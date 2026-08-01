# -*- coding: utf-8 -*-
"""
AI 管家服務設定。慣例對齊 bff_server/app/config.py（pydantic-settings + lru_cache）。

所有值都能用環境變數覆寫。部署到 AgentCore Runtime 時透過
create-agent-runtime 的 --environment-variables 帶入，
但**不要放任何機密** —— 那裡的值可以用 get-agent-runtime 讀出來。
"""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # ---------------- AWS / Bedrock ----------------
    aws_region: str = "us-west-2"

    # cross-region inference profile（us. 前綴），已在 us-west-2 實測可用。
    # 換帳號或換區時重新確認：
    #   aws bedrock list-inference-profiles --region us-west-2 \
    #     --query "inferenceProfileSummaries[?contains(inferenceProfileId,'claude')].inferenceProfileId"
    bedrock_model_id: str = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"

    max_tokens: int = 2048
    temperature: float = 0.3

    # 一輪對話最多幾次 tool 往返，防止模型繞圈燒 token
    max_iterations: int = 8

    # ---------------- AgentCore Memory ----------------
    # 部署後由 CDK 自動注入 MEMORY_BUTLERMEMORY_ID（命名規則是
    # MEMORY_<agentcore.json 裡 memory 名稱大寫>_ID）。
    # 本機開發時可以自己設 MEMORY_ID。兩個都留空 = 關閉記憶。
    memory_butlermemory_id: str = ""
    memory_id: str = ""

    # 每輪注入系統提示的長期偏好筆數。太多會讓提示變肥、成本上升。
    memory_top_k: int = 5

    # 從 Memory 重建 session 內歷史時最多取幾則事件
    memory_history_limit: int = 40

    # ---------------- 後端 ----------------
    # 隊友的 bff_server。還沒好之前留空，tool 會走內建假資料。
    bff_base_url: str = ""
    bff_timeout_seconds: float = 10.0

    # ---------------- 草稿 ----------------
    draft_ttl_seconds: int = 600

    @property
    def resolved_memory_id(self) -> str:
        """CDK 注入的優先，本機手設的當備援。"""
        return self.memory_butlermemory_id or self.memory_id

    @property
    def memory_enabled(self) -> bool:
        return bool(self.resolved_memory_id)

    @property
    def backend_enabled(self) -> bool:
        return bool(self.bff_base_url)


@lru_cache
def get_settings() -> Settings:
    return Settings()
