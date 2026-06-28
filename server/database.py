import datetime
import logging
from sqlalchemy import create_engine, Column, String, Float, Boolean, DateTime, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

logger = logging.getLogger("expense_tracker_server")

SQLALCHEMY_DATABASE_URL = "sqlite:///./transactions.db"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(String(36), primary_key=True, index=True)
    raw_input = Column(String, nullable=False)
    amount = Column(Float, nullable=False)
    description = Column(String, nullable=True)
    tag = Column(String(50), nullable=True)
    merchant = Column(String(100), nullable=True)
    display_label = Column(String(150), nullable=True)
    ai_confidence = Column(Float, nullable=True)
    is_recurring = Column(Boolean, default=False)
    sync_status = Column(String(20), default="pending")  # pending, processing, completed, failed
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)

def _migrate_display_label():
    with engine.connect() as conn:
        try:
            conn.execute(text("ALTER TABLE transactions ADD COLUMN display_label TEXT"))
            conn.commit()
            logger.info("Added display_label column to transactions table.")
        except Exception:
            conn.rollback()

def init_db():
    Base.metadata.create_all(bind=engine)
    _migrate_display_label()


def normalize_all_tags() -> None:
    from categories import normalize_category

    db = SessionLocal()
    updated = 0
    try:
        for tx in db.query(Transaction).all():
            normalized = normalize_category(tx.tag)
            if tx.tag != normalized:
                tx.tag = normalized
                updated += 1
        if updated:
            db.commit()
            logger.info("Normalized tags on %s transaction(s).", updated)
    finally:
        db.close()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
