# -*- coding: utf-8 -*-
"""
呼叫 AI 管家（AgentCore Runtime）並把 SSE 串流轉發給前端。

為什麼需要這一層：
AgentCore Runtime 的 InvokeAgentRuntime 只接受 SigV4(IAM) 驗證。Flutter web
前端沒有 AWS 憑證，也絕對不該把憑證放進前端程式。所以由 bff_server 用 EC2
instance role 的身分代為呼叫，再把回來的 SSE 原樣轉發。

前端因此完全不需要知道 AgentCore 的存在，只看到一支普通的 SSE 端點。

事件格式維持不變（agent_service/app/AiButler/schemas.py 定義）：
    data: {"type":"text_delta","text":"..."}
    data: {"type":"tool_start","name":"..."}
    data: {"type":"ui","component":"vendor_list","payload":{...}}
    data: {"type":"draft",...}
    data: {"type":"done"}
    data: {"type":"error","message":"..."}
"""
from __future__ import annotations

import asyncio
import json
import logging
import uuid
from collections.abc import AsyncIterator

import boto3
from botocore.config import Config

from app.config import get_settings

log = logging.getLogger(__name__)

# AgentCore 要求 runtimeSessionId 至少 33 字元。標準 UUID 含連字號是 36 字元，
# 剛好符合；去掉連字號的 32 字元版本會被拒絕。
_MIN_SESSION_ID_LEN = 33


def _sse(event_type: str, **payload) -> bytes:
    body = json.dumps({"type": event_type, **payload}, ensure_ascii=False)
    return f"data: {body}\n\n".encode("utf-8")


class ButlerAgentClient:
    def __init__(self) -> None:
        settings = get_settings()
        self._arn = settings.agentcore_runtime_arn
        self._qualifier = settings.agentcore_qualifier
        self._enabled = settings.butler_enabled
        self._client = None
        self._region = settings.aws_region

    @property
    def enabled(self) -> bool:
        return self._enabled

    def _data_plane(self):
        """延後建立 client，讓服務在沒設定 ARN 時也能正常啟動。"""
        if self._client is None:
            self._client = boto3.client(
                "bedrock-agentcore",
                region_name=self._region,
                config=Config(
                    retries={"max_attempts": 2, "mode": "standard"},
                    read_timeout=180,
                    connect_timeout=10,
                ),
            )
        return self._client

    @staticmethod
    def normalize_session_id(raw: str | None) -> str:
        """補足長度不夠的 session id，並在缺少時產生一個。

        同一個聊天室要一直用同一個 id，AgentCore 才會把它視為同一段對話
        （短期記憶靠這個，跨 session 的長期偏好靠 actor_id）。
        """
        candidate = (raw or "").strip()
        if len(candidate) >= _MIN_SESSION_ID_LEN:
            return candidate
        return f"sess-{uuid.uuid4()}-{uuid.uuid4().hex[:8]}"

    async def stream(
        self, message: str, actor_id: str, session_id: str
    ) -> AsyncIterator[bytes]:
        """呼叫 agent 並逐段 yield SSE bytes。

        boto3 是同步的、回傳的 body 是阻塞式迭代器，所以整段讀取丟到執行緒，
        用 queue 交回 event loop —— 否則會卡住整個 server 的其他請求。
        """
        if not self._enabled:
            yield _sse("error", message="AI 管家尚未設定（缺少 AGENTCORE_RUNTIME_ARN）")
            yield _sse("done")
            return

        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[bytes | None] = asyncio.Queue()

        def push(item: bytes | None) -> None:
            loop.call_soon_threadsafe(queue.put_nowait, item)

        def reader() -> None:
            try:
                kwargs = {
                    "agentRuntimeArn": self._arn,
                    "runtimeSessionId": session_id,
                    "contentType": "application/json",
                    "accept": "text/event-stream",
                    "payload": json.dumps(
                        {
                            "message": message,
                            "actor_id": actor_id,
                            "session_id": session_id,
                        }
                    ).encode("utf-8"),
                }
                if self._qualifier:
                    kwargs["qualifier"] = self._qualifier

                resp = self._data_plane().invoke_agent_runtime(**kwargs)

                body = resp.get("response")
                if body is None:
                    push(_sse("error", message="AI 管家沒有回應內容"))
                    return

                # agent 端已經是 `data: {...}\n\n` 格式，原樣轉發即可，
                # 不要重新組裝，避免兩邊協定不同步。
                for chunk in body.iter_lines():
                    if not chunk:
                        continue
                    push(chunk + b"\n\n" if not chunk.endswith(b"\n") else chunk)
            except Exception as exc:  # noqa: BLE001
                log.exception("呼叫 AgentCore 失敗")
                push(_sse("error", message=f"AI 管家呼叫失敗：{type(exc).__name__}"))
            finally:
                push(None)  # 哨兵

        task = asyncio.create_task(asyncio.to_thread(reader))
        try:
            while True:
                item = await queue.get()
                if item is None:
                    break
                yield item
        finally:
            await task


_agent_client: ButlerAgentClient | None = None


def get_agent_client() -> ButlerAgentClient:
    global _agent_client
    if _agent_client is None:
        _agent_client = ButlerAgentClient()
    return _agent_client
