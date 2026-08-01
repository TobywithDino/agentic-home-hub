# -*- coding: utf-8 -*-
"""
AI 管家的 AgentCore Runtime 入口。

用 BedrockAgentCoreApp，它自己處理 AgentCore 的協定契約：
  POST /invocations  呼叫，回傳 SSE
  GET  /ping         健康檢查
  port 8080

**不要自己格式化 SSE**。這裡 yield dict，SDK 的 _convert_to_sse 會包成
`data: {json}\\n\\n`。自己先包一次會變成雙重包裝，前端解不出來。

本機開發：
    cd agent_service
    agentcore dev --no-browser
    curl -X POST http://localhost:8080/invocations -H "Content-Type: application/json" \\
      -d '{"message":"我想吃晚餐","actor_id":"demo-user-0001"}'
"""
from __future__ import annotations

import os
from typing import Any

from bedrock_agentcore.runtime import BedrockAgentCoreApp

from backend import BackendClient
from loop import run_turn
from schemas import event

app = BedrockAgentCoreApp()
log = app.logger

# 連線池重用，每次 invoke 重建 httpx client 會浪費 TCP 握手
_backend: BackendClient | None = None


def get_backend() -> BackendClient:
    global _backend
    if _backend is None:
        _backend = BackendClient()
        log.info(
            "backend=%s", os.environ.get("BFF_BASE_URL") or "stub(內建假資料)"
        )
    return _backend


@app.entrypoint
async def invoke(payload: dict[str, Any], context: Any):
    """一輪對話。

    payload:
      message   (必填) 使用者這次說的話
      actor_id  (必填) 會員 UUID（inbr_account_id），跨 session 記憶就是靠這個

    注意 actor_id 是呼叫端聲明的，不是驗證過的身分 —— 這個專案目前沒有
    token 機制。等 bff_server 上了驗證再改成從 JWT 取。
    """
    message = (payload or {}).get("message") or (payload or {}).get("prompt")
    if not message or not str(message).strip():
        yield event("error", message="payload 缺少 message")
        return

    actor_id = (payload or {}).get("actor_id")
    if not actor_id:
        yield event("error", message="payload 缺少 actor_id")
        return

    # session_id 由 Runtime 從 X-Amzn-Bedrock-AgentCore-Runtime-Session-Id 帶進來，
    # 同一個聊天室重複用同一個 id 就能延續對話
    session_id = getattr(context, "session_id", None) or "local-dev-session"

    log.info("invoke actor=%s session=%s", actor_id, session_id)

    async for evt in run_turn(
        user_text=str(message),
        actor_id=str(actor_id),
        session_id=str(session_id),
        backend=get_backend(),
    ):
        yield evt


if __name__ == "__main__":
    app.run()
