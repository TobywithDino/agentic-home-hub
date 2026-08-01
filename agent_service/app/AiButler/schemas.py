# -*- coding: utf-8 -*-
"""
對外事件協定與訂單草稿模型。

SSE 事件全部走同一個 envelope，Flutter 端用 `type` 分派。
這裡的字串必須跟 flutter_ai_script/lib/agent/agent_event.dart 一致。
"""
from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Literal


class ServiceType(str, Enum):
    """對齊 cms_homepage_service.type 的代碼。

    新增服務時這裡加一個 member，Flutter 的導覽藍圖表也要同步加。
    """

    HOME_CLEANING = "1"  # 一般居家清潔
    APPLIANCE_CLEANING = "2"  # 家電清洗（洗衣機清洗在這類）
    PARCEL_DELIVERY = "3"  # 包裹寄送
    RESTAURANT_RESERVATION = "6"  # 餐廳訂位
    FOOD_DELIVERY = "9"  # 美食外送
    REPAIR = "10"  # 水電修繕
    SHOPPING = "11"  # 商城購物


SERVICE_TYPE_LABELS: dict[str, str] = {
    "1": "居家清潔",
    "2": "家電清洗",
    "3": "包裹寄送",
    "6": "餐廳訂位",
    "9": "美食外送",
    "10": "水電修繕",
    "11": "商城購物",
}

EventType = Literal[
    "text_delta",  # 助理文字逐字輸出
    "tool_start",  # 開始執行 tool，前端顯示「正在查詢…」
    "ui",  # 結構化 GUI 元件（服務商列表卡片等）
    "draft",  # 諮詢單/訂單草稿就緒，前端顯示兩顆按鈕
    "done",  # 本輪結束
    "error",
]


def event(event_type: EventType, **payload: Any) -> dict[str, Any]:
    """組一筆事件。

    回傳 dict 而不是 SSE 字串 —— BedrockAgentCoreApp 的 _convert_to_sse
    會自己做 `data: {json}\\n\\n` 的包裝。這裡若先格式化成字串，
    上線後前端會收到 `data: "data: {...}"` 的雙重包裝。
    """
    return {"type": event_type, **payload}


# --------------------------------------------------------------------------
# 草稿
# --------------------------------------------------------------------------
@dataclass
class OrderDraft:
    """管家產生、使用者尚未確認的送出內容。

    `payload` 的欄位必須與既有下單/建單 endpoint 的 request body 一致，
    這樣「直接送出」可以原封不動轉送，教學模式也能逐欄位填進表單。
    """

    kind: Literal["feedback", "order"]
    service_id: int
    service_type: str
    payload: dict[str, Any]
    summary: str
    actor_id: str
    form_id: int | None = None
    draft_id: str = field(default_factory=lambda: uuid.uuid4().hex)
    created_at: float = field(default_factory=time.time)
    ttl_seconds: int = 600

    @property
    def expired(self) -> bool:
        return time.time() - self.created_at > self.ttl_seconds

    def to_event_payload(self) -> dict[str, Any]:
        return {
            "draft_id": self.draft_id,
            "kind": self.kind,
            "service_id": self.service_id,
            "service_type": self.service_type,
            "service_type_label": SERVICE_TYPE_LABELS.get(self.service_type, ""),
            "form_id": self.form_id,
            "payload": self.payload,
            "summary": self.summary,
            "expires_at": self.created_at + self.ttl_seconds,
        }


class DraftStore:
    """草稿暫存。

    AgentCore Runtime 的每個 session 是獨立 microVM，同一 session 內用
    process 記憶體就夠。但實例會被回收，所以草稿只保證在 TTL 內、
    且同一 session 存活期間可用 —— 這對「產生草稿後馬上讓使用者確認」
    的流程是足夠的。

    注意 actor_id 檢查在目前架構下只是防手誤，不是安全機制：
    這個專案沒有 token 驗證，知道別人 inbr_account_id 的人本來就能冒用。
    """

    def __init__(self) -> None:
        self._items: dict[str, OrderDraft] = {}

    def put(self, draft: OrderDraft) -> None:
        self._purge()
        self._items[draft.draft_id] = draft

    def get(self, draft_id: str, actor_id: str) -> OrderDraft | None:
        draft = self._items.get(draft_id)
        if draft is None or draft.expired or draft.actor_id != actor_id:
            return None
        return draft

    def _purge(self) -> None:
        for key in [k for k, v in self._items.items() if v.expired]:
            self._items.pop(key, None)


draft_store = DraftStore()
