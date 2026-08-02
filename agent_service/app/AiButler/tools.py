# -*- coding: utf-8 -*-
"""
Tool 定義與執行（async）。

三類 tool：
  READ  — 透過 BackendClient 讀資料，結果回餵給模型
  UI    — 不做後端動作，只把結構化元件推給 App 顯示，立刻回 success
  DRAFT — 產生草稿。**不會真的送出**，送出由 App 帶使用者身分打既有 endpoint

設計重點：表單是資料驅動的（pms_form 系列），所以管家不寫死任何服務流程。
get_service_form 把題目結構交給模型，模型自己決定要問什麼、怎麼問，
一套 tool 就能處理全部 7 種服務類型。

安全原則：actor_id 由呼叫端注入 ToolContext，絕不出現在 inputSchema，
模型沒有能力指定「幫別人送單」。
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Any, Awaitable, Callable, Protocol

from backend import BackendClient, BackendError
from config import get_settings
from schemas import (
    COMMENT_STATUS_LABELS,
    ORDER_TYPE_LABELS,
    SERVICE_TYPE_LABELS,
    OrderDraft,
    draft_store,
    order_status_label,
)
from session_state import SessionState

log = logging.getLogger(__name__)

# 題目型別代碼 → 語意，讓模型知道該怎麼問、答案該長什麼樣
TOPIC_TYPES: dict[str, str] = {
    "1": "簡答（單行文字）",
    "2": "詳答（多行文字）",
    "3": "單選（從 options 挑一個 option_name）",
    "4": "複選（從 options 挑多個 option_name）",
    "5": "地區選單（縣市+行政區）",
    "6": "上傳照片（管家無法代填）",
    "7": "備註（自由文字）",
    "8": "聯絡資料（含地址）",
    "9": "日期（YYYY-MM-DD）",
    "10": "聯絡資料（不含地址）",
}

# 管家不能代填的題型，遇到要跟使用者說明稍後在表單補
UNFILLABLE_TOPIC_TYPES = {"6"}

# 訂單/諮詢單回給模型時要保留的欄位。
#
# 用白名單而不是黑名單：真實訂單有 48 個欄位，含 member_name / member_phone /
# member_email 與一堆 *_hash。黑名單漏一個就把 PII 送進模型 context 和
# CloudWatch log，白名單漏一個只是模型少看到一項資訊。
_ORDER_KEEP_FIELDS = (
    "record_id",
    "order_no",
    "order_type",
    "order_status",
    "comment_status",
    "service_id",
    "service_vendor_id",
    "final_amount",
    "service_time",
    "order_time",
    "cre_time",
)

_FEEDBACK_KEEP_FIELDS = (
    "feedback_no",
    "service_id",
    "form_id",
    "status",
    "is_read",
    "description",
    "cre_time",
)

# 評價回給模型時只留這些。刻意排除 inbr_account_id / order_no / cre_id /
# upd_id —— 那些是評價者的身分關聯，模型不需要，也不該有機會講出來。
_REVIEW_KEEP_FIELDS = (
    "overall_rating",
    "rating_detail",
    "review_content",
    "cre_time",
)

_FEEDBACK_STATUS_LABELS = {"0": "未處理", "1": "處理中", "2": "已完成"}


class EventEmitter(Protocol):
    def __call__(self, event_type: str, **payload: Any) -> None: ...


@dataclass
class ToolContext:
    actor_id: str  # inbr_account_id，由呼叫端注入，不是模型給的
    emit: EventEmitter  # 把 ui / draft 事件推到 SSE 串流
    backend: BackendClient
    state: SessionState  # 跨輪帶著走的已解析實體，避免模型猜 id


ToolHandler = Callable[[ToolContext, dict[str, Any]], Awaitable[dict[str, Any]]]

_SPECS: list[dict[str, Any]] = []
_HANDLERS: dict[str, ToolHandler] = {}


def tool(name: str, description: str, schema: dict[str, Any]):
    """註冊 tool。description 寫得好壞直接決定模型會不會正確呼叫它。"""

    def wrap(fn: ToolHandler) -> ToolHandler:
        _SPECS.append(
            {
                "toolSpec": {
                    "name": name,
                    "description": description,
                    "inputSchema": {"json": schema},
                }
            }
        )
        _HANDLERS[name] = fn
        return fn

    return wrap


def tool_config() -> dict[str, Any]:
    return {"tools": _SPECS}


async def dispatch(
    ctx: ToolContext, name: str, payload: dict[str, Any]
) -> dict[str, Any]:
    handler = _HANDLERS.get(name)
    if handler is None:
        return {"error": f"unknown tool: {name}"}
    # 模型傳錯參數是最常見的故障，日誌要留輸入才查得出來。
    # 注意這會寫進 CloudWatch，所以不要把 PII 塞進 tool 參數。
    log.info("tool %s <- %s", name, payload)
    try:
        return await handler(ctx, payload)
    except (BackendError, ValueError) as exc:
        # 預期得到的錯誤，回給模型讓它改參數或改口跟使用者說明
        return {"error": type(exc).__name__, "detail": str(exc)}
    except Exception as exc:  # noqa: BLE001
        return {"error": "InternalError", "detail": str(exc)[:200]}


# ==========================================================================
# READ：找服務商
# ==========================================================================
@tool(
    name="find_service_vendors",
    description=(
        "依服務類型（必要時加標籤）搜尋可用的服務商。"
        "使用者說出需求後第一步就呼叫這個。"
        "不要自己編造服務商或服務項目，所有資料都必須來自這個 tool 的回傳。"
    ),
    schema={
        "type": "object",
        "properties": {
            "service_type": {
                "type": "string",
                "enum": list(SERVICE_TYPE_LABELS.keys()),
                "description": (
                    "服務類型代碼："
                    + "、".join(f"{k}={v}" for k, v in SERVICE_TYPE_LABELS.items())
                ),
            },
            "label_ids": {
                "type": "array",
                "items": {"type": "integer"},
                "description": (
                    "篩選標籤的 id，只在使用者明確提到偏好時才傳。"
                    "**必須先呼叫 list_service_labels 取得該服務類型的合法 label id**，"
                    "不要自己猜數字 —— 每種服務類型的專屬標籤不同"
                    "（例如餐廳訂位才有「中餐廳」「泰式料理」）。"
                ),
            },
        },
        "required": ["service_type"],
    },
)
async def find_service_vendors(
    ctx: ToolContext, args: dict[str, Any]
) -> dict[str, Any]:
    service_type = str(args["service_type"])
    vendors = await ctx.backend.find_vendors(service_type, args.get("label_ids"))

    # 只回模型決策需要的欄位。整包資料丟進 context 會浪費 token，
    # 也容易讓模型把內部欄位講給使用者聽。
    slim = [
        {
            "vendor_id": v["id"],
            "name": v["name"],
            "description": v.get("description") or "",
            "services": [
                {
                    "service_id": s["id"],
                    "name": s["name"],
                    # form_id 為 null 表示這個服務項目還沒設定表單，無法線上填單。
                    # 先讓模型看到，它才不會挑了之後才在 get_service_form 撞牆。
                    "has_form": s.get("form_id") is not None,
                }
                for s in v.get("matched_services", [])
            ],
        }
        for v in vendors
    ]
    # 記進工作集，下一輪系統提示會帶上，模型就不用憑印象猜 id
    ctx.state.remember_vendors(service_type, slim)

    return {
        "service_type": service_type,
        "service_type_label": SERVICE_TYPE_LABELS.get(service_type, ""),
        "count": len(slim),
        "vendors": slim,
        "note": (
            "只有 has_form=true 的服務項目能線上填單。"
            "使用者沒特別指定時優先推薦這些；若他選的服務 has_form=false，"
            "要老實說那個服務目前無法透過對話填單。"
        ),
    }


# ==========================================================================
# UI：把服務商列表推給 App 用原生卡片顯示
# ==========================================================================
@tool(
    name="show_vendor_list",
    description=(
        "把服務商列表用 App 的圖卡元件顯示給使用者。"
        "在 find_service_vendors 之後呼叫，vendor_ids 用搜尋結果裡的 vendor_id。"
        "呼叫後用一句話問使用者要選哪一家。"
        "回傳值會告訴你每一家在畫面上的位置，使用者說「第二家」時用它換算成 vendor_id。"
    ),
    schema={
        "type": "object",
        "properties": {
            "vendor_ids": {
                "type": "array",
                "items": {"type": "integer"},
                "maxItems": 5,
                "description": "要顯示的 vendor_id，最多 5 個",
            },
            "service_type": {
                "type": "string",
                "enum": list(SERVICE_TYPE_LABELS.keys()),
            },
        },
        "required": ["vendor_ids", "service_type"],
    },
)
async def show_vendor_list(ctx: ToolContext, args: dict[str, Any]) -> dict[str, Any]:
    service_type = str(args["service_type"])
    wanted = {int(i) for i in args["vendor_ids"]}

    vendors = await ctx.backend.find_vendors(service_type, None)
    # 保持 vendor_ids 傳進來的順序，畫面順序要跟模型認知的一致
    by_id = {v["id"]: v for v in vendors}
    chosen = [by_id[i] for i in (int(x) for x in args["vendor_ids"]) if i in by_id]

    ctx.emit(
        "ui",
        component="vendor_list",
        payload={"service_type": service_type, "vendors": chosen},
    )

    # 把「畫面第幾家 → vendor_id」明確回餵。少了這個，使用者說「第二家」時
    # 模型會直接把 2 當成 vendor_id 傳下去（實測踩過）。
    return {
        "displayed_in_order": [
            {"position": idx, "vendor_id": v["id"], "name": v["name"]}
            for idx, v in enumerate(chosen, start=1)
        ],
        "hint": "使用者講「第N家」時對照 position，傳 vendor_id 給後續 tool，不要傳 N。",
    }


# ==========================================================================
# READ：取表單結構（動態表單的核心）
# ==========================================================================
@tool(
    name="get_service_form",
    description=(
        "取得某個服務項目的表單題目結構。選定服務項目後、開始問細節前必須呼叫。"
        "回傳的 topics 就是要問使用者的題目，依 sort 順序問，"
        "is_required=1 的一定要問到答案。單選/複選題只能用 options 裡的 option_name。"
    ),
    schema={
        "type": "object",
        "properties": {
            "service_id": {
                "type": "integer",
                "description": (
                    "服務項目 id，必須是 find_service_vendors 回傳的 services[].service_id 值。"
                    "注意是「服務項目」不是「服務商」—— 一個服務商可能有多個服務項目，"
                    "表單是掛在服務項目上的。也不是「第幾家」的序號。"
                ),
            },
        },
        "required": ["service_id"],
    },
)
async def get_service_form(ctx: ToolContext, args: dict[str, Any]) -> dict[str, Any]:
    service_id = int(args["service_id"])
    full = await ctx.backend.get_service_form(service_id)
    if not full:
        # 這個錯誤要能讓模型自己修好，所以把兩種可能原因都寫清楚：
        # 傳錯 id（實測最常見是把「第N家」的序號當 id），或這個服務真的沒表單。
        return {
            "error": "ServiceFormNotFound",
            "detail": (
                f"service_id={service_id} 找不到對應表單。可能是："
                "(1) 你傳的不是 find_service_vendors 回傳的 services[].service_id，"
                "請重新呼叫 find_service_vendors 查正確的值；"
                "(2) 這個服務項目尚未設定表單，那就告訴使用者這個服務目前無法線上填單，"
                "並建議改選同類型的其他服務項目。不要自己編一份表單題目出來。"
            ),
        }

    form = full["form"]
    topics = sorted(full.get("topics", []), key=lambda t: t.get("sort", 0))

    slim_topics = [_slim_topic(t) for t in topics]
    ctx.state.remember_form(service_id, int(form["id"]), slim_topics)

    return {
        "form_id": form["id"],
        "form_name": form.get("name", ""),
        "form_type": form.get("type", "1"),
        "topics": slim_topics,
        "note": (
            "依 sort 順序逐題問使用者。type=6（上傳照片）你無法代填，"
            "要告訴使用者稍後在表單頁補上。"
        ),
    }


def _slim_topic(topic: dict[str, Any]) -> dict[str, Any]:
    ttype = str(topic.get("type", ""))
    out: dict[str, Any] = {
        "topic_id": topic["id"],
        "title": topic.get("title", ""),
        "type": ttype,
        "type_meaning": TOPIC_TYPES.get(ttype, "未知題型"),
        "is_required": topic.get("is_required", "0") == "1",
        "fillable_by_agent": ttype not in UNFILLABLE_TOPIC_TYPES,
    }
    if remark := topic.get("remark"):
        out["remark"] = remark
    if options := topic.get("options"):
        out["options"] = [
            {
                k: o[k]
                for k in ("id", "option_name", "unit_price", "unit")
                if o.get(k) is not None
            }
            for o in options
        ]
    if ttype == "9":
        # 日期題的可選範圍，讓模型自己算出合法日期而不是亂猜
        out["date_range"] = {
            "start_offset_days": topic.get("start_date_offset_days"),
            "end_offset_days": topic.get("end_date_offset_days"),
        }
    if ttype == "1" and topic.get("is_number_only") == "1":
        out["number_only"] = True
    return out


# ==========================================================================
# READ：會員聯絡資訊
# ==========================================================================
@tool(
    name="get_my_profile",
    description=(
        "取得目前使用者的姓名、手機、Email，用來填表單的聯絡資料題。"
        "不要開口問使用者這些資料，先呼叫這個 tool。"
    ),
    schema={"type": "object", "properties": {}, "required": []},
)
async def get_my_profile(ctx: ToolContext, args: dict[str, Any]) -> dict[str, Any]:
    user = await ctx.backend.get_user(ctx.actor_id)
    return {
        "contact_name": user.get("contact_name"),
        "contact_mobile": user.get("contact_mobile"),
        "contact_email": user.get("contact_email"),
    }


# ==========================================================================
# READ：可用標籤（取代寫死的清單）
# ==========================================================================
@tool(
    name="list_service_labels",
    description=(
        "取得某服務類型可用的篩選標籤。使用者提到偏好條件"
        "（例如「有寵物友善的」「要中式的」「24小時的」）時，"
        "先呼叫這個拿到 label id，再把 id 傳給 find_service_vendors 的 label_ids。"
        "不要自己猜 label id。"
    ),
    schema={
        "type": "object",
        "properties": {
            "service_type": {
                "type": "string",
                "enum": list(SERVICE_TYPE_LABELS.keys()),
                "description": "服務類型代碼。會回傳「通用標籤 + 該類型專屬標籤」",
            },
        },
        "required": ["service_type"],
    },
)
async def list_service_labels(ctx: ToolContext, args: dict[str, Any]) -> dict[str, Any]:
    service_type = str(args["service_type"])
    labels = await ctx.backend.list_labels(service_type)

    return {
        "service_type": service_type,
        "labels": [{"label_id": l["id"], "name": l["name"]} for l in labels],
        "note": (
            "使用者的說法要對應到最接近的標籤，對不上就不要傳 label_ids，"
            "硬套會篩掉所有結果。可以多個一起傳，但那是「同時滿足全部條件」。"
        ),
    }


# ==========================================================================
# READ：某服務商名下的服務項目
# ==========================================================================
@tool(
    name="list_vendor_services",
    description=(
        "列出某服務商提供的所有服務項目。"
        "使用者問「這家還有什麼服務」「他們也做清潔嗎」時用這個。"
        "也可用來在同一家裡換一個服務項目。"
    ),
    schema={
        "type": "object",
        "properties": {
            "vendor_id": {
                "type": "integer",
                "description": "服務商 id，用 find_service_vendors 回傳的 vendor_id",
            },
            "service_type": {
                "type": "string",
                "enum": list(SERVICE_TYPE_LABELS.keys()),
                "description": "只看某一類型時才傳，不傳則回傳該商家全部服務項目",
            },
        },
        "required": ["vendor_id"],
    },
)
async def list_vendor_services(ctx: ToolContext, args: dict[str, Any]) -> dict[str, Any]:
    vendor_id = int(args["vendor_id"])
    services = await ctx.backend.list_vendor_services(
        vendor_id, args.get("service_type")
    )

    if not services:
        return {
            "error": "NoServicesFound",
            "detail": (
                f"vendor_id={vendor_id} 查不到服務項目。確認你傳的是"
                " find_service_vendors 回傳的 vendor_id，不是「第幾家」的序號。"
            ),
        }

    return {
        "vendor_id": vendor_id,
        "services": [
            {
                "service_id": s["id"],
                "name": s.get("name", ""),
                "service_type": str(s.get("type", "")),
                "service_type_label": SERVICE_TYPE_LABELS.get(str(s.get("type")), ""),
                "description": s.get("description") or "",
                "has_form": s.get("form_id") is not None,
            }
            for s in services
        ],
        "note": "只有 has_form=true 的服務項目能線上填單。",
    }


# ==========================================================================
# READ：服務項目的評價與 AI 摘要
# ==========================================================================
@tool(
    name="get_service_reviews",
    description=(
        "查某個服務項目的評價與 AI 摘要。"
        "使用者問「評價好嗎」「別人怎麼說」「推薦哪一家」時用這個。"
        "有 AI 摘要就以摘要為主回答，沒有才引用個別評價。"
    ),
    schema={
        "type": "object",
        "properties": {
            "service_id": {
                "type": "integer",
                "description": (
                    "服務項目 id，用 find_service_vendors 回傳的"
                    " services[].service_id。注意評價是掛在服務項目上，不是商家上。"
                ),
            },
            "limit": {
                "type": "integer",
                "description": "最多回幾筆個別評價，預設 5。摘要不受此限制。",
            },
        },
        "required": ["service_id"],
    },
)
async def get_service_reviews(ctx: ToolContext, args: dict[str, Any]) -> dict[str, Any]:
    service_id = int(args["service_id"])
    limit = max(1, min(int(args.get("limit") or 5), 20))

    reviews = await ctx.backend.get_service_reviews(service_id)
    summary = await ctx.backend.get_service_review_summary(service_id)

    if not reviews and not summary:
        return {
            "service_id": service_id,
            "review_count": 0,
            "note": (
                "這個服務項目目前還沒有任何評價。老實告訴使用者沒有評價可參考，"
                "不要憑服務商名稱或描述編造評價內容。"
            ),
        }

    # 新的先給模型看，舊評價的參考價值較低
    ordered = sorted(reviews, key=lambda r: str(r.get("cre_time") or ""), reverse=True)
    ratings = [r["overall_rating"] for r in reviews if r.get("overall_rating") is not None]

    out: dict[str, Any] = {
        "service_id": service_id,
        "review_count": len(reviews),
        # 逐筆裁成白名單欄位，把評價者身分關聯（inbr_account_id / order_no）濾掉
        "recent_reviews": [
            {k: r[k] for k in _REVIEW_KEEP_FIELDS if r.get(k) is not None}
            for r in ordered[:limit]
        ],
    }
    if ratings:
        out["average_rating"] = round(sum(ratings) / len(ratings), 1)

    if summary:
        out["ai_summary"] = {
            "content": summary.get("summary_content"),
            "highlights": summary.get("summary_highlights"),
            "based_on_review_count": summary.get("source_review_count"),
            # is_stale=true 代表有新評價還沒納入摘要，講的時候別說得太絕對
            "is_outdated": summary.get("is_stale"),
        }

    # 摘要與逐筆評價是兩張表，實測會不一致（摘要說有 3 筆、逐筆卻抓不到）。
    # 不講清楚的話模型會同時說「有 3 筆評價」和「目前沒有評價」，自相矛盾。
    if summary and not reviews:
        out["note"] = (
            "查不到逐筆評價，但有先前產生的 AI 摘要。回答時以摘要內容為準，"
            "不要說「沒有評價」，也不要自己編出具體某一則評價的內容。"
        )
    elif reviews:
        out["note"] = (
            "recent_reviews 是實際評價內容，可以引用但不要逐字唸完。"
            "有 ai_summary 時以摘要為主，個別評價當補充。"
        )

    return out


# ==========================================================================
# READ：我的訂單與諮詢單
# ==========================================================================
@tool(
    name="list_my_orders",
    description=(
        "查目前使用者自己的訂單與諮詢單。"
        "使用者問「我的訂單」「上次那筆好了嗎」「我約的時間是什麼時候」"
        "「有什麼還沒評價」時用這個。不需要傳帳號，會自動用當前使用者。"
    ),
    schema={
        "type": "object",
        "properties": {
            "only_reviewable": {
                "type": "boolean",
                "description": (
                    "只回「已完成且還沒評價」的訂單。"
                    "使用者想寫評價時傳 true，可以少問一輪。"
                ),
            },
        },
        "required": [],
    },
)
async def list_my_orders(ctx: ToolContext, args: dict[str, Any]) -> dict[str, Any]:
    data = await ctx.backend.get_orders_overview(ctx.actor_id)

    orders: list[dict[str, Any]] = []
    for o in data.get("orders") or []:
        slim = {k: o[k] for k in _ORDER_KEEP_FIELDS if o.get(k) is not None}
        # 代碼直接給模型它講不出人話，這裡翻好
        slim["order_type_label"] = ORDER_TYPE_LABELS.get(str(o.get("order_type")), "")
        slim["order_status_label"] = order_status_label(
            o.get("order_type"), o.get("order_status")
        )
        slim["comment_status_label"] = COMMENT_STATUS_LABELS.get(
            str(o.get("comment_status")), ""
        )
        slim["can_review"] = _can_review(o)
        if review := o.get("review"):
            slim["my_review"] = {
                k: review[k] for k in _REVIEW_KEEP_FIELDS if review.get(k) is not None
            }
        orders.append(slim)

    # 先記全部再篩。工作集是「這位使用者有哪些訂單 id」，不是「這次顯示了哪些」——
    # 若只記篩選後的，使用者下一輪問到別筆訂單，模型就又要猜 record_id 了。
    ctx.state.remember_orders(orders)

    if args.get("only_reviewable"):
        orders = [o for o in orders if o["can_review"]]

    feedbacks = [
        {
            **{k: f[k] for k in _FEEDBACK_KEEP_FIELDS if f.get(k) is not None},
            "status_label": _FEEDBACK_STATUS_LABELS.get(str(f.get("status")), ""),
        }
        for f in (data.get("feedbacks") or [])
    ]

    result: dict[str, Any] = {
        "order_count": len(orders),
        "orders": orders,
        "note": (
            "record_id 是內部 id，回答使用者時講 order_no 或服務名稱，不要唸 record_id。"
            "can_review=true 才能呼叫 propose_review。"
        ),
    }
    if not args.get("only_reviewable"):
        result["pending_feedbacks"] = feedbacks
        result["pending_feedback_count"] = len(feedbacks)
    return result


def _can_review(order: dict[str, Any]) -> bool:
    """能不能評價。

    條件跟 api_server 的驗證一致：訂單狀態必須是 80（已完成）、
    且尚未評價過。這裡先判斷是為了不要讓模型產生註定被拒絕的草稿，
    真正的把關仍在 api_server。
    """
    return (
        str(order.get("order_status")) == "80"
        and str(order.get("comment_status")) != "02"
        and not order.get("review")
    )


# ==========================================================================
# DRAFT：產生草稿
# ==========================================================================
@tool(
    name="propose_submission",
    description=(
        "產生送出草稿給使用者確認。這個動作**不會真的送出**，"
        "只會在 App 上跳出確認卡片，使用者可以選擇直接送出或讓你帶他操作一次 GUI。"
        "所有必填題都要有答案才能呼叫。"
        "呼叫後不要說「已經幫你送出/訂好了」，要說「請確認以下內容」。"
    ),
    schema={
        "type": "object",
        "properties": {
            "vendor_id": {
                "type": "integer",
                "description": "服務商 id，用 find_service_vendors 回傳的 vendor_id",
            },
            "service_id": {
                "type": "integer",
                "description": (
                    "服務項目 id，用 find_service_vendors 回傳的 services[].service_id。"
                    "不是序號，是那個實際的數字。"
                ),
            },
            "service_type": {
                "type": "string",
                "enum": list(SERVICE_TYPE_LABELS.keys()),
            },
            "form_id": {
                "type": "integer",
                "description": "get_service_form 回傳的 form_id，照抄，不要自己編",
            },
            "summary": {
                "type": "string",
                "description": "一句話摘要，例如「初魚鐵板燒・8/3 19:00・2 位」",
            },
            "answers": {
                "type": "array",
                "description": "逐題答案，順序不重要但必填題不能漏",
                "items": {
                    "type": "object",
                    "properties": {
                        "topic_id": {
                            "type": "integer",
                            "description": (
                                "get_service_form 回傳的 topic_id，照抄。"
                                "不是題目順序，是那個實際的數字。"
                            ),
                        },
                        "title": {"type": "string"},
                        "value": {
                            "type": "string",
                            "description": "答案文字。複選用逗號分隔。",
                        },
                    },
                    "required": ["topic_id", "title", "value"],
                },
            },
            "contact_name": {"type": "string"},
            "contact_mobile": {"type": "string", "description": "09 開頭 10 碼"},
            "contact_email": {"type": "string"},
            "description": {"type": "string", "description": "補充說明，沒有就不傳"},
        },
        "required": [
            "vendor_id",
            "service_id",
            "service_type",
            "form_id",
            "summary",
            "answers",
            "contact_name",
            "contact_mobile",
        ],
    },
)
async def propose_submission(
    ctx: ToolContext, args: dict[str, Any]
) -> dict[str, Any]:
    settings = get_settings()

    # 模型輸出是不可信輸入。實測模型會把序號當成 id 傳進來（service_id=2、
    # form_id=1、topic_id=1…），所以這裡逐項對照真實表單結構驗證。
    # 驗證失敗回成 error，模型看得懂就會自己重抓正確的 id 再試一次。
    problem = await _validate_against_form(ctx, args)
    if problem:
        return problem

    mobile = str(args["contact_mobile"]).strip()
    if not re.fullmatch(r"09\d{8}", mobile):
        raise ValueError("contact_mobile 必須是 09 開頭的 10 碼手機號")

    answers = args["answers"]

    # feedback_content 的結構「依表單題目動態組成」，這裡用 topic_id 當 key，
    # 讓 App 的表單頁能對回每一題做預填。
    feedback_content = {
        str(a["topic_id"]): {"title": a["title"], "value": a["value"]}
        for a in answers
    }

    # 同一張草稿只產生一次。提示裡雖然已經寫了「不要重複產生」，但模型輸出
    # 一律當不可信輸入 —— 實測它會在處理下一個需求時順手再 propose 一次，
    # 使用者就看到兩張一模一樣的卡片。
    signature = _draft_signature(
        "feedback", int(args["form_id"]), sorted(feedback_content.items())
    )
    if existing := ctx.state.find_proposal(signature):
        return _already_proposed(existing)

    service_type = str(args["service_type"])
    payload = {
        # feedback_no 由送出端產生，草稿階段不決定 —— 避免草稿放久了單號撞號
        "service_id": int(args["service_id"]),
        "platform_code": "01",  # 01 = OP APP
        "form_id": int(args["form_id"]),
        "form_type": "01",
        "feedback_content": feedback_content,
        "contact_name": args["contact_name"],
        "contact_mobile": mobile,
        "contact_email": args.get("contact_email"),
        "description": args.get("description", ""),
        "inbr_account_id": ctx.actor_id,
    }
    payload = {k: v for k, v in payload.items() if v is not None}

    draft = OrderDraft(
        kind="feedback",
        service_id=int(args["service_id"]),
        service_type=service_type,
        form_id=int(args["form_id"]),
        vendor_id=int(args["vendor_id"]),
        payload=payload,
        summary=args["summary"],
        actor_id=ctx.actor_id,
        submit_method="POST",
        submit_path="/app-api/feedbacks",
        ttl_seconds=settings.draft_ttl_seconds,
    )
    draft_store.put(draft)
    ctx.emit("draft", **draft.to_event_payload())
    ctx.state.remember_proposal(
        "feedback", signature, args["summary"], draft.draft_id
    )

    return {
        "draft_id": draft.draft_id,
        "status": "awaiting_user_confirmation",
        "answered_topics": len(answers),
    }


def _draft_signature(kind: str, key: int | str, content: Any) -> str:
    """草稿的內容指紋。

    內容一樣就算同一張（使用者改了某個答案才算新草稿，那時本來就該重新產生）。
    """
    return f"{kind}|{key}|{content!r}"


def _already_proposed(existing: dict[str, Any]) -> dict[str, Any]:
    """回給模型的「已經產生過」說明。

    刻意回成正常結果而不是 error：這不是模型傳錯參數，而是它多做了一次。
    寫清楚卡片已經在畫面上、以及什麼情況才該重新產生，它就不會硬要再試。
    """
    return {
        "draft_id": existing["draft_id"],
        "status": "already_awaiting_user_confirmation",
        "detail": (
            f"這張草稿（{existing['summary']}）剛剛已經產生過，卡片就在畫面上，"
            "不需要也不要再產生一次。直接接著回應使用者目前的需求就好。"
            "只有在使用者要求修改內容時才重新呼叫（內容不同會算新的草稿）。"
        ),
    }


async def _validate_against_form(
    ctx: ToolContext, args: dict[str, Any]
) -> dict[str, Any] | None:
    """把草稿內容對照真實表單結構驗一遍。

    回 None 表示通過；回 dict 表示有問題，內容會當成 tool error 回餵給模型，
    訊息要寫得夠具體讓它能自己修好，不要只說「參數錯誤」。
    """
    vendor_id = int(args["vendor_id"])
    service_id = int(args["service_id"])

    full = await ctx.backend.get_service_form(service_id)
    if not full:
        return {
            "error": "ServiceFormNotFound",
            "detail": (
                f"service_id={service_id} 找不到對應表單。"
                "確認傳的是 find_service_vendors 回傳的 services[].service_id，不是序號。"
            ),
        }

    form = full["form"]
    topics = {int(t["id"]): t for t in full.get("topics", [])}

    # form_id
    if int(args["form_id"]) != int(form["id"]):
        return {
            "error": "FormIdMismatch",
            "detail": (
                f"form_id={args['form_id']} 不對，service_id={service_id} 的 form_id "
                f"是 {form['id']}。請用 get_service_form 回傳的 form_id。"
            ),
        }

    # service_id 必須真的屬於這個服務商
    service_type = str(args["service_type"])
    vendors = await ctx.backend.find_vendors(service_type, None)
    vendor = next((v for v in vendors if int(v["id"]) == vendor_id), None)
    valid_service_ids = (
        {int(s["id"]) for s in vendor.get("matched_services", [])} if vendor else set()
    )
    if valid_service_ids and int(args["service_id"]) not in valid_service_ids:
        return {
            "error": "ServiceIdMismatch",
            "detail": (
                f"service_id={args['service_id']} 不屬於 vendor_id={vendor_id}。"
                f"這家可用的 service_id 是 {sorted(valid_service_ids)}。"
            ),
        }

    answers = args.get("answers") or []
    if not answers:
        return {
            "error": "NoAnswers",
            "detail": "answers 不能為空，請先依 get_service_form 的 topics 問完使用者。",
        }

    # topic_id 必須存在
    answered: dict[int, str] = {}
    for a in answers:
        tid = int(a["topic_id"])
        if tid not in topics:
            return {
                "error": "UnknownTopicId",
                "detail": (
                    f"topic_id={tid} 不存在於 form {form['id']}。"
                    f"合法的 topic_id 是 {sorted(topics)}。"
                    "請照抄 get_service_form 回傳的 topic_id，不要用題目順序。"
                ),
            }
        answered[tid] = str(a["value"]).strip()

    # 必填題要有答案（照片題除外，管家填不了）
    missing = [
        f"{tid}（{t.get('title', '')}）"
        for tid, t in topics.items()
        if t.get("is_required") == "1"
        and str(t.get("type")) not in UNFILLABLE_TOPIC_TYPES
        and not answered.get(tid)
    ]
    if missing:
        return {
            "error": "MissingRequiredAnswers",
            "detail": f"還有必填題沒答：{', '.join(missing)}。請先問使用者。",
        }

    # 單選/複選的答案必須在 options 裡
    for tid, value in answered.items():
        topic = topics[tid]
        ttype = str(topic.get("type"))
        if ttype not in ("3", "4"):
            continue
        allowed = {str(o["option_name"]) for o in topic.get("options", [])}
        if not allowed:
            continue
        picked = [v.strip() for v in value.split(",") if v.strip()] if ttype == "4" else [value]
        bad = [p for p in picked if p not in allowed]
        if bad:
            return {
                "error": "InvalidOption",
                "detail": (
                    f"題目 {tid}（{topic.get('title', '')}）的答案 {bad} 不在選項裡。"
                    f"只能選 {sorted(allowed)}。"
                ),
            }

    return None


# ==========================================================================
# DRAFT：訂單評價
# ==========================================================================
@tool(
    name="propose_review",
    description=(
        "產生訂單評價草稿給使用者確認。**不會真的送出**，"
        "只會在 App 上跳出確認卡片。"
        "呼叫前必須先用 list_my_orders 確認該筆訂單 can_review=true。"
        "呼叫後不要說「已經幫你評價了」，要說「請確認以下評價內容」。"
    ),
    schema={
        "type": "object",
        "properties": {
            "record_id": {
                "type": "integer",
                "description": (
                    "訂單內部 id，用 list_my_orders 回傳的 record_id 照抄。"
                    "不是 order_no，也不是「第幾筆」的序號。"
                ),
            },
            "overall_rating": {
                "type": "integer",
                "minimum": 1,
                "maximum": 5,
                "description": "整體評分 1~5。使用者只說「很好」「不錯」時要問出幾分，不要自己決定。",
            },
            "review_content": {
                "type": "string",
                "description": (
                    "評價文字。用使用者自己說的話整理，不要幫他加油添醋或補他沒說過的優點。"
                ),
            },
            "rating_detail": {
                "type": "object",
                "description": (
                    "分項評分，只在使用者明確分項評論時才傳，"
                    "例如 {\"service\": 5, \"attitude\": 4}。值同樣是 1~5。"
                ),
            },
        },
        "required": ["record_id", "overall_rating"],
    },
)
async def propose_review(ctx: ToolContext, args: dict[str, Any]) -> dict[str, Any]:
    settings = get_settings()
    record_id = int(args["record_id"])

    rating = int(args["overall_rating"])
    if not 1 <= rating <= 5:
        raise ValueError("overall_rating 必須是 1~5 的整數")

    # 模型輸出當不可信輸入：record_id 必須真的是這位使用者的訂單，
    # 而且狀態允許評價。不驗的話會產生註定被 api_server 打回來的草稿，
    # 使用者按了「直接送出」才失敗，體驗更差。
    overview = await ctx.backend.get_orders_overview(ctx.actor_id)
    orders = {int(o["record_id"]): o for o in (overview.get("orders") or [])}

    order = orders.get(record_id)
    if order is None:
        return {
            "error": "OrderNotFound",
            "detail": (
                f"record_id={record_id} 不在這位使用者的訂單裡。"
                f"他的訂單 record_id 是 {sorted(orders)}。"
                "請重新呼叫 list_my_orders 取得正確的 record_id，不要用序號。"
            ),
        }

    if not _can_review(order):
        reason = (
            "這筆訂單已經評價過了"
            if str(order.get("comment_status")) == "02" or order.get("review")
            else f"這筆訂單狀態是「{order_status_label(order.get('order_type'), order.get('order_status'))}」，"
            "只有已完成的訂單才能評價"
        )
        return {
            "error": "OrderNotReviewable",
            "detail": (
                f"{reason}。請告訴使用者原因，"
                "或用 list_my_orders 的 only_reviewable=true 找出可評價的訂單。"
            ),
        }

    detail = args.get("rating_detail") or None
    if detail is not None:
        bad = {k: v for k, v in detail.items() if not (isinstance(v, int) and 1 <= v <= 5)}
        if bad:
            raise ValueError(f"rating_detail 的值必須是 1~5 的整數，這些不合法：{bad}")

    payload = {
        "inbr_account_id": ctx.actor_id,
        "overall_rating": rating,
        "review_content": args.get("review_content"),
        "rating_detail": detail,
    }
    payload = {k: v for k, v in payload.items() if v is not None}

    signature = _draft_signature("review", record_id, sorted(payload.items(), key=str))
    if existing := ctx.state.find_proposal(signature):
        return _already_proposed(existing)

    draft = OrderDraft(
        kind="review",
        service_id=order.get("service_id"),
        payload=payload,
        summary=args.get("summary")
        or f"評價「{order.get('order_no')}」{rating} 星",
        actor_id=ctx.actor_id,
        submit_method="POST",
        submit_path=f"/app-api/orders/{record_id}/review",
        ttl_seconds=settings.draft_ttl_seconds,
    )
    draft_store.put(draft)
    ctx.emit("draft", **draft.to_event_payload())
    ctx.state.remember_proposal("review", signature, draft.summary, draft.draft_id)

    return {
        "draft_id": draft.draft_id,
        "status": "awaiting_user_confirmation",
        "order_no": order.get("order_no"),
    }


# ==========================================================================
# DRAFT：修改個人聯絡資料
# ==========================================================================
@tool(
    name="propose_profile_update",
    description=(
        "產生修改個人聯絡資料的草稿給使用者確認。**不會真的修改**。"
        "使用者說「幫我改手機」「我換 email 了」時用這個。"
        "只傳要改的欄位，沒提到的不要傳。"
        "呼叫後不要說「已經幫你改好了」，要說「請確認要改成這樣」。"
    ),
    schema={
        "type": "object",
        "properties": {
            "contact_name": {"type": "string", "description": "新的姓名"},
            "contact_mobile": {
                "type": "string",
                "description": "新的手機號碼，09 開頭 10 碼",
            },
            "contact_email": {"type": "string", "description": "新的 Email"},
        },
        "required": [],
    },
)
async def propose_profile_update(
    ctx: ToolContext, args: dict[str, Any]
) -> dict[str, Any]:
    settings = get_settings()

    fields = {
        k: str(args[k]).strip()
        for k in ("contact_name", "contact_mobile", "contact_email")
        if args.get(k)
    }
    if not fields:
        return {
            "error": "NothingToUpdate",
            "detail": "沒有任何要修改的欄位。先問使用者想改什麼（姓名／手機／Email）。",
        }

    if mobile := fields.get("contact_mobile"):
        if not re.fullmatch(r"09\d{8}", mobile):
            raise ValueError("contact_mobile 必須是 09 開頭的 10 碼手機號")

    if email := fields.get("contact_email"):
        # 只做基本形狀檢查，真正的驗證交給後端
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
            raise ValueError(f"contact_email 格式看起來不對：{email}")

    # 拿現值做對照，草稿卡片才能顯示「原本 → 改成」
    current = await ctx.backend.get_user(ctx.actor_id)
    changes = {
        k: {"from": current.get(k), "to": v}
        for k, v in fields.items()
        if current.get(k) != v
    }
    if not changes:
        return {
            "error": "NoActualChange",
            "detail": (
                "要改的內容跟現在完全一樣，不需要修改。"
                "跟使用者確認他是不是想改別的欄位。"
            ),
        }

    labels = {"contact_name": "姓名", "contact_mobile": "手機", "contact_email": "Email"}
    summary = "、".join(
        f"{labels[k]}改成 {c['to']}" for k, c in changes.items()
    )

    signature = _draft_signature("profile", ctx.actor_id, sorted(fields.items()))
    if existing := ctx.state.find_proposal(signature):
        return _already_proposed(existing)

    draft = OrderDraft(
        kind="profile",
        payload={k: c["to"] for k, c in changes.items()},
        summary=summary,
        actor_id=ctx.actor_id,
        submit_method="PATCH",
        submit_path=f"/app-api/users/{ctx.actor_id}",
        ttl_seconds=settings.draft_ttl_seconds,
    )
    draft_store.put(draft)
    # changes 讓 App 的確認卡片能顯示前後對照，不用自己再查一次
    ctx.emit("draft", changes=changes, **draft.to_event_payload())
    ctx.state.remember_proposal("profile", signature, summary, draft.draft_id)

    return {
        "draft_id": draft.draft_id,
        "status": "awaiting_user_confirmation",
        "changed_fields": sorted(changes),
    }
