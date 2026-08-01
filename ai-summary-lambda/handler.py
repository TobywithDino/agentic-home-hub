# -*- coding: utf-8 -*-
"""
AI Review Summary Lambda Handler

Lambda 入口。支援兩種觸發方式：
  1. EventBridge Scheduler（每週定時）：event 為空 dict 或帶 source="aws.scheduler"
  2. API Gateway HTTP 手動觸發（demo 用）：event 帶 queryStringParameters

event 參數（皆為可選，不傳就跑全部）：
  - mode       : "consumer" | "merchant" | "all"（預設 "all"）
  - service_id : 只跑單一服務項目的消費者摘要（mode="consumer" 時有效）
  - vendor_id  : 只跑單一商家的商家摘要（mode="merchant" 時有效）

回傳 / log：
  - Lambda CloudWatch Logs 會印出每次 Bedrock 的完整回覆
  - HTTP 觸發時額外把摘要結果回傳在 response body（方便 demo）
"""

import json
import logging
import os

import boto3
import httpx

from prompts import build_consumer_prompt, build_merchant_prompt

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── 環境變數（Lambda 設定，有預設值方便本地測試） ─────────────────────────────
BFF_BASE_URL = os.environ.get("BFF_BASE_URL", "http://52.10.163.115:8100")
BEDROCK_MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID", "anthropic.claude-sonnet-4-5-20250929-v1:0"
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
        service_names = {int(only_service_id): f"Service {only_service_id}"}
    else:
        # 拉出全平台所有服務項目（用 bff 的 api_server 直接查或用 /app-api 端點）
        # 這裡用 api_server 直接列出所有服務（bff 沒有「列出全部服務」的 BFF 端點）
        service_ids, service_names = _fetch_all_services()

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
    若 only_vendor_id 有值，只跑該商家。
    """
    summaries = []

    if only_vendor_id:
        vendor_ids = [int(only_vendor_id)]
        vendor_names = {int(only_vendor_id): f"Vendor {only_vendor_id}"}
    else:
        vendor_ids, vendor_names = _fetch_all_vendors()

    for vendor_id in vendor_ids:
        vendor_name = vendor_names.get(vendor_id, f"Vendor {vendor_id}")
        logger.info("[merchant] Processing vendor_id=%d name=%s", vendor_id, vendor_name)

        reviews = _fetch_merchant_reviews(vendor_id)
        if not reviews:
            logger.info("[merchant] vendor_id=%d: no reviews, skipping", vendor_id)
            continue

        prompt = build_merchant_prompt(vendor_name, reviews)
        summary_text = _call_bedrock(prompt)

        logger.info(
            "[merchant] vendor_id=%d | review_count=%d\n%s\n%s\n%s",
            vendor_id,
            len(reviews),
            "=" * 60,
            summary_text,
            "=" * 60,
        )

        summaries.append({
            "type": "merchant",
            "vendor_id": vendor_id,
            "vendor_name": vendor_name,
            "review_count": len(reviews),
            "summary": summary_text,
        })

    return summaries


# ── BFF HTTP calls ────────────────────────────────────────────────────────────

def _fetch_all_services() -> tuple[list[int], dict[int, str]]:
    """從 bff_server GET /merchant-api/services 拉出所有服務項目 id 與名稱。"""
    try:
        resp = httpx.get(
            f"{BFF_BASE_URL}/merchant-api/services",
            timeout=30,
        )
        resp.raise_for_status()
        items = resp.json()
        service_ids = [item["id"] for item in items]
        service_names = {item["id"]: item.get("name", f"Service {item['id']}") for item in items}
        logger.info("Fetched %d services from bff_server", len(service_ids))
        return service_ids, service_names
    except Exception as e:
        logger.error("Failed to fetch services: %s", e)
        return [], {}


def _fetch_all_vendors() -> tuple[list[int], dict[int, str]]:
    """從 bff_server GET /merchant-api/vendors 拉出所有服務商 id 與名稱。"""
    try:
        resp = httpx.get(
            f"{BFF_BASE_URL}/merchant-api/vendors",
            timeout=30,
        )
        resp.raise_for_status()
        items = resp.json()
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
                "topP": 0.9,
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
