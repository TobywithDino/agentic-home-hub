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
from schemas import SERVICE_TYPE_LABELS, OrderDraft, draft_store
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

LABELS: dict[int, str] = {
    1: "寵物友善",
    2: "24小時營業",
    3: "專業認證",
    4: "免費估價",
    5: "到府服務",
    6: "快速到達",
}


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
                    "篩選標籤，只在使用者明確提到時才傳："
                    + "、".join(f"{k}={v}" for k, v in LABELS.items())
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
        payload=payload,
        summary=args["summary"],
        actor_id=ctx.actor_id,
        ttl_seconds=settings.draft_ttl_seconds,
    )
    draft_store.put(draft)
    ctx.emit("draft", **draft.to_event_payload())

    return {
        "draft_id": draft.draft_id,
        "status": "awaiting_user_confirmation",
        "answered_topics": len(answers),
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
