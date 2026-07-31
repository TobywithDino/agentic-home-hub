# -*- coding: utf-8 -*-
"""
密碼雜湊工具。用於 user_accounts / vendor_accounts 的 password_hash 欄位。
採用 bcrypt（不可逆雜湊），符合 schema 註解「不可逆雜湊演算法儲存,如bcrypt/argon2」。
"""
import bcrypt


def hash_password(plain_password: str) -> str:
    return bcrypt.hashpw(plain_password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain_password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode("utf-8"), password_hash.encode("utf-8"))
    except (ValueError, TypeError):
        # password_hash 格式不是合法 bcrypt hash（例如舊資料損毀），視為驗證失敗
        return False
