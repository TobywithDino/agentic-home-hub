# -*- coding: utf-8 -*-
"""
呼叫 bff_server 的 client。

隊友的 bff_server 還沒長出全部端點，所以這裡有兩種模式：
  - settings.bff_base_url 有值 → 真的打 HTTP
  - 留空                        → 走內建假資料

假資料的形狀刻意照 Database/API_Reference.md 的真實 schema 做，
等 bff_server 好了只要設環境變數就切換，tool 程式碼一行都不用改。

架構原則（見 .kiro/steering/project-overview.md）：
這一層只打 bff_server，不直接碰 Database/api_server，更不碰 DB。
"""
from __future__ import annotations

import logging
from typing import Any

import httpx

from config import get_settings

log = logging.getLogger(__name__)


class BackendError(RuntimeError):
    """後端呼叫失敗。會被包成 tool error 回餵給模型，讓它改口或改參數。"""


class BackendClient:
    def __init__(self) -> None:
        settings = get_settings()
        self._enabled = settings.backend_enabled
        self._client: httpx.AsyncClient | None = None
        if self._enabled:
            self._client = httpx.AsyncClient(
                base_url=settings.bff_base_url,
                timeout=settings.bff_timeout_seconds,
            )

    @property
    def live(self) -> bool:
        return self._enabled

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()

    async def _get(self, path: str, **params: Any) -> Any:
        assert self._client is not None
        clean = {k: v for k, v in params.items() if v is not None}
        try:
            resp = await self._client.get(path, params=clean)
        except httpx.RequestError as exc:
            raise BackendError(f"連不上後端: {exc}") from exc
        if resp.status_code >= 400:
            raise BackendError(f"後端回 {resp.status_code}: {resp.text[:200]}")
        return resp.json()

    # ------------------------------------------------------------------
    # 依服務類型找服務商
    # 對應 GET /app-api/service-types/{service_type}/vendors
    # ------------------------------------------------------------------
    async def find_vendors(
        self, service_type: str, label_ids: list[int] | None = None
    ) -> list[dict[str, Any]]:
        if not self._enabled:
            return _stub_vendors(service_type, label_ids)

        labels = ",".join(str(i) for i in label_ids) if label_ids else None
        return await self._get(
            f"/app-api/service-types/{service_type}/vendors", labels=labels
        )

    # ------------------------------------------------------------------
    # 取某服務項目對應表單的完整結構
    # 對應 GET /app-api/services/{service_id}/form/full
    #
    # 為什麼用 service_id 而不是 vendor_id：表單是掛在服務項目上的
    # （cms_homepage_service.form_id），不是掛在商家上。實際資料裡同一個
    # 商家名下可能有十幾張表單（含測試用的、給別的服務用的），
    # 用 vendor 反查沒有可靠依據挑出正確那張。
    # ------------------------------------------------------------------
    async def get_service_form(self, service_id: int) -> dict[str, Any] | None:
        """回傳 {form, groups, topics}；該服務沒設定表單時回 None。"""
        if not self._enabled:
            return _stub_form_for_service(service_id)

        try:
            return await self._get(f"/app-api/services/{service_id}/form/full")
        except BackendError as exc:
            # BFF 對「服務不存在」與「form_id 為 NULL」都回 404。
            # 這是預期內的狀態，不該讓整輪對話爆掉，讓 tool 回可讀的錯誤給模型。
            if "404" in str(exc):
                return None
            raise

    # ------------------------------------------------------------------
    # 會員資料，用來自動填聯絡資訊
    # 對應 api_server GET /users/{inbr_account_id}
    # ------------------------------------------------------------------
    async def get_user(self, inbr_account_id: str) -> dict[str, Any]:
        if not self._enabled:
            return _stub_user(inbr_account_id)

        return await self._get(f"/app-api/users/{inbr_account_id}")

    # ------------------------------------------------------------------
    # 可用標籤（通用 + 該服務類型專屬）
    # 對應 GET /app-api/labels
    #
    # 為什麼要有這支：標籤不能寫死在 agent 裡。label 表有 service_type 欄位，
    # 餐廳訂位才有「中餐廳」「泰式料理」這種專屬標籤，寫死就永遠篩不到。
    # ------------------------------------------------------------------
    async def list_labels(self, service_type: str | None = None) -> list[dict[str, Any]]:
        if not self._enabled:
            return _stub_labels(service_type)

        return await self._get("/app-api/labels", service_type=service_type)

    # ------------------------------------------------------------------
    # 某服務商名下的服務項目
    # 對應 GET /app-api/vendors/{id}/services
    # ------------------------------------------------------------------
    async def list_vendor_services(
        self, service_vendor_id: int, service_type: str | None = None
    ) -> list[dict[str, Any]]:
        if not self._enabled:
            return _stub_vendor_services(service_vendor_id, service_type)

        return await self._get(
            f"/app-api/vendors/{service_vendor_id}/services", service_type=service_type
        )

    # ------------------------------------------------------------------
    # 某服務項目的評價
    # 對應 GET /app-api/services/{id}/reviews
    #
    # ⚠️ 這支回傳的是完整 ReviewOut，含 inbr_account_id / order_no 等
    # 身分關聯欄位。tool 層一定要裁掉才能給模型，否則會進 context 與
    # CloudWatch log，也可能被模型講給使用者聽。
    # ------------------------------------------------------------------
    async def get_service_reviews(self, service_id: int) -> list[dict[str, Any]]:
        if not self._enabled:
            return _stub_reviews(service_id)

        try:
            return await self._get(f"/app-api/services/{service_id}/reviews")
        except BackendError as exc:
            # 實測會 404（api_server 對某些 service_id 回「服務項目不存在」）。
            # 當成「沒有評價」而不是讓整個 tool 掛掉 —— 摘要可能還是拿得到，
            # 那對使用者仍有價值。
            if "404" in str(exc):
                return []
            raise

    # ------------------------------------------------------------------
    # 某服務項目的評價 AI 摘要
    # 對應 GET /app-api/services/{id}/review-summary
    # ------------------------------------------------------------------
    async def get_service_review_summary(
        self, service_id: int
    ) -> dict[str, Any] | None:
        """尚未生成摘要時回 None（BFF 回 404），這是正常狀態不是錯誤。"""
        if not self._enabled:
            return _stub_review_summary(service_id)

        try:
            return await self._get(f"/app-api/services/{service_id}/review-summary")
        except BackendError as exc:
            if "404" in str(exc):
                return None
            raise

    # ------------------------------------------------------------------
    # 會員的訂單與諮詢單總覽
    # 對應 GET /app-api/users/{id}/orders-overview
    #
    # ⚠️ 回傳含 member_name / member_phone / contact_* 等 PII，
    # tool 層必須裁切。
    # ------------------------------------------------------------------
    async def get_orders_overview(self, inbr_account_id: str) -> dict[str, Any]:
        if not self._enabled:
            return _stub_orders_overview(inbr_account_id)

        return await self._get(f"/app-api/users/{inbr_account_id}/orders-overview")


# ==========================================================================
# 假資料。形狀對齊 API_Reference.md，接上 bff_server 後這整段可以刪。
# ==========================================================================

_STUB_VENDORS: dict[str, list[dict[str, Any]]] = {
    "6": [  # 餐廳訂位
        {
            "id": 101,
            "name": "鳥花枝居酒屋",
            "description": "信義區日式居酒屋，串燒與清酒為主",
            "matched_services": [
                {
                    "id": 6001,
                    "service_vendor_id": 101,
                    "type": "6",
                    "name": "晚餐訂位",
                    "form_id": 9001,
                    "img_url": "https://example.com/izakaya.jpg",
                }
            ],
        },
        {
            "id": 102,
            "name": "初魚鐵板燒",
            "description": "信義區無菜單鐵板燒，需提前訂位",
            "matched_services": [
                {
                    "id": 6002,
                    "service_vendor_id": 102,
                    "type": "6",
                    "name": "無菜單套餐訂位",
                    "form_id": 9002,
                    "img_url": "https://example.com/teppanyaki.jpg",
                }
            ],
        },
    ],
    "2": [  # 家電清洗
        {
            "id": 201,
            "name": "潔淨家電清洗",
            "description": "洗衣機、冷氣深度清洗，到府服務",
            "matched_services": [
                {
                    "id": 2001,
                    "service_vendor_id": 201,
                    "type": "2",
                    "name": "洗衣機槽清洗",
                    "form_id": 9003,
                    "img_url": "https://example.com/washer.jpg",
                }
            ],
        }
    ],
}

# label: 1=寵物友善 2=24小時營業 3=專業認證 4=免費估價 5=到府服務 6=快速到達
_STUB_VENDOR_LABELS: dict[int, set[int]] = {
    101: {2},
    102: {3},
    201: {3, 4, 5},
}


def _stub_vendors(service_type: str, label_ids: list[int] | None) -> list[dict[str, Any]]:
    rows = _STUB_VENDORS.get(service_type, [])
    if not label_ids:
        return rows
    required = set(label_ids)
    return [v for v in rows if required.issubset(_STUB_VENDOR_LABELS.get(v["id"], set()))]


# 表單結構照 GET /forms/{form_id}/full 的形狀：{form, groups, topics}
# key 是 service_id（對齊真實的 cms_homepage_service.form_id 關聯），不是 vendor_id
# topic.type: 1簡答 2詳答 3單選 4複選 5地區選單 6上傳照片 7備註 8聯絡資料 9日期題 10聯絡資料(不含地址)
_STUB_FORMS: dict[int, dict[str, Any]] = {
    6001: (
        {
            "form": {
                "id": 9001,
                "service_vendor_id": 101,
                "type": "1",
                "sub_type": "1",
                "name": "訂位需求單",
            },
            "groups": [{"id": 1, "form_id": 9001, "name": "訂位資訊", "sort": 1}],
            "topics": [
                {
                    "id": 1, "form_id": 9001, "form_group_id": 1, "type": "9",
                    "title": "希望訂位日期", "is_required": "1", "sort": 1,
                    "start_date_offset_days": 0, "end_date_offset_days": 30,
                    "options": [], "media": [], "county_district_relations": [],
                },
                {
                    "id": 2, "form_id": 9001, "form_group_id": 1, "type": "3",
                    "title": "希望時段", "is_required": "1", "sort": 2,
                    "options": [
                        {"id": 21, "option_name": "17:30"},
                        {"id": 22, "option_name": "18:00"},
                        {"id": 23, "option_name": "19:00"},
                        {"id": 24, "option_name": "20:30"},
                    ],
                    "media": [], "county_district_relations": [],
                },
                {
                    "id": 3, "form_id": 9001, "form_group_id": 1, "type": "1",
                    "title": "用餐人數", "is_required": "1", "sort": 3,
                    "is_number_only": "1",
                    "options": [], "media": [], "county_district_relations": [],
                },
                {
                    "id": 4, "form_id": 9001, "form_group_id": 1, "type": "10",
                    "title": "聯絡資料", "is_required": "1", "sort": 4,
                    "options": [], "media": [], "county_district_relations": [],
                },
                {
                    "id": 5, "form_id": 9001, "form_group_id": 1, "type": "7",
                    "title": "特殊需求", "is_required": "0", "sort": 5,
                    "options": [], "media": [], "county_district_relations": [],
                },
            ],
        }
    ),
    6002: (
        {
            "form": {
                "id": 9002, "service_vendor_id": 102, "type": "1",
                "sub_type": "1", "name": "無菜單訂位單",
            },
            "groups": [{"id": 2, "form_id": 9002, "name": "訂位資訊", "sort": 1}],
            "topics": [
                {
                    "id": 11, "form_id": 9002, "form_group_id": 2, "type": "9",
                    "title": "希望訂位日期", "is_required": "1", "sort": 1,
                    "start_date_offset_days": 1, "end_date_offset_days": 60,
                    "options": [], "media": [], "county_district_relations": [],
                },
                {
                    "id": 12, "form_id": 9002, "form_group_id": 2, "type": "3",
                    "title": "希望時段", "is_required": "1", "sort": 2,
                    "options": [
                        {"id": 31, "option_name": "18:00"},
                        {"id": 32, "option_name": "19:00"},
                    ],
                    "media": [], "county_district_relations": [],
                },
                {
                    "id": 13, "form_id": 9002, "form_group_id": 2, "type": "1",
                    "title": "用餐人數", "is_required": "1", "sort": 3,
                    "is_number_only": "1",
                    "options": [], "media": [], "county_district_relations": [],
                },
                {
                    "id": 14, "form_id": 9002, "form_group_id": 2, "type": "10",
                    "title": "聯絡資料", "is_required": "1", "sort": 4,
                    "options": [], "media": [], "county_district_relations": [],
                },
            ],
        }
    ),
    2001: (
        {
            "form": {
                "id": 9003, "service_vendor_id": 201, "type": "2",
                "sub_type": "2", "name": "家電清洗估價單",
            },
            "groups": [{"id": 3, "form_id": 9003, "name": "服務需求", "sort": 1}],
            "topics": [
                {
                    "id": 21, "form_id": 9003, "form_group_id": 3, "type": "3",
                    "title": "洗衣機類型", "is_required": "1", "sort": 1,
                    "options": [
                        {"id": 41, "option_name": "直立式", "unit_price": 1600, "unit": "台"},
                        {"id": 42, "option_name": "滾筒式", "unit_price": 2200, "unit": "台"},
                    ],
                    "media": [], "county_district_relations": [],
                },
                {
                    "id": 22, "form_id": 9003, "form_group_id": 3, "type": "9",
                    "title": "希望到府日期", "is_required": "1", "sort": 2,
                    "start_date_offset_days": 2, "end_date_offset_days": 30,
                    "options": [], "media": [], "county_district_relations": [],
                },
                {
                    "id": 23, "form_id": 9003, "form_group_id": 3, "type": "8",
                    "title": "聯絡資料與地址", "is_required": "1", "sort": 3,
                    "options": [], "media": [], "county_district_relations": [],
                },
            ],
        }
    ),
}


def _stub_form_for_service(service_id: int) -> dict[str, Any] | None:
    return _STUB_FORMS.get(service_id)


def _stub_user(inbr_account_id: str) -> dict[str, Any]:
    return {
        "inbr_account_id": inbr_account_id,
        "contact_name": "王小明",
        "contact_mobile": "0912345678",
        "contact_email": "user01@example.com",
    }


# 通用標籤（service_type 為 null）+ 各類型專屬標籤，形狀照 GET /app-api/labels
_STUB_COMMON_LABELS: list[dict[str, Any]] = [
    {"id": 1, "name": "寵物友善"},
    {"id": 2, "name": "24小時營業"},
    {"id": 3, "name": "專業認證"},
    {"id": 4, "name": "免費估價"},
    {"id": 5, "name": "到府服務"},
    {"id": 6, "name": "快速到達"},
]

_STUB_TYPE_LABELS: dict[str, list[dict[str, Any]]] = {
    "6": [{"id": 7, "name": "中餐廳"}, {"id": 8, "name": "泰式料理"}],
}


def _stub_labels(service_type: str | None) -> list[dict[str, Any]]:
    extra = _STUB_TYPE_LABELS.get(str(service_type), []) if service_type else []
    return _STUB_COMMON_LABELS + extra


def _stub_vendor_services(
    service_vendor_id: int, service_type: str | None
) -> list[dict[str, Any]]:
    """從 _STUB_VENDORS 反查該商家的服務項目，不另外維護一份。"""
    out: list[dict[str, Any]] = []
    for stype, vendors in _STUB_VENDORS.items():
        if service_type is not None and str(service_type) != stype:
            continue
        for v in vendors:
            if v["id"] != service_vendor_id:
                continue
            out.extend(v.get("matched_services", []))
    return out


# 刻意保留 inbr_account_id / order_no / cre_id 等 PII 欄位，
# 這樣離線測試就能驗證 tool 層真的有裁掉它們。
_STUB_REVIEWS: dict[int, list[dict[str, Any]]] = {
    6001: [
        {
            "record_id": 9101,
            "order_no": "ORD20260710000001",
            "service_vendor_id": 101,
            "service_id": 6001,
            "inbr_account_id": "00000000-0000-0000-0000-000000000001",
            "overall_rating": 5,
            "rating_detail": {"food": 5, "service": 4},
            "review_content": "串燒很好吃，服務也親切",
            "media": None,
            "status": "01",
            "is_deleted": False,
            "cre_id": "00000000-0000-0000-0000-000000000001",
            "cre_time": "2026-07-10T12:00:00Z",
            "upd_id": None,
            "upd_time": None,
        },
        {
            "record_id": 9102,
            "order_no": "ORD20260715000002",
            "service_vendor_id": 101,
            "service_id": 6001,
            "inbr_account_id": "00000000-0000-0000-0000-000000000002",
            "overall_rating": 3,
            "rating_detail": None,
            "review_content": "位子有點擠，東西還可以",
            "media": None,
            "status": "01",
            "is_deleted": False,
            "cre_id": "00000000-0000-0000-0000-000000000002",
            "cre_time": "2026-07-15T19:30:00Z",
            "upd_id": None,
            "upd_time": None,
        },
    ],
}


def _stub_reviews(service_id: int) -> list[dict[str, Any]]:
    return _STUB_REVIEWS.get(service_id, [])


def _stub_review_summary(service_id: int) -> dict[str, Any] | None:
    if service_id != 6001:
        return None  # 對齊真實行為：沒生成過摘要時 BFF 回 404
    return {
        "service_id": 6001,
        "service_vendor_id": 101,
        "service_name": "晚餐訂位",
        "summary_content": "整體評價正向，串燒與服務態度受好評，座位空間偏小。",
        "summary_highlights": {"pros": ["串燒好吃", "服務親切"], "cons": ["座位擠"]},
        "sentiment_stats": {"positive": 1, "neutral": 1, "negative": 0},
        "source_review_count": 2,
        "source_avg_rating": 4.0,
        "generate_status": "02",
        "is_stale": False,
    }


def _stub_orders_overview(inbr_account_id: str) -> dict[str, Any]:
    """形狀照真實回應，含 member_* / contact_* 等 PII 欄位供裁切測試。"""
    return {
        "feedbacks": [
            {
                "feedback_no": "FB20260720000001",
                "service_id": 2001,
                "form_id": 9003,
                "status": "0",
                "is_read": "0",
                "contact_name": "王小明",
                "contact_mobile": "0912345678",
                "contact_email": "user01@example.com",
                "contact_mobile_hash": "should-be-stripped",
                "inbr_account_id": inbr_account_id,
                "description": "想問洗衣機清洗價格",
                "feedback_content": {},
                "cre_time": "2026-07-20T10:00:00Z",
            }
        ],
        "orders": [
            {
                "record_id": 8801,
                "order_no": "ORD20260701000010",
                "order_type": "02",
                "order_status": "80",
                "comment_status": "01",
                "service_id": 6001,
                "service_vendor_id": 101,
                "final_amount": 1800.0,
                "original_amount": 2000.0,
                "service_time": "2026-07-01T19:00:00Z",
                "order_time": "2026-06-28T09:00:00Z",
                "member_name": "王小明",
                "member_phone": "0912345678",
                "member_email": "user01@example.com",
                "member_phone_hash": "should-be-stripped",
                "inbr_account_id": inbr_account_id,
                "review": None,
                "cre_time": "2026-06-28T09:00:00Z",
            },
            {
                "record_id": 8802,
                "order_no": "ORD20260620000009",
                "order_type": "01",
                "order_status": "13",
                "comment_status": "00",
                "service_id": 2001,
                "service_vendor_id": 201,
                "final_amount": 2200.0,
                "service_time": None,
                "order_time": "2026-06-20T14:00:00Z",
                "member_name": "王小明",
                "member_phone": "0912345678",
                "inbr_account_id": inbr_account_id,
                "review": None,
                "cre_time": "2026-06-20T14:00:00Z",
            },
        ],
    }
