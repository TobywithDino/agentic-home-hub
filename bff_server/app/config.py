# -*- coding: utf-8 -*-
"""
BFF 層設定。所有可能因環境而異的值（隊友 DB Access API 的位址等）
都從環境變數讀取，本地開發可透過 .env 檔案提供。
"""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # 隊友的 DB Access API (Database/api_server) 位址
    db_api_base_url: str = "http://127.0.0.1:8000"

    # 本層自己對前端的 CORS 設定（本地開發用）
    cors_allow_origins: str = "*"


@lru_cache
def get_settings() -> Settings:
    return Settings()
