# -*- coding: utf-8 -*-
"""
PII 欄位加解密工具，對應 schema 中標註「AES-256-GCM 加密」的 bytea 欄位
（member_name/member_phone/member_email、contact_name/contact_mobile/
contact_landline/contact_email/contact_address_detail）。

設計說明：
- 加密格式：nonce(12 bytes) + ciphertext+tag，一併存入 bytea 欄位。
- 若未設定 PII_ENCRYPTION_KEY_B64 環境變數，encrypt/decrypt 皆回傳 None，
  對應欄位在寫入時存 NULL、讀取時回傳 None，不會用假資料填充，
  避免產生「看起來加密但實際上無法被任何金鑰解開」的誤導性資料。
- _hash 欄位一律用 SHA-256 + Base64 產生，與現有範例資料格式一致，
  不受是否設定加密金鑰影響，確保查詢比對功能永遠可用。
"""
import base64
import hashlib
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.config import get_settings

_NONCE_SIZE = 12


def _get_key() -> bytes | None:
    settings = get_settings()
    if not settings.pii_encryption_key_b64:
        return None
    key = base64.b64decode(settings.pii_encryption_key_b64)
    if len(key) != 32:
        raise ValueError("PII_ENCRYPTION_KEY_B64 解碼後必須為 32 bytes（AES-256）")
    return key


def encrypt_pii(plain_text: str | None) -> bytes | None:
    if plain_text is None:
        return None
    key = _get_key()
    if key is None:
        return None
    aesgcm = AESGCM(key)
    nonce = os.urandom(_NONCE_SIZE)
    ciphertext = aesgcm.encrypt(nonce, plain_text.encode("utf-8"), None)
    return nonce + ciphertext


def decrypt_pii(cipher_bytes: bytes | None) -> str | None:
    if cipher_bytes is None:
        return None
    key = _get_key()
    if key is None:
        return None
    if len(cipher_bytes) <= _NONCE_SIZE:
        return None
    nonce, ciphertext = cipher_bytes[:_NONCE_SIZE], cipher_bytes[_NONCE_SIZE:]
    aesgcm = AESGCM(key)
    try:
        plain = aesgcm.decrypt(nonce, ciphertext, None)
        return plain.decode("utf-8")
    except Exception:
        # 金鑰不符或資料非本系統加密產生（如既有範例種子資料），無法解密，回傳 None。
        return None


def sha256_hash(plain_text: str | None) -> str | None:
    if plain_text is None:
        return None
    digest = hashlib.sha256(plain_text.encode("utf-8")).digest()
    return base64.b64encode(digest).decode("utf-8")
