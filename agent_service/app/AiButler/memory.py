# -*- coding: utf-8 -*-
"""
AgentCore Memory 封裝。

三件事：
  1. 寫入   CreateEvent           —— 每輪對話結束後把 user/assistant 訊息存進去
  2. 短期   ListEvents            —— 同一 session 重建對話歷史（實例被回收也不失憶）
  3. 長期   RetrieveMemoryRecords —— 跨 session 撈使用者偏好，注入系統提示

actorId 用 inbr_account_id，所以記憶天然按會員隔離。
sessionId 是單一聊天室，同一個聊天室重複使用同一個 id。

萃取是 AWS 那邊非同步做的（userPreferenceMemoryStrategy），
所以「剛剛才說的偏好」不會立刻出現在 RetrieveMemoryRecords 結果裡，
但同一 session 內靠 ListEvents 的原始歷史就看得到，不影響對話。
"""
from __future__ import annotations

import asyncio
import datetime as dt
import logging
from typing import Any

import boto3
from botocore.config import Config

from config import get_settings

log = logging.getLogger(__name__)

# namespace 模板必須跟 agentcore/agentcore.json 的 namespaceTemplates 完全一致，
# 不然讀取時撈不到東西。{actorId}/{sessionId} 由 AgentCore 在寫入時代換，
# 讀取時我們自己填成具體路徑。
NS_PREFERENCE = "/preferences/{actorId}"

# 摘要目前只寫不讀 —— SUMMARIZATION 策略會產生 per-session 摘要存在這裡，
# 之後想做「上次你訂了什麼」這種功能可以直接撈。
NS_SUMMARY = "/summaries/{actorId}/{sessionId}"


class MemoryClient:
    def __init__(self) -> None:
        settings = get_settings()
        self._memory_id = settings.resolved_memory_id
        self._top_k = settings.memory_top_k
        self._history_limit = settings.memory_history_limit
        self._enabled = settings.memory_enabled

        self._client = boto3.client(
            "bedrock-agentcore",
            region_name=settings.aws_region,
            config=Config(
                retries={"max_attempts": 3, "mode": "adaptive"},
                read_timeout=15,
                connect_timeout=5,
            ),
        )

    @property
    def enabled(self) -> bool:
        return self._enabled

    # ------------------------------------------------------------------
    # 寫入
    # ------------------------------------------------------------------
    async def record_turn(
        self,
        actor_id: str,
        session_id: str,
        user_text: str,
        assistant_text: str,
    ) -> None:
        """把一輪問答寫進 Memory。

        失敗不能中斷對話 —— 使用者已經拿到回覆了，記憶寫失敗只是下次少一點
        上下文，不值得把整個請求變成 500。
        """
        if not self._enabled:
            return

        payload: list[dict[str, Any]] = [
            {"conversational": {"role": "USER", "content": {"text": user_text}}}
        ]
        if assistant_text.strip():
            payload.append(
                {
                    "conversational": {
                        "role": "ASSISTANT",
                        "content": {"text": assistant_text},
                    }
                }
            )

        try:
            await asyncio.to_thread(
                self._client.create_event,
                memoryId=self._memory_id,
                actorId=actor_id,
                sessionId=session_id,
                eventTimestamp=dt.datetime.now(dt.timezone.utc),
                payload=payload,
            )
        except Exception:  # noqa: BLE001
            log.warning("create_event 失敗，本輪不寫入記憶", exc_info=True)

    # ------------------------------------------------------------------
    # 短期：同一 session 的歷史
    # ------------------------------------------------------------------
    async def load_history(self, actor_id: str, session_id: str) -> list[dict[str, Any]]:
        """重建 Converse API 格式的 messages。

        只還原 USER / ASSISTANT 的純文字。tool 往返不還原 —— 這是刻意的：
        Converse API 要求 toolResult 必須配對到同一輪的 toolUse，
        跨請求還原配對很容易組出不合法的 messages 被 API 拒絕。
        文字歷史對延續對話已經足夠。
        """
        if not self._enabled:
            return []

        try:
            resp = await asyncio.to_thread(
                self._client.list_events,
                memoryId=self._memory_id,
                actorId=actor_id,
                sessionId=session_id,
                includePayloads=True,
                maxResults=self._history_limit,
            )
        except Exception:  # noqa: BLE001
            log.warning("list_events 失敗，本輪不帶歷史", exc_info=True)
            return []

        messages: list[dict[str, Any]] = []
        for mem_event in _oldest_first(resp.get("events", [])):
            for item in mem_event.get("payload", []):
                conv = item.get("conversational")
                if not conv:
                    continue
                role = conv.get("role")
                text = (conv.get("content") or {}).get("text", "")
                if role not in ("USER", "ASSISTANT") or not text.strip():
                    continue

                converse_role = "user" if role == "USER" else "assistant"
                # Converse API 不接受連續同 role 的訊息，合併掉
                if messages and messages[-1]["role"] == converse_role:
                    messages[-1]["content"][0]["text"] += f"\n{text}"
                else:
                    messages.append(
                        {"role": converse_role, "content": [{"text": text}]}
                    )

        # 歷史必須從 user 開始，否則 Converse API 會拒絕
        while messages and messages[0]["role"] != "user":
            messages.pop(0)
        return messages

    # ------------------------------------------------------------------
    # 長期：跨 session 偏好
    # ------------------------------------------------------------------
    async def recall_preferences(self, actor_id: str, query: str) -> list[str]:
        """撈跨 session 的使用者偏好，回傳純文字清單給系統提示用。"""
        if not self._enabled:
            return []

        try:
            resp = await asyncio.to_thread(
                self._client.retrieve_memory_records,
                memoryId=self._memory_id,
                namespace=NS_PREFERENCE.format(actorId=actor_id),
                searchCriteria={"searchQuery": query, "topK": self._top_k},
            )
        except Exception:  # noqa: BLE001
            # Memory 剛建好、還沒有任何萃取結果時這裡會空手而回，屬正常
            log.info("retrieve_memory_records 無結果或失敗", exc_info=True)
            return []

        out: list[str] = []
        for record in resp.get("memoryRecords", []):
            text = _extract_text(record)
            if text:
                out.append(text)
        return out


def _oldest_first(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """ListEvents 預設新到舊，對話歷史要舊到新。"""
    return sorted(events, key=lambda e: e.get("eventTimestamp") or 0)


def _extract_text(record: dict[str, Any]) -> str:
    """從 memoryRecord 取出可讀文字。

    content 的形狀依 strategy 而異，所以逐層 fallback，
    取不到就回空字串讓呼叫端略過，不要讓格式變動炸掉整個請求。
    """
    content = record.get("content")
    if isinstance(content, dict):
        if isinstance(content.get("text"), str):
            return content["text"].strip()
    if isinstance(content, str):
        return content.strip()
    return ""


_memory_client: MemoryClient | None = None


def get_memory_client() -> MemoryClient:
    global _memory_client
    if _memory_client is None:
        _memory_client = MemoryClient()
    return _memory_client
