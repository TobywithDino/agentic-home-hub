# -*- coding: utf-8 -*-
"""共用工具函式：UUID v7 產生、分頁查詢、系統操作者識別碼。"""
import datetime as dt
import os
import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.deps import PageParams

# 目前 API 沒有身分驗證中介層（見專案README安全性提醒），
# 對於「操作者(cre_id/upd_id)」欄位，管理端CRUD操作暫以此系統識別碼填入。
# 待未來加上認證機制後，應改用實際登入者的 uuid。
SYSTEM_ACTOR_ID = uuid.UUID("00000000-0000-7000-8000-000000000000")


def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def uuid7() -> uuid.UUID:
    """產生符合 README 規範的 UUID v7（第3段開頭7代表版本、第4段開頭8~b代表變體）。"""
    ms = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    ts_bytes = ms.to_bytes(6, byteorder="big")
    rand_bytes = os.urandom(10)
    b = bytearray(ts_bytes + rand_bytes)
    b[6] = (b[6] & 0x0F) | 0x70
    b[8] = (b[8] & 0x3F) | 0x80
    return uuid.UUID(bytes=bytes(b))


def paginate(db: Session, stmt, pp: PageParams):
    """對任意 select() stmt 執行分頁查詢，回傳 (items, total)。"""
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    items = db.execute(stmt.limit(pp.limit).offset(pp.offset)).scalars().all()
    return items, total or 0
