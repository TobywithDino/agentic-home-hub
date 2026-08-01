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

    # ---------------- AI 管家（AgentCore Runtime）----------------
    # AgentCore Runtime 只接受 SigV4(IAM) 驗證，前端拿不到憑證也不該拿，
    # 所以由這一層用 EC2 instance role 代為呼叫並把 SSE 轉發給前端。
    #
    # 取得方式：agent_service 目錄下跑 `agentcore status --json`，
    # 取 resources 裡 resourceType=agent 的 identifier。
    # 不寫死預設值：它含 AWS account id，而這個 repo 會公開。
    agentcore_runtime_arn: str = ""
    agentcore_qualifier: str = "DEFAULT"
    aws_region: str = "us-west-2"

    @property
    def butler_enabled(self) -> bool:
        return bool(self.agentcore_runtime_arn)


@lru_cache
def get_settings() -> Settings:
    return Settings()
