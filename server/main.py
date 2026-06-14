import os
import json
import logging
import asyncio
from typing import List, Optional
from fastapi import FastAPI, BackgroundTasks, Depends, HTTPException, status
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

app = FastAPI(title="Asynchronous Expense Tracker API Gateway")

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

async def enrich_transaction_with_ollama(tx_id: str, raw_input: str, db_session: Session):
    logger.info(f"Starting LLM enrichment for transaction: {tx_id} ('{raw_input}')")
    
    # 1. Update status to processing
    db_tx = db_session.query(Transaction).filter(Transaction.id == tx_id).first()
    if not db_tx:
        logger.error(f"Transaction {tx_id} not found in database for enrichment.")
        return
    
    db_tx.sync_status = "processing"
    db_session.commit()

    try:
        # 2. Call Ollama API
        async with httpx.AsyncClient(timeout=30.0) as client:
            payload = {
                "model": OLLAMA_MODEL,
                "messages": [
                    {"role": "system", "content": OLLAMA_SYSTEM_PROMPT},
                    {"role": "user", "content": raw_input}
                ],
                "format": "json",
                "stream": False,
                "options": {
                    "temperature": 0.1
                }
            }
            
            logger.info(f"Sending request to Ollama: {OLLAMA_URL}/api/chat with model {OLLAMA_MODEL}")
            response = await client.post(f"{OLLAMA_URL}/api/chat", json=payload)
            
            if response.status_code != 200:
                raise Exception(f"Ollama server returned status code {response.status_code}: {response.text}")
            
            resp_data = response.json()
            message_content = resp_data.get("message", {}).get("content", "").strip()
            
            # Clean potential markdown block formatting from JSON output
            if message_content.startswith("```"):
                lines = message_content.splitlines()
                if len(lines) >= 3:
                    message_content = "\n".join(lines[1:-1])
            
            logger.info(f"Received response from Ollama: {message_content}")
            result = json.loads(message_content)
            
            # 3. Apply enrichment to database record
            db_tx.merchant = result.get("merchant")
            if result.get("category"):
                db_tx.tag = result.get("category")
            db_tx.ai_confidence = result.get("confidence", 1.0)
            db_tx.is_recurring = result.get("is_recurring", False)
            db_tx.sync_status = "completed"
            
            db_session.commit()
            logger.info(f"Successfully enriched transaction: {tx_id}")

    except Exception as e:
        logger.error(f"Failed to enrich transaction {tx_id}: {str(e)}")
        # Reload transaction in session if it's detatched or stale
        try:
            db_tx = db_session.query(Transaction).filter(Transaction.id == tx_id).first()
            if db_tx:
                db_tx.sync_status = "failed"
                db_session.commit()
        except Exception as commit_ex:
            logger.error(f"Failed to save failure status for {tx_id}: {str(commit_ex)}")

async def run_sync_pipeline(items: List[TransactionSyncItem]):
    db_session = SessionLocal()
    try:
        for item in items:
            # Check if already exists in DB
            db_tx = db_session.query(Transaction).filter(Transaction.id == item.id).first()
            if not db_tx:
                # Create a new local record on the server
                db_tx = Transaction(
                    id=item.id,
                    raw_input=item.raw_input,
                    amount=item.amount,
                    description=item.description,
                    tag=item.tag,
                    sync_status="pending"
                )
                db_session.add(db_tx)
                db_session.commit()
                db_session.refresh(db_tx)
            
            # Only run LLM parser if it hasn't completed successfully
            if db_tx.sync_status in ("pending", "failed", "processing"):
                await enrich_transaction_with_ollama(db_tx.id, db_tx.raw_input, db_session)
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

    # Add to SQLite DB immediately as 'pending' / 'processing' to preserve state
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

@app.get("/health")
def health_check():
    return {"status": "ok", "ollama_url": OLLAMA_URL, "ollama_model": OLLAMA_MODEL}
