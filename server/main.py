import os
import json
import logging
import asyncio
import datetime
from typing import List, Optional
from fastapi import FastAPI, BackgroundTasks, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
import httpx

from database import init_db, get_db, Transaction, SessionLocal

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("expense_tracker_server")

# Load configuration
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen3:8b")
OLLAMA_SOFT_TIMEOUT = float(os.getenv("OLLAMA_SOFT_TIMEOUT", "60"))
OLLAMA_HARD_TIMEOUT = float(os.getenv("OLLAMA_HARD_TIMEOUT", "300"))

app = FastAPI(title="Asynchronous Expense Tracker API Gateway")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize database tables on startup
@app.on_event("startup")
def on_startup():
    init_db()
    logger.info("Database initialized successfully.")

# Pydantic Schemas
class TransactionSyncItem(BaseModel):
    id: str
    raw_input: str = Field(..., alias="raw_input")
    amount: float
    description: Optional[str] = None
    tag: Optional[str] = None
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
    ai_confidence: Optional[float]
    is_recurring: bool
    sync_status: str
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True

class DeleteSyncRequest(BaseModel):
    ids: List[str]

class DeleteSyncResponse(BaseModel):
    status: str
    deleted: int

# System prompt for Ollama
OLLAMA_SYSTEM_PROMPT = """You are an isolated financial intelligence string extraction parser microservice engine.
Your specific structural instructions are to accept raw, single-line data entries and resolve them into perfectly compliant structured parameters without additional narrative text wrapper outputs.

You must format output streams to match the parameters of this designated JSON schema map:
{
  "amount": float,
  "category": string,
  "confidence": float (range 0.00 to 1.00),
  "merchant": string or null,
  "is_recurring": boolean
}"""

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

class EnrichmentManager:
    """Tracks in-flight Ollama jobs so retries never cancel an active enrichment."""

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
            await asyncio.wait_for(asyncio.shield(task), timeout=OLLAMA_SOFT_TIMEOUT)
        except asyncio.TimeoutError:
            logger.warning(
                f"Enrichment soft-timeout for {tx_id} after {OLLAMA_SOFT_TIMEOUT}s; "
                "continuing to wait for Ollama in background"
            )
        except Exception:
            # Errors are logged and persisted inside _run_enrichment.
            pass

    async def _call_ollama(self, raw_input: str) -> dict:
        timeout = httpx.Timeout(
            connect=10.0,
            read=OLLAMA_HARD_TIMEOUT,
            write=10.0,
            pool=10.0,
        )
        payload = {
            "model": OLLAMA_MODEL,
            "messages": [
                {"role": "system", "content": OLLAMA_SYSTEM_PROMPT},
                {"role": "user", "content": raw_input},
            ],
            "format": "json",
            "stream": False,
            "options": {"temperature": 0.1},
        }

        async with httpx.AsyncClient(timeout=timeout) as client:
            logger.info(f"Sending request to Ollama: {OLLAMA_URL}/api/chat with model {OLLAMA_MODEL}")
            response = await client.post(f"{OLLAMA_URL}/api/chat", json=payload)

        if response.status_code != 200:
            raise RuntimeError(
                f"Ollama server returned status code {response.status_code}: {response.text}"
            )

        resp_data = response.json()
        message_content = resp_data.get("message", {}).get("content", "").strip()

        if message_content.startswith("```"):
            lines = message_content.splitlines()
            if len(lines) >= 3:
                message_content = "\n".join(lines[1:-1])

        logger.info(f"Received response from Ollama: {message_content}")
        return json.loads(message_content)

    def _apply_enrichment(self, db_session: Session, tx_id: str, result: dict) -> None:
        db_tx = db_session.query(Transaction).filter(Transaction.id == tx_id).first()
        if not db_tx:
            logger.error(f"Transaction {tx_id} not found when applying enrichment.")
            return

        db_tx.merchant = result.get("merchant")
        if result.get("category"):
            db_tx.tag = result.get("category")
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
                result = await self._call_ollama(raw_input)
                self._apply_enrichment(db_session, tx_id, result)
            except httpx.TimeoutException:
                logger.error(
                    f"Enrichment hard-timeout for {tx_id} after {OLLAMA_HARD_TIMEOUT}s"
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
                    tag=item.tag,
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
                    or db_tx.tag != (item.tag or "")
                )
                db_tx.raw_input = item.raw_input
                db_tx.amount = item.amount
                db_tx.description = item.description
                db_tx.tag = item.tag
                apply_client_created_at(db_tx, item)
                if content_changed:
                    db_tx.merchant = None
                    db_tx.ai_confidence = None
                    db_tx.is_recurring = False
                    db_tx.sync_status = "pending"
                db_session.commit()

            if db_tx.sync_status in ("pending", "failed"):
                await enrich_transaction_with_ollama(db_tx.id, db_tx.raw_input)
            elif db_tx.sync_status == "processing" and not enrichment_manager.is_in_flight(db_tx.id):
                logger.info(
                    f"Transaction {db_tx.id} is processing with no active job; restarting enrichment"
                )
                await enrich_transaction_with_ollama(db_tx.id, db_tx.raw_input)
    finally:
        db_session.close()

# Endpoints

@app.post("/api/v1/sync", status_code=status.HTTP_202_ACCEPTED, response_model=SyncResponse)
def sync_transactions(
    payload: SyncRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """
    Sync endpoint that ingests client transactions, returns 202 immediately,
    and processes the transactions in the background via Ollama.
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
                tag=item.tag,
                sync_status="pending"
            )
            db.add(db_tx)
            apply_client_created_at(db_tx, item)
        else:
            content_changed = (
                db_tx.raw_input != item.raw_input
                or db_tx.amount != item.amount
                or db_tx.description != (item.description or "")
                or db_tx.tag != (item.tag or "")
            )
            db_tx.raw_input = item.raw_input
            db_tx.amount = item.amount
            db_tx.description = item.description
            db_tx.tag = item.tag
            apply_client_created_at(db_tx, item)
            if content_changed:
                db_tx.merchant = None
                db_tx.ai_confidence = None
                db_tx.is_recurring = False
                db_tx.sync_status = "pending"
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
    
    response_items = []
    for tx in transactions:
        response_items.append(
            EnrichedTransactionResponse(
                id=tx.id,
                raw_input=tx.raw_input,
                amount=tx.amount,
                description=tx.description or "",
                tag=tx.tag or "",
                merchant=tx.merchant,
                ai_confidence=tx.ai_confidence,
                is_recurring=tx.is_recurring,
                sync_status=tx.sync_status,
                created_at=tx.created_at.isoformat(),
                updated_at=tx.updated_at.isoformat()
            )
        )
    return response_items

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
        or db_tx.tag != (item.tag or "")
    )
    db_tx.raw_input = item.raw_input
    db_tx.amount = item.amount
    db_tx.description = item.description
    db_tx.tag = item.tag
    apply_client_created_at(db_tx, item)
    if content_changed:
        db_tx.merchant = None
        db_tx.ai_confidence = None
        db_tx.is_recurring = False
        db_tx.sync_status = "pending"
    db.commit()
    db.refresh(db_tx)

    if db_tx.sync_status in ("pending", "failed", "processing"):
        background_tasks.add_task(run_sync_pipeline, [item])

    return EnrichedTransactionResponse(
        id=db_tx.id,
        raw_input=db_tx.raw_input,
        amount=db_tx.amount,
        description=db_tx.description or "",
        tag=db_tx.tag or "",
        merchant=db_tx.merchant,
        ai_confidence=db_tx.ai_confidence,
        is_recurring=db_tx.is_recurring,
        sync_status=db_tx.sync_status,
        created_at=db_tx.created_at.isoformat(),
        updated_at=db_tx.updated_at.isoformat(),
    )

@app.get("/health")
def health_check():
    return {"status": "ok", "ollama_url": OLLAMA_URL, "ollama_model": OLLAMA_MODEL}
