import logging
import asyncio
import datetime
import uuid
from pathlib import Path
from typing import List, Literal, Optional
from fastapi import FastAPI, BackgroundTasks, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
import httpx

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")

from database import init_db, get_db, Transaction, SessionLocal, normalize_all_tags
from categories import category_prompt_block, normalize_category
from llm_client import (
    ENRICHMENT_HARD_TIMEOUT,
    ENRICHMENT_SOFT_TIMEOUT,
    call_llm,
    enrichment_health,
    openrouter_client_config,
)

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("expense_tracker_server")

app = FastAPI(title="Asynchronous Expense Tracker API Gateway")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize database tables on startup
@app.on_event("startup")
async def on_startup():
    init_db()
    normalize_all_tags()
    logger.info("Database initialized successfully.")
    asyncio.create_task(recover_stuck_enrichments())

# Pydantic Schemas
class TransactionSyncItem(BaseModel):
    id: str
    raw_input: str = Field(..., alias="raw_input")
    amount: float
    description: Optional[str] = None
    tag: Optional[str] = None
    merchant: Optional[str] = None
    display_label: Optional[str] = Field(None, alias="display_label")
    ai_confidence: Optional[float] = Field(None, alias="ai_confidence")
    is_recurring: bool = Field(False, alias="is_recurring")
    sync_status: str = "pending"
    created_at: Optional[str] = None

    class Config:
        populate_by_name = True

class SyncRequest(BaseModel):
    transactions: List[TransactionSyncItem]

class SyncResponse(BaseModel):
    status: str
    message: str

class EnrichedTransactionResponse(BaseModel):
    id: str
    raw_input: str
    amount: float
    description: Optional[str]
    tag: Optional[str]
    merchant: Optional[str]
    display_label: Optional[str] = None
    ai_confidence: Optional[float]
    is_recurring: bool
    sync_status: str
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True

class ImportRequest(BaseModel):
    content: str
    format: Literal["text", "csv"] = "text"

class ImportResponse(BaseModel):
    status: str
    message: str

class DeleteSyncRequest(BaseModel):
    ids: List[str]

class DeleteSyncResponse(BaseModel):
    status: str
    deleted: int

class EnrichmentConfigResponse(BaseModel):
    configured: bool
    openrouter_api_key: Optional[str] = None
    openrouter_model: str = "openrouter/free"

# System prompts for LLM enrichment
_CATEGORY_RULES = category_prompt_block()

ENRICHMENT_SYSTEM_PROMPT = f"""You are an isolated financial intelligence string extraction parser microservice engine.
Your specific structural instructions are to accept raw, single-line data entries and resolve them into perfectly compliant structured parameters without additional narrative text wrapper outputs.

You must format output streams to match the parameters of this designated JSON schema map:
{{
  "amount": float,
  "category": string,
  "confidence": float (range 0.00 to 1.00),
  "merchant": string or null,
  "is_recurring": boolean,
  "display_label": string
}}

{_CATEGORY_RULES}

The display_label must be a short (max 50 characters), title-case, human-readable summary suitable for a mobile UI.
Do not include hashtags, currency symbols, or raw tag markers in display_label.
Example: "Zoom Subscription Renewal" instead of "zoom subscription renewal @work"."""

ENRICHMENT_IMPORT_SYSTEM_PROMPT = f"""You are a bulk financial transaction import parser.
Accept multi-line plain text or CSV file content and extract every expense transaction.

Return JSON matching this schema:
{{
  "transactions": [
    {{
      "raw_input": "original line or CSV row text exactly as provided",
      "amount": float,
      "description": "fallback plain description without tags or currency symbols",
      "tag": "canonical category string",
      "display_label": "short human-readable title, max 50 chars, title-case",
      "created_at": "YYYY-MM-DD or null if unknown"
    }}
  ]
}}

{_CATEGORY_RULES}

Rules:
- One transaction per non-empty line (text) or data row (CSV).
- Date lines (e.g. MM/DD or MM/DD/YYYY on their own line) apply to following transactions until the next date line.
- Skip header rows in CSV files.
- tag must use a canonical category value from the list above.
- display_label must be user-friendly and suitable for a 2-line mobile UI label.
- Preserve raw_input verbatim for each parsed entry."""

def parse_client_datetime(value: Optional[str]) -> Optional[datetime.datetime]:
    if not value:
        return None
    try:
        return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).replace(tzinfo=None)
    except ValueError:
        return None

def apply_client_created_at(db_tx: Transaction, item: TransactionSyncItem) -> None:
    parsed = parse_client_datetime(item.created_at)
    if parsed:
        db_tx.created_at = parsed

def apply_import_created_at(db_tx: Transaction, created_at: Optional[str]) -> None:
    parsed = parse_client_datetime(created_at)
    if parsed:
        current_year = datetime.datetime.now().year
        if parsed.year != current_year:
            parsed = parsed.replace(year=current_year)
        db_tx.created_at = parsed


def client_tag(item: TransactionSyncItem) -> str:
    return normalize_category(item.tag or "uncategorized")


def client_provided_enrichment(item: TransactionSyncItem) -> bool:
    return bool(item.display_label and str(item.display_label).strip())


def apply_client_enrichment(db_tx: Transaction, item: TransactionSyncItem) -> None:
    db_tx.merchant = item.merchant
    db_tx.display_label = str(item.display_label).strip()
    db_tx.ai_confidence = item.ai_confidence
    db_tx.is_recurring = item.is_recurring
    db_tx.tag = client_tag(item)
    db_tx.sync_status = "completed"

def transaction_to_response(tx: Transaction) -> EnrichedTransactionResponse:
    return EnrichedTransactionResponse(
        id=tx.id,
        raw_input=tx.raw_input,
        amount=tx.amount,
        description=tx.description or "",
        tag=tx.tag or "",
        merchant=tx.merchant,
        display_label=tx.display_label,
        ai_confidence=tx.ai_confidence,
        is_recurring=tx.is_recurring,
        sync_status=tx.sync_status,
        created_at=tx.created_at.isoformat(),
        updated_at=tx.updated_at.isoformat(),
    )

def clear_enrichment_fields(db_tx: Transaction) -> None:
    db_tx.merchant = None
    db_tx.display_label = None
    db_tx.ai_confidence = None
    db_tx.is_recurring = False
    db_tx.sync_status = "pending"

class EnrichmentManager:
    """Tracks in-flight LLM jobs so retries never cancel an active enrichment."""

    def __init__(self):
        self._tasks: dict[str, asyncio.Task] = {}
        self._lock = asyncio.Lock()

    def is_in_flight(self, tx_id: str) -> bool:
        task = self._tasks.get(tx_id)
        return task is not None and not task.done()

    async def ensure_enrichment(self, tx_id: str, raw_input: str) -> None:
        async with self._lock:
            if self.is_in_flight(tx_id):
                logger.info(
                    f"Enrichment already in flight for {tx_id}; keeping existing request alive"
                )
                return
            task = asyncio.create_task(self._run_enrichment(tx_id, raw_input))
            self._tasks[tx_id] = task

        try:
            await asyncio.wait_for(asyncio.shield(task), timeout=ENRICHMENT_SOFT_TIMEOUT)
        except asyncio.TimeoutError:
            logger.warning(
                f"Enrichment soft-timeout for {tx_id} after {ENRICHMENT_SOFT_TIMEOUT}s; "
                "continuing to wait for LLM in background"
            )
        except Exception:
            # Errors are logged and persisted inside _run_enrichment.
            pass

    async def _call_llm(
        self,
        raw_input: str,
        system_prompt: str = ENRICHMENT_SYSTEM_PROMPT,
        *,
        think: Optional[bool] = None,
    ) -> dict:
        return await call_llm(raw_input, system_prompt, think=think)

    def _apply_enrichment(self, db_session: Session, tx_id: str, result: dict) -> None:
        db_tx = db_session.query(Transaction).filter(Transaction.id == tx_id).first()
        if not db_tx:
            logger.error(f"Transaction {tx_id} not found when applying enrichment.")
            return

        db_tx.merchant = result.get("merchant")
        if result.get("category"):
            db_tx.tag = normalize_category(result.get("category"))
        if result.get("display_label"):
            db_tx.display_label = result.get("display_label")
        db_tx.ai_confidence = result.get("confidence", 1.0)
        db_tx.is_recurring = result.get("is_recurring", False)
        db_tx.sync_status = "completed"
        db_session.commit()
        logger.info(f"Successfully enriched transaction: {tx_id}")

    def _mark_failed(self, db_session: Session, tx_id: str) -> None:
        db_tx = db_session.query(Transaction).filter(Transaction.id == tx_id).first()
        if db_tx and db_tx.sync_status != "completed":
            db_tx.sync_status = "failed"
            db_session.commit()

    async def _run_enrichment(self, tx_id: str, raw_input: str) -> None:
        db_session = SessionLocal()
        try:
            logger.info(f"Starting LLM enrichment for transaction: {tx_id} ('{raw_input}')")
            db_tx = db_session.query(Transaction).filter(Transaction.id == tx_id).first()
            if not db_tx:
                logger.error(f"Transaction {tx_id} not found in database for enrichment.")
                return

            db_tx.sync_status = "processing"
            db_session.commit()

            try:
                result = await self._call_llm(raw_input, think=False)
                self._apply_enrichment(db_session, tx_id, result)
            except httpx.TimeoutException:
                logger.error(
                    f"Enrichment hard-timeout for {tx_id} after {ENRICHMENT_HARD_TIMEOUT}s"
                )
                self._mark_failed(db_session, tx_id)
            except Exception as e:
                logger.error(f"Failed to enrich transaction {tx_id}: {str(e)}")
                self._mark_failed(db_session, tx_id)
        finally:
            db_session.close()
            async with self._lock:
                if self._tasks.get(tx_id) is asyncio.current_task():
                    self._tasks.pop(tx_id, None)


enrichment_manager = EnrichmentManager()

async def recover_stuck_enrichments() -> None:
    """Re-queue or finalize transactions left in processing after a crash or slow import."""
    await asyncio.sleep(1)
    db_session = SessionLocal()
    try:
        stuck = db_session.query(Transaction).filter(Transaction.sync_status == "processing").all()
        if not stuck:
            return

        logger.info(f"Recovering {len(stuck)} transaction(s) stuck in processing")
        finalized = 0
        requeued: List[str] = []

        for db_tx in stuck:
            if enrichment_manager.is_in_flight(db_tx.id):
                continue
            if db_tx.display_label:
                db_tx.sync_status = "completed"
                db_session.commit()
                finalized += 1
                logger.info(f"Finalized imported transaction {db_tx.id} (already has display_label)")
            else:
                requeued.append(db_tx.id)

        if finalized:
            logger.info(f"Marked {finalized} imported transaction(s) as completed")

        for tx_id in requeued:
            db_tx = db_session.query(Transaction).filter(Transaction.id == tx_id).first()
            if db_tx:
                logger.info(f"Re-queuing enrichment for stuck transaction {tx_id}")
                await enrich_transaction_with_ollama(db_tx.id, db_tx.raw_input)
    finally:
        db_session.close()

async def enrich_transaction_with_ollama(tx_id: str, raw_input: str, db_session: Optional[Session] = None):
    await enrichment_manager.ensure_enrichment(tx_id, raw_input)

async def run_sync_pipeline(items: List[TransactionSyncItem]):
    db_session = SessionLocal()
    try:
        for item in items:
            db_tx = db_session.query(Transaction).filter(Transaction.id == item.id).first()
            if not db_tx:
                db_tx = Transaction(
                    id=item.id,
                    raw_input=item.raw_input,
                    amount=item.amount,
                    description=item.description,
                    tag=client_tag(item),
                    sync_status="pending"
                )
                db_session.add(db_tx)
                apply_client_created_at(db_tx, item)
                db_session.commit()
                db_session.refresh(db_tx)
            else:
                content_changed = (
                    db_tx.raw_input != item.raw_input
                    or db_tx.amount != item.amount
                    or db_tx.description != (item.description or "")
                    or db_tx.tag != client_tag(item)
                )
                db_tx.raw_input = item.raw_input
                db_tx.amount = item.amount
                db_tx.description = item.description
                db_tx.tag = client_tag(item)
                apply_client_created_at(db_tx, item)
                if content_changed:
                    clear_enrichment_fields(db_tx)
                db_session.commit()

            if client_provided_enrichment(item):
                apply_client_enrichment(db_tx, item)
                db_session.commit()
                logger.info(
                    f"Transaction {db_tx.id} enriched by client; skipping server LLM"
                )
                continue

            if db_tx.sync_status in ("pending", "failed"):
                await enrich_transaction_with_ollama(db_tx.id, db_tx.raw_input)
            elif db_tx.sync_status == "processing" and not enrichment_manager.is_in_flight(db_tx.id):
                logger.info(
                    f"Transaction {db_tx.id} is processing with no active job; restarting enrichment"
                )
                await enrich_transaction_with_ollama(db_tx.id, db_tx.raw_input)
    finally:
        db_session.close()

async def call_llm_import(content: str, file_format: str) -> List[dict]:
    user_content = f"Format: {file_format}\n\n{content}"
    result = await enrichment_manager._call_llm(
        user_content,
        system_prompt=ENRICHMENT_IMPORT_SYSTEM_PROMPT,
        think=False,
    )
    transactions = result.get("transactions", [])
    if not isinstance(transactions, list):
        raise ValueError("Import response missing transactions array")
    return transactions

async def run_import_pipeline(content: str, file_format: str) -> None:
    line_count = len([line for line in content.splitlines() if line.strip()])
    logger.info(
        f"Starting background import pipeline: format={file_format}, "
        f"chars={len(content)}, non_empty_lines={line_count}"
    )

    try:
        logger.info("Calling LLM to parse import file")
        parsed_items = await call_llm_import(content, file_format)
        logger.info(f"LLM returned {len(parsed_items)} parsed item(s)")
    except Exception as e:
        logger.error(f"Background import parsing failed: {e}", exc_info=True)
        return

    if not parsed_items:
        logger.warning("Import file contained no parseable transactions")
        return

    db_session = SessionLocal()
    tx_ids: List[str] = []
    skipped = 0
    try:
        for item in parsed_items:
            if not isinstance(item, dict):
                skipped += 1
                logger.warning(f"Skipping non-dict import row: {item!r}")
                continue
            raw_input = (item.get("raw_input") or "").strip()
            amount = item.get("amount")
            if not raw_input or amount is None:
                skipped += 1
                logger.warning(f"Skipping invalid import row: {item}")
                continue

            tx_id = str(uuid.uuid4())
            db_tx = Transaction(
                id=tx_id,
                raw_input=raw_input,
                amount=float(amount),
                description=item.get("description") or raw_input,
                tag=normalize_category(item.get("tag") or "uncategorized"),
                display_label=item.get("display_label"),
                sync_status="completed",
            )
            apply_import_created_at(db_tx, item.get("created_at"))
            db_session.add(db_tx)
            tx_ids.append(tx_id)
            logger.info(
                f"Queued import transaction {tx_id}: amount={db_tx.amount}, "
                f"raw_input={raw_input!r}"
            )

        db_session.commit()
        logger.info(
            f"Background import persisted {len(tx_ids)} transaction(s) "
            f"({skipped} row(s) skipped)"
        )
    except Exception as e:
        logger.error(f"Background import failed while saving transactions: {e}", exc_info=True)
        return
    finally:
        db_session.close()

    if not tx_ids:
        logger.warning("Import pipeline finished with no transactions saved")
        return

    logger.info(f"Background import pipeline finished for {len(tx_ids)} transaction(s)")

# Endpoints

@app.post("/api/v1/sync", status_code=status.HTTP_202_ACCEPTED, response_model=SyncResponse)
def sync_transactions(
    payload: SyncRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """
    Sync endpoint that ingests client transactions, returns 202 immediately,
    and processes the transactions in the background via the configured LLM provider.
    """
    if not payload.transactions:
        return {"status": "success", "message": "No transactions to sync"}

    # Upsert into SQLite DB immediately to preserve state
    for item in payload.transactions:
        db_tx = db.query(Transaction).filter(Transaction.id == item.id).first()
        if not db_tx:
            db_tx = Transaction(
                id=item.id,
                raw_input=item.raw_input,
                amount=item.amount,
                description=item.description,
                tag=client_tag(item),
                sync_status="pending"
            )
            db.add(db_tx)
            apply_client_created_at(db_tx, item)
        else:
            content_changed = (
                db_tx.raw_input != item.raw_input
                or db_tx.amount != item.amount
                or db_tx.description != (item.description or "")
                or db_tx.tag != client_tag(item)
            )
            db_tx.raw_input = item.raw_input
            db_tx.amount = item.amount
            db_tx.description = item.description
            db_tx.tag = client_tag(item)
            apply_client_created_at(db_tx, item)
            if content_changed:
                clear_enrichment_fields(db_tx)
    db.commit()

    # Dispatch to background task execution
    background_tasks.add_task(run_sync_pipeline, payload.transactions)

    return {
        "status": "accepted",
        "message": f"Processing sync for {len(payload.transactions)} transactions in background."
    }

@app.get("/api/v1/sync/status", response_model=List[EnrichedTransactionResponse])
def get_sync_status(
    ids: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """
    Retrieves the sync state and enriched properties of transactions.
    Optional query parameter: 'ids' (comma-separated list of transaction UUIDs).
    If no ids are provided, returns all transactions.
    """
    query = db.query(Transaction)
    if ids:
        id_list = [i.strip() for i in ids.split(",") if i.strip()]
        query = query.filter(Transaction.id.in_(id_list))
    
    transactions = query.all()
    return [transaction_to_response(tx) for tx in transactions]

@app.post("/api/v1/import", status_code=status.HTTP_202_ACCEPTED, response_model=ImportResponse)
async def import_transactions(
    payload: ImportRequest,
    background_tasks: BackgroundTasks,
):
    content = payload.content.strip()
    if not content:
        raise HTTPException(status_code=400, detail="Import content cannot be empty")

    background_tasks.add_task(run_import_pipeline, content, payload.format)

    return ImportResponse(
        status="accepted",
        message="Import submitted; transactions will appear after the next sync",
    )

@app.post("/api/v1/sync/deletes", response_model=DeleteSyncResponse)
def sync_deletes(payload: DeleteSyncRequest, db: Session = Depends(get_db)):
    """Removes transactions from the server when deleted on the client."""
    deleted = 0
    for tx_id in payload.ids:
        db_tx = db.query(Transaction).filter(Transaction.id == tx_id).first()
        if db_tx:
            db.delete(db_tx)
            deleted += 1
    db.commit()
    return {"status": "success", "deleted": deleted}

@app.delete("/api/v1/transactions/{tx_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_transaction(tx_id: str, db: Session = Depends(get_db)):
    db_tx = db.query(Transaction).filter(Transaction.id == tx_id).first()
    if not db_tx:
        raise HTTPException(status_code=404, detail="Transaction not found")
    db.delete(db_tx)
    db.commit()

@app.put("/api/v1/transactions/{tx_id}", response_model=EnrichedTransactionResponse)
def update_transaction(
    tx_id: str,
    item: TransactionSyncItem,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    db_tx = db.query(Transaction).filter(Transaction.id == tx_id).first()
    if not db_tx:
        raise HTTPException(status_code=404, detail="Transaction not found")

    content_changed = (
        db_tx.raw_input != item.raw_input
        or db_tx.amount != item.amount
        or db_tx.description != (item.description or "")
        or db_tx.tag != client_tag(item)
    )
    db_tx.raw_input = item.raw_input
    db_tx.amount = item.amount
    db_tx.description = item.description
    db_tx.tag = client_tag(item)
    apply_client_created_at(db_tx, item)
    if content_changed:
        clear_enrichment_fields(db_tx)
    db.commit()
    db.refresh(db_tx)

    if content_changed or db_tx.sync_status in ("pending", "failed", "processing"):
        background_tasks.add_task(run_sync_pipeline, [item])

    return transaction_to_response(db_tx)

@app.get("/health")
def health_check():
    return enrichment_health()

@app.get("/api/v1/enrichment/config", response_model=EnrichmentConfigResponse)
def get_enrichment_config():
    """Shares the tailnet OpenRouter credentials with connected clients."""
    return EnrichmentConfigResponse(**openrouter_client_config())
