# -*- coding: utf-8 -*-
"""
應用程式設定。所有敏感值（DB連線密碼、PII加密金鑰）皆從環境變數讀取，
不寫死在程式碼中。本地開發可透過 .env 檔案或直接設定環境變數提供。
"""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # PostgreSQL 連線設定
    pg_host: str = "localhost"
    pg_port: int = 5432
    pg_dbname: str = "postgres"
    pg_user: str = "postgres"
    pg_password: str = ""
    pg_sslmode: str = "prefer"  # 本地測試用 disable/prefer；連線 AWS RDS 建議 require

    # PII 欄位 AES-256-GCM 加密金鑰（base64, 32 bytes 解碼後）。
    # 未設定時，PII 加密/解密功能會停用（寫入時只存 hash，bytea 欄位存 NULL），
    # 避免在沒有金鑰的情況下產生無法復原的假密文。
    pii_encryption_key_b64: str | None = None

    # API 是否啟用簡易 CORS（本地開發用）
    cors_allow_origins: str = "*"

    @property
    def database_url(self) -> str:
        return (
            f"postgresql+psycopg2://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{self.pg_port}/{self.pg_dbname}?sslmode={self.pg_sslmode}"
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
