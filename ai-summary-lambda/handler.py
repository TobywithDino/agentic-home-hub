# -*- coding: utf-8 -*-
"""
AI Review Summary Lambda Handler

Lambda 入口。支援兩種觸發方式：
  1. EventBridge Scheduler（每週定時）：event 為空 dict 或帶 source="aws.scheduler"
  2. CLI invoke / Console Test（手動/demo 用）：event 頂層直接帶參數

event 參數（皆為可選，不傳就跑全部）：
  - mode       : "consumer" | "merchant" | "all"（預設 "all"）
  - service_id : 只跑單一服務項目的消費者摘要（mode="consumer" 時有效）
  - vendor_id  : 只跑單一商家的商家摘要（mode="merchant" 時有效）

兩種摘要視角：
  consumer（寫入 mms_review_summary_service）
    - 針對每個服務項目，分析全部評價，輸出純文字口碑摘要
    - 寫回：PUT /merchant-api/services/{id}/review-summary

  merchant（寫入 mms_review_summary_vendor）
    - 針對每個商家，只分析近 7 天評價，輸出結構化 JSON：
        summary_content:  分析期間字串
        vendor_name:      商家名稱（頂層欄位）
        summary_highlights: { summary（≤50字字串）, suggestions（3~4點陣列） }
        sentiment_stats:  { positive, neutral, negative }
    - 寫回：PUT /merchant-api/vendors/{id}/review-summary

回傳 / log：
  - Lambda CloudWatch Logs 會印出每次 Bedrock 的完整回覆
  - CLI invoke 觸發時 response body 包含完整摘要結果（方便 demo）
"""

import json
import logging
import os
from datetime import datetime, timedelta, timezone

import boto3
import httpx

from prompts import build_consumer_prompt, build_merchant_prompt

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── 環境變數（Lambda 設定，有預設值方便本地測試） ─────────────────────────────
BFF_BASE_URL = os.environ.get("BFF_BASE_URL", "http://52.10.163.115:8100")
BEDROCK_MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID", "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
)
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "us-west-2")
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "2048"))


# ── Bedrock client（module-level，Lambda 容器重用時只初始化一次） ───────────────
bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)


# ── 主入口 ────────────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    logger.info("Lambda triggered. event=%s", json.dumps(event, ensure_ascii=False))

    # 解析觸發參數（相容 EventBridge 與 API Gateway）
    params = _extract_params(event)
    mode = params.get("mode", "all")
    service_id = params.get("service_id")
    vendor_id = params.get("vendor_id")

    results = []

    if mode in ("consumer", "all"):
        results.extend(_run_consumer_summaries(service_id))

    if mode in ("merchant", "all"):
        results.extend(_run_merchant_summaries(vendor_id))

    logger.info(
        "All summaries done. total=%d", len(results)
    )

    # API Gateway 觸發時回傳完整結果；EventBridge 觸發時只回傳計數
    is_http = "httpMethod" in event or "requestContext" in event
    if is_http:
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json; charset=utf-8"},
            "body": json.dumps(
                {"ok": True, "count": len(results), "summaries": results},
                ensure_ascii=False,
                indent=2,
            ),
        }

    return {"ok": True, "count": len(results)}


# ── Consumer summaries ────────────────────────────────────────────────────────

def _run_consumer_summaries(only_service_id: str | None) -> list[dict]:
    """
    消費者視角：針對每個服務項目產生摘要。
    若 only_service_id 有值，只跑該服務。
    """
    summaries = []

    if only_service_id:
        service_ids = [int(only_service_id)]
        # 查實際服務名稱與 service_vendor_id
        _, _names, _meta = _fetch_all_services()
        sid = int(only_service_id)
        service_names = {sid: _names.get(sid, f"Service {only_service_id}")}
        service_names_meta = {sid: _meta.get(sid, {"service_vendor_id": None})}
    else:
        service_ids, service_names, service_names_meta = _fetch_all_services()

    for service_id in service_ids:
        service_name = service_names.get(service_id, f"Service {service_id}")
        logger.info("[consumer] Processing service_id=%d name=%s", service_id, service_name)

        reviews = _fetch_consumer_reviews(service_id)
        if not reviews:
            logger.info("[consumer] service_id=%d: no reviews, skipping", service_id)
            continue

        prompt = build_consumer_prompt(service_name, reviews)
        summary_text = _call_bedrock(prompt)

        logger.info(
            "[consumer] service_id=%d | review_count=%d\n%s\n%s\n%s",
            service_id,
            len(reviews),
            "=" * 60,
            summary_text,
            "=" * 60,
        )

        # 計算寫回需要的聚合值
        avg_rating = _calc_avg_rating(reviews)
        latest_review_time = _calc_latest_review_time(reviews)
        service_vendor_id = service_names_meta.get(service_id, {}).get("service_vendor_id")

        # 寫回 DB（PUT /merchant-api/services/{service_id}/review-summary）
        _upsert_service_summary(
            service_id=service_id,
            service_name=service_name,
            service_vendor_id=service_vendor_id,
            summary_text=summary_text,
            review_count=len(reviews),
            avg_rating=avg_rating,
            latest_review_time=latest_review_time,
        )

        summaries.append({
            "type": "consumer",
            "service_id": service_id,
            "service_name": service_name,
            "review_count": len(reviews),
            "summary": summary_text,
        })

    return summaries


# ── Merchant summaries ────────────────────────────────────────────────────────

def _run_merchant_summaries(only_vendor_id: str | None) -> list[dict]:
    """
    商家視角：針對每個商家產生跨服務項目的綜合摘要。
    只使用近一週（7天）內的評價。
    若 only_vendor_id 有值，只跑該商家。

    流程：
    1. 拉商家清單（含名稱）
    2. 拉全平台服務名稱對照表（供 prompt 顯示服務名稱而非 ID）
    3. 拉該商家全部評價，篩選近 7 天
    4. 呼叫 Bedrock 產生 JSON（summary / suggestions / sentiment_stats）
    5. 計算聚合值（全部評價，供 is_stale 使用）
    6. 寫回 DB
    """
    summaries = []

    # 計算近一週時間範圍（UTC）
    now_utc = datetime.now(timezone.utc)
    week_ago = now_utc - timedelta(days=7)
    week_start = week_ago.strftime("%Y/%m/%d")
    week_end = now_utc.strftime("%Y/%m/%d")
    week_ago_iso = week_ago.isoformat()

    if only_vendor_id:
        vendor_ids = [int(only_vendor_id)]
        _, vendor_names = _fetch_all_vendors(vendor_id_filter=int(only_vendor_id))
        if not vendor_names:
            vendor_names = {int(only_vendor_id): f"Vendor {only_vendor_id}"}
    else:
        vendor_ids, vendor_names = _fetch_all_vendors()

    for vendor_id in vendor_ids:
        vendor_name = vendor_names.get(vendor_id, f"Vendor {vendor_id}")
        logger.info("[merchant] Processing vendor_id=%d name=%s", vendor_id, vendor_name)

        all_reviews = _fetch_merchant_reviews(vendor_id)

        # 拉取此商家的服務名稱對照表（用於 prompt 顯示服務名稱而非 ID）
        _, _svc_names, _ = _fetch_all_services()
        # 只保留屬於此商家的服務名稱（_fetch_all_services 拉全平台，過濾一下）
        vendor_service_ids = {r.get("service_id") for r in all_reviews if r.get("service_id")}
        service_names_for_prompt = {sid: _svc_names.get(sid, f"服務{sid}") for sid in vendor_service_ids}

        # 篩選近一週的評價
        recent_reviews = _filter_reviews_by_date(all_reviews, week_ago_iso)
        logger.info(
            "[merchant] vendor_id=%d: total=%d recent(7d)=%d",
            vendor_id, len(all_reviews), len(recent_reviews),
        )

        # 近一週無評價時仍呼叫 LLM（讓 LLM 輸出「本週尚無新評價資料」的結構化回應）
        prompt = build_merchant_prompt(vendor_name, recent_reviews, week_start, week_end, service_names_for_prompt)
        raw_output = _call_bedrock(prompt)

        logger.info(
            "[merchant] vendor_id=%d | recent_count=%d\n%s\n%s\n%s",
            vendor_id,
            len(recent_reviews),
            "=" * 60,
            raw_output,
            "=" * 60,
        )

        # 解析 LLM 輸出的 JSON
        parsed = _parse_merchant_json(raw_output, vendor_id)
        summary = parsed.get("summary", "")
        suggestions = parsed.get("suggestions", [])
        sentiment_stats = parsed.get("sentiment_stats", {"positive": 0, "neutral": 0, "negative": 0})

        # 聚合值仍用全部評價計算（給 is_stale 判斷用），統計資料用近一週
        avg_rating = _calc_avg_rating(all_reviews)
        latest_review_time = _calc_latest_review_time(all_reviews)
        service_breakdown = _calc_service_breakdown(all_reviews)

        # 寫回 DB
        _upsert_vendor_summary(
            vendor_id=vendor_id,
            vendor_name=vendor_name,
            summary=summary,
            suggestions=suggestions,
            sentiment_stats=sentiment_stats,
            week_start=week_start,
            week_end=week_end,
            recent_review_count=len(recent_reviews),
            total_review_count=len(all_reviews),
            avg_rating=avg_rating,
            latest_review_time=latest_review_time,
            service_breakdown=service_breakdown,
        )

        summaries.append({
            "type": "merchant",
            "vendor_id": vendor_id,
            "vendor_name": vendor_name,
            "recent_review_count": len(recent_reviews),
            "summary": summary,
            "suggestions": suggestions,
            "sentiment_stats": sentiment_stats,
        })

    return summaries


# ── BFF HTTP calls ────────────────────────────────────────────────────────────

def _fetch_all_services() -> tuple[list[int], dict[int, str], dict[int, dict]]:
    """從 bff_server GET /merchant-api/services 拉出所有服務項目。
    回傳：(service_ids, {id: name}, {id: {service_vendor_id: ...}})
    """
    try:
        resp = httpx.get(
            f"{BFF_BASE_URL}/merchant-api/services",
            timeout=30,
        )
        resp.raise_for_status()
        items = resp.json()
        service_ids = [item["id"] for item in items]
        service_names = {item["id"]: item.get("name", f"Service {item['id']}") for item in items}
        service_meta = {
            item["id"]: {"service_vendor_id": item.get("service_vendor_id")}
            for item in items
        }
        logger.info("Fetched %d services from bff_server", len(service_ids))
        return service_ids, service_names, service_meta
    except Exception as e:
        logger.error("Failed to fetch services: %s", e)
        return [], {}, {}


def _fetch_all_vendors(vendor_id_filter: int | None = None) -> tuple[list[int], dict[int, str]]:
    """從 bff_server GET /merchant-api/vendors 拉出所有服務商 id 與名稱。
    若指定 vendor_id_filter，只回傳該商家（單筆查詢用）。
    """
    try:
        resp = httpx.get(
            f"{BFF_BASE_URL}/merchant-api/vendors",
            timeout=30,
        )
        resp.raise_for_status()
        items = resp.json()
        if vendor_id_filter is not None:
            items = [item for item in items if item["id"] == vendor_id_filter]
        vendor_ids = [item["id"] for item in items]
        vendor_names = {item["id"]: item.get("name", f"Vendor {item['id']}") for item in items}
        logger.info("Fetched %d vendors from bff_server", len(vendor_ids))
        return vendor_ids, vendor_names
    except Exception as e:
        logger.error("Failed to fetch vendors: %s", e)
        return [], {}


def _fetch_consumer_reviews(service_id: int) -> list[dict]:
    """呼叫 bff GET /app-api/services/{service_id}/reviews。
    回傳格式：ReviewOut 陣列（非分頁包裝，直接是 list）。
    """
    url = f"{BFF_BASE_URL}/app-api/services/{service_id}/reviews"
    try:
        resp = httpx.get(url, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        # 防禦：回傳有時可能是 {"items": [...]} 或直接是陣列
        reviews = data if isinstance(data, list) else data.get("items", [])
        logger.info("Fetched %d reviews for service_id=%d", len(reviews), service_id)
        return reviews
    except Exception as e:
        logger.error("Failed to fetch reviews for service_id=%d: %s", service_id, e)
        return []


def _fetch_merchant_reviews(vendor_id: int) -> list[dict]:
    """呼叫 bff GET /merchant-api/vendors/{vendor_id}/reviews。
    回傳格式：ReviewOut 陣列（不分頁，直接是 list）。
    """
    url = f"{BFF_BASE_URL}/merchant-api/vendors/{vendor_id}/reviews"
    try:
        resp = httpx.get(url, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        reviews = data if isinstance(data, list) else data.get("items", [])
        logger.info("Fetched %d reviews for vendor_id=%d", len(reviews), vendor_id)
        return reviews
    except Exception as e:
        logger.error("Failed to fetch reviews for vendor_id=%d: %s", vendor_id, e)
        return []


# ── Bedrock call ──────────────────────────────────────────────────────────────

def _call_bedrock(prompt: str) -> str:
    """
    呼叫 Bedrock Claude，回傳純文字回覆。
    使用 Converse API（新版統一介面，相容所有 Bedrock model）。
    """
    try:
        response = bedrock.converse(
            modelId=BEDROCK_MODEL_ID,
            messages=[
                {
                    "role": "user",
                    "content": [{"text": prompt}],
                }
            ],
            inferenceConfig={
                "maxTokens": MAX_TOKENS,
                "temperature": 0.3,   # 摘要任務低溫，輸出穩定
                # topP 不能與 temperature 並用（Claude Sonnet 4.x 限制）
            },
        )
        output_text = response["output"]["message"]["content"][0]["text"]
        usage = response.get("usage", {})
        logger.info(
            "Bedrock usage: inputTokens=%s outputTokens=%s",
            usage.get("inputTokens"),
            usage.get("outputTokens"),
        )
        return output_text
    except Exception as e:
        logger.error("Bedrock call failed: %s", e)
        return f"[ERROR] Bedrock call failed: {e}"


# ── Helpers ───────────────────────────────────────────────────────────────────

def _extract_params(event: dict) -> dict:
    """
    從各種觸發來源中提取統一的參數 dict。
    支援：
      - API Gateway v1 (httpMethod)
      - API Gateway v2 / Function URL (requestContext.http)
      - EventBridge / direct invoke (直接在 event 頂層帶參數)
    """
    # API Gateway v1
    if "queryStringParameters" in event and event["queryStringParameters"]:
        return event["queryStringParameters"]

    # API Gateway v2
    if "queryStringParameters" in event and event.get("version") == "2.0":
        return event.get("queryStringParameters") or {}

    # Direct invoke 或 EventBridge 自訂 payload（直接在 event 頂層）
    # 過濾掉 EventBridge 自帶的 metadata key
    skip_keys = {"source", "detail-type", "detail", "id", "version", "account", "time", "region", "resources"}
    return {k: v for k, v in event.items() if k not in skip_keys}


# ── 聚合計算 ──────────────────────────────────────────────────────────────────

def _calc_avg_rating(reviews: list[dict]) -> float | None:
    """計算評價平均分，無評價時回傳 None。"""
    ratings = [r["overall_rating"] for r in reviews if r.get("overall_rating") is not None]
    if not ratings:
        return None
    return round(sum(ratings) / len(ratings), 2)


def _calc_latest_review_time(reviews: list[dict]) -> str | None:
    """取最新一筆評價的 cre_time（ISO8601 字串），無評價時回傳 None。"""
    times = [r["cre_time"] for r in reviews if r.get("cre_time")]
    if not times:
        return None
    return max(times)


def _calc_service_breakdown(reviews: list[dict]) -> list[dict]:
    """依 service_id 分組，計算各服務項目的評價數與平均分。"""
    from collections import defaultdict
    groups: dict[int, list[int]] = defaultdict(list)
    for r in reviews:
        sid = r.get("service_id")
        rating = r.get("overall_rating")
        if sid is not None and rating is not None:
            groups[sid].append(rating)
    return [
        {
            "service_id": sid,
            "review_count": len(ratings),
            "avg_rating": round(sum(ratings) / len(ratings), 2),
        }
        for sid, ratings in groups.items()
    ]


def _filter_reviews_by_date(reviews: list[dict], since_iso: str) -> list[dict]:
    """回傳 cre_time >= since_iso 的評價，用於篩選近一週資料。"""
    result = []
    for r in reviews:
        cre_time = r.get("cre_time", "")
        if cre_time and cre_time >= since_iso:
            result.append(r)
    return result


def _parse_merchant_json(raw: str, vendor_id: int) -> dict:
    """解析 LLM 輸出的 JSON 字串，失敗時回傳安全預設值。"""
    try:
        # LLM 偶爾會在 JSON 前後夾 markdown code fence，嘗試清除
        text = raw.strip()
        if text.startswith("```"):
            lines = text.split("\n")
            text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
        return json.loads(text)
    except Exception as e:
        logger.error("[merchant] vendor_id=%d failed to parse LLM JSON: %s\nraw=%s", vendor_id, e, raw[:200])
        return {
            "summary": "本週 AI 分析暫時無法產生。",
            "suggestions": ["請稍後重新觸發 AI 分析。"],
            "sentiment_stats": {"positive": 0, "neutral": 0, "negative": 0},
        }

# ── 寫回 DB ───────────────────────────────────────────────────────────────────

def _upsert_service_summary(
    service_id: int,
    service_name: str,
    service_vendor_id: int | None,
    summary_text: str,
    review_count: int,
    avg_rating: float | None,
    latest_review_time: str | None,
) -> None:
    """PUT /merchant-api/services/{service_id}/review-summary 寫回服務項目摘要。"""
    url = f"{BFF_BASE_URL}/merchant-api/services/{service_id}/review-summary"
    body = {
        "service_vendor_id": service_vendor_id,
        "service_name": service_name,
        "summary_content": summary_text,
        "source_review_count": review_count,
        "source_avg_rating": avg_rating,
        "latest_review_cre_time": latest_review_time,
        "ai_model": BEDROCK_MODEL_ID,
        "generate_status": "02",  # 02 = 已完成
        "error_message": None,
    }
    try:
        resp = httpx.put(url, json=body, timeout=30)
        resp.raise_for_status()
        logger.info("[consumer] service_id=%d summary upserted (status=%d)", service_id, resp.status_code)
    except Exception as e:
        logger.error("[consumer] service_id=%d failed to upsert summary: %s", service_id, e)


def _upsert_vendor_summary(
    vendor_id: int,
    vendor_name: str,
    summary: str,
    suggestions: list[str],
    sentiment_stats: dict,
    week_start: str,
    week_end: str,
    recent_review_count: int,
    total_review_count: int,
    avg_rating: float | None,
    latest_review_time: str | None,
    service_breakdown: list[dict],
) -> None:
    """PUT /merchant-api/vendors/{vendor_id}/review-summary 寫回商家摘要。

    頂層欄位對應：
    - summary_content:  分析期間字串（供前端顯示「分析期間：...」）
    - vendor_name:      商家名稱（頂層欄位，平行於 summary_content）
    - summary_highlights: { summary, suggestions }（UI 兩個文字區塊）
    - sentiment_stats:  { positive, neutral, negative }（UI 情緒圓餅圖）
    """
    url = f"{BFF_BASE_URL}/merchant-api/vendors/{vendor_id}/review-summary"

    # summary_content 存分析期間，前端可直接顯示
    summary_content = f"分析期間：{week_start} – {week_end}"

    body = {
        "summary_content": summary_content,
        "vendor_name": vendor_name,
        "summary_highlights": {
            "summary": summary,
            "suggestions": suggestions,
        },
        "sentiment_stats": sentiment_stats,
        "service_breakdown": service_breakdown,
        "source_review_count": total_review_count,
        "source_avg_rating": avg_rating,
        "latest_review_cre_time": latest_review_time,
        "ai_model": BEDROCK_MODEL_ID,
        "generate_status": "02",  # 02 = 已完成
        "error_message": None,
    }
    try:
        resp = httpx.put(url, json=body, timeout=30)
        resp.raise_for_status()
        logger.info(
            "[merchant] vendor_id=%d summary upserted (status=%d) recent=%d",
            vendor_id, resp.status_code, recent_review_count,
        )
    except Exception as e:
        logger.error("[merchant] vendor_id=%d failed to upsert summary: %s", vendor_id, e)
