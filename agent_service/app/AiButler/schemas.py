# -*- coding: utf-8 -*-
"""
對外事件協定與訂單草稿模型。

SSE 事件全部走同一個 envelope，Flutter 端用 `type` 分派。
這裡的字串必須跟 ai-butler-app/lib/data/remote/http_butler_ai_service.dart
的 _mapEvent 一致，草稿欄位另外對應 lib/domain/services/butler_ai_service.dart
的 ButlerChunk 子型別。
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

# --------------------------------------------------------------------------
# 訂單狀態代碼
#
# 來源是 Database/database/mms_order_record.sql 的 COMMENT ON COLUMN。
# 這些代碼直接丟給模型它講不出人話，所以在 tool 回傳前翻成中文。
# --------------------------------------------------------------------------
ORDER_TYPE_LABELS: dict[str, str] = {
    "01": "服務訂單",
    "02": "訂位",
    "03": "預約",
    "04": "其他",
    "05": "商品訂單",
    "06": "訂餐",
}

# 服務訂單有自己一套（含報價、尾款流程），其餘類型共用一套。
_SERVICE_ORDER_STATUS: dict[str, str] = {
    "11": "待訂金支付",
    "12": "已支付訂金，待報價",
    "13": "已報價，待客戶同意",
    "14": "客戶同意報價",
    "15": "已驗收，待尾款支付",
    "80": "已完成",
    "90": "已取消",
    "98": "部分退款",
    "99": "已退款",
}

_BOOKING_STATUS: dict[str, str] = {
    "01": "待付款",
    "02": "待確認",
    "03": "已確認",
    "04": "進行中",
    "70": "已完成",
    "80": "已完成",
    "90": "已取消",
    "99": "已退款",
}

COMMENT_STATUS_LABELS: dict[str, str] = {
    "00": "無須評價",
    "01": "未評價",
    "02": "已評價",
}


def order_status_label(order_type: str | None, order_status: str | None) -> str:
    """把訂單狀態代碼翻成中文。

    同一個代碼在不同 order_type 下語意不同（例如 `01` 在服務訂單裡沒用到，
    在訂位裡是「待付款」），所以要一起看。查不到就回原始代碼，
    不要編一個看起來合理的說法出來。
    """
    table = _SERVICE_ORDER_STATUS if str(order_type) == "01" else _BOOKING_STATUS
    return table.get(str(order_status), f"未知狀態({order_status})")

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
DraftKind = Literal["feedback", "review", "profile"]

# 草稿類型 → App 端該用哪個畫面帶使用者操作。
# 「帶我操作一遍」的導覽藍圖靠這個對應，不要讓 App 用 payload 的欄位去猜。
DRAFT_KIND_LABELS: dict[str, str] = {
    "feedback": "諮詢單",
    "review": "訂單評價",
    "profile": "個人資料",
}


@dataclass
class OrderDraft:
    """管家產生、使用者尚未確認的送出內容。

    `payload` 的欄位必須與 `submit_path` 那支 endpoint 的 request body 一致，
    這樣「直接送出」可以原封不動轉送，教學模式也能逐欄位填進表單。

    `submit_method` / `submit_path` 讓草稿自己描述「該送去哪」。少了這個，
    App 就得用 `kind` 去 switch 出路徑，每加一種草稿都要改前端；
    有了它前端只要重播 method + path + payload 就好。

    注意路徑一律是 bff_server 的 `/app-api/...` —— 送出是 App 帶使用者
    身分去打，不是管家打。管家全程沒有寫入權限。
    """

    kind: DraftKind
    payload: dict[str, Any]
    summary: str
    actor_id: str
    submit_method: str
    submit_path: str
    # 只有 feedback 類型才有服務項目與表單；評價/個資草稿沒有，所以可選
    service_id: int | None = None
    service_type: str | None = None
    form_id: int | None = None
    # App 的「帶我操作一遍」導覽要從首頁走到這家商家，所以草稿得記住它。
    # payload 裡沒有 vendor_id（建 feedback 只需要 service_id），
    # 但導覽需要在服務商列表圈出正確那一張卡。
    vendor_id: int | None = None
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
            "kind_label": DRAFT_KIND_LABELS.get(self.kind, self.kind),
            "service_id": self.service_id,
            "service_type": self.service_type,
            "service_type_label": (
                SERVICE_TYPE_LABELS.get(self.service_type, "")
                if self.service_type
                else ""
            ),
            "form_id": self.form_id,
            "vendor_id": self.vendor_id,
            "submit": {"method": self.submit_method, "path": self.submit_path},
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
