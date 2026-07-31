# -*- coding: utf-8 -*-
"""
資料庫連線層。使用 SQLAlchemy Session，透過 FastAPI 依賴注入提供給每個請求，
並確保每個請求結束後正確關閉連線。

注意：本專案不執行 Base.metadata.create_all()，因為資料表已由
database/ 內的 DDL 腳本與 import_seed_data.py 建立完成，這裡的 ORM
model 只負責「映射」既有 schema，不負責建表，避免與正式建置流程衝突。
"""
from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import get_settings

settings = get_settings()

engine = create_engine(settings.database_url, pool_pre_ping=True, future=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
