# -*- coding: utf-8 -*-
"""
Bedrock Converse tool-use 迴圈（async）。

一輪使用者訊息可能觸發多次「模型思考 → 執行 tool → 結果回餵」，
這個 async generator 把整個過程攤成 SSE 事件吐出去。

boto3 是同步的，所以模型呼叫用 asyncio.to_thread 丟到執行緒，
避免阻塞 event loop 讓其他請求排隊。
"""
from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import AsyncIterator
from typing import Any

import boto3
from botocore.config import Config

from backend import BackendClient
from config import get_settings
from memory import get_memory_client
from prompts import build_system_prompt
from schemas import event
from session_state import session_store
from tools import ToolContext, dispatch, tool_config

log = logging.getLogger(__name__)

_client = None


def _bedrock():
    """延後建立 client，讓設定與憑證在 import 時還沒就緒也不會炸。"""
    global _client
    if _client is None:
        settings = get_settings()
        _client = boto3.client(
            "bedrock-runtime",
            region_name=settings.aws_region,
            config=Config(
                retries={"max_attempts": 4, "mode": "adaptive"},  # 吸收 Throttling
                read_timeout=120,
                connect_timeout=10,
            ),
        )
    return _client


async def run_turn(
    user_text: str,
    actor_id: str,
    session_id: str,
    backend: BackendClient,
) -> AsyncIterator[dict[str, Any]]:
    """跑一輪對話，yield 事件 dict（由 BedrockAgentCoreApp 包成 SSE）。"""
    settings = get_settings()
    memory = get_memory_client()

    # 短期歷史與長期偏好可以並行抓，省一次往返延遲
    history, preferences = await asyncio.gather(
        memory.load_history(actor_id, session_id),
        memory.recall_preferences(actor_id, user_text),
    )

    messages: list[dict[str, Any]] = [
        *history,
        {"role": "user", "content": [{"text": user_text}]},
    ]

    state = session_store.get(session_id)

    # 一輪之內固定同一份系統提示，避免多次 tool 往返之間時間跳動。
    # 工作集在本輪 tool 執行中會更新，但提示已經定稿 —— 這是刻意的，
    # 本輪的 tool 結果本來就還在 messages 裡，模型看得到。
    system = [{"text": build_system_prompt(preferences, facts=state.render())}]

    pending: list[dict[str, Any]] = []

    def emit(event_type: str, **payload: Any) -> None:
        # tool 執行中產生的事件先收集，等 tool 跑完一起 yield
        pending.append(event(event_type, **payload))  # type: ignore[arg-type]

    ctx = ToolContext(actor_id=actor_id, emit=emit, backend=backend, state=state)

    assistant_text_parts: list[str] = []

    for _ in range(settings.max_iterations):
        try:
            response = await asyncio.to_thread(
                _bedrock().converse_stream,
                modelId=settings.bedrock_model_id,
                messages=messages,
                system=system,
                toolConfig=tool_config(),
                inferenceConfig={
                    "maxTokens": settings.max_tokens,
                    "temperature": settings.temperature,
                },
            )
        except Exception as exc:  # noqa: BLE001
            name = type(exc).__name__
            log.exception("converse_stream 失敗")
            if name == "ThrottlingException":
                yield event("error", message="目前太多人使用，請稍後再試")
            else:
                yield event("error", message=f"模型呼叫失敗：{name}")
            return

        blocks: list[dict[str, Any]] = []
        stop_reason = "end_turn"

        async for frame, block_result in _consume(response["stream"]):
            if frame is not None:
                yield frame
            if block_result is not None:
                blocks, stop_reason = block_result

        for block in blocks:
            if "text" in block:
                assistant_text_parts.append(block["text"])

        messages.append({"role": "assistant", "content": blocks})

        tool_uses = [b["toolUse"] for b in blocks if "toolUse" in b]
        if stop_reason != "tool_use" or not tool_uses:
            await memory.record_turn(
                actor_id, session_id, user_text, "\n".join(assistant_text_parts)
            )
            yield event("done")
            return

        results = []
        for use in tool_uses:
            yield event("tool_start", name=use["name"])

            pending.clear()
            output = await dispatch(ctx, use["name"], use["input"])
            for frame in pending:
                yield frame
            pending.clear()

            results.append(
                {
                    "toolResult": {
                        "toolUseId": use["toolUseId"],
                        "content": [{"json": output}],
                        "status": "error" if "error" in output else "success",
                    }
                }
            )

        # tool 結果一律用 user role 回餵，這是 Converse API 的規定
        messages.append({"role": "user", "content": results})

    await memory.record_turn(
        actor_id, session_id, user_text, "\n".join(assistant_text_parts)
    )
    yield event("error", message="這個需求太複雜，我處理不完，要不要換個方式說？")


async def _consume(stream: Any):
    """把 converse_stream 的事件流組回完整的 assistant content blocks。

    yield (frame, None)                  有東西要送前端
    yield (None, (blocks, stop_reason))  串流結束、組裝完成

    botocore 的 EventStream 是阻塞迭代器，而且串流佔了整輪大部分的時間，
    所以整段讀取搬到執行緒，用 queue 把結果交回 event loop。
    直接在 async generator 裡 for-loop 會把整個 server 卡住。
    """
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[tuple[str | None, tuple[list, str] | None] | None] = (
        asyncio.Queue()
    )

    def push(item):
        loop.call_soon_threadsafe(queue.put_nowait, item)

    def reader() -> None:
        try:
            for item in _iter_blocking(stream):
                push(item)
        except Exception as exc:  # noqa: BLE001
            log.exception("讀取串流失敗")
            push((event("error", message=f"串流中斷：{type(exc).__name__}"), None))
            push((None, ([], "end_turn")))
        finally:
            push(None)  # 哨兵，通知消費端結束

    task = asyncio.create_task(asyncio.to_thread(reader))
    try:
        while True:
            item = await queue.get()
            if item is None:
                break
            yield item
    finally:
        await task


def _iter_blocking(stream: Any):
    """同步解析 EventStream，產出跟 _consume 相同形狀的項目。"""
    blocks: list[dict[str, Any]] = []
    stop_reason = "end_turn"

    text_buf = ""
    tool_meta: dict[str, str] | None = None
    tool_json_buf = ""

    # 注意：迴圈變數不能叫 event —— 那會蓋掉從 schemas 匯入的 event() 函式，
    # 導致下面呼叫 event("text_delta", ...) 時炸出
    # "TypeError: 'dict' object is not callable"（部署後才會踩到的坑，
    # 因為函式改名前用的是 sse()，改名時沒注意到跟這裡的區域變數同名）。
    for stream_event in stream:
        if "contentBlockStart" in stream_event:
            start = stream_event["contentBlockStart"]["start"]
            if "toolUse" in start:
                tool_meta = {
                    "toolUseId": start["toolUse"]["toolUseId"],
                    "name": start["toolUse"]["name"],
                }
                tool_json_buf = ""

        elif "contentBlockDelta" in stream_event:
            delta = stream_event["contentBlockDelta"]["delta"]
            if "text" in delta:
                text_buf += delta["text"]
                yield event("text_delta", text=delta["text"]), None
            elif "toolUse" in delta:
                # 這裡收到的是「不完整的 JSON 字串片段」，必須累積完整才能 parse。
                # 直接對單一 delta 做 json.loads 會隨機失敗。
                tool_json_buf += delta["toolUse"]["input"]

        elif "contentBlockStop" in stream_event:
            if tool_meta is not None:
                try:
                    parsed = json.loads(tool_json_buf) if tool_json_buf.strip() else {}
                except json.JSONDecodeError:
                    log.warning("tool input 不是合法 json: %r", tool_json_buf)
                    parsed = {}
                blocks.append({"toolUse": {**tool_meta, "input": parsed}})
                tool_meta = None
                tool_json_buf = ""
            elif text_buf:
                blocks.append({"text": text_buf})
                text_buf = ""

        elif "messageStop" in stream_event:
            stop_reason = stream_event["messageStop"]["stopReason"]

        elif "metadata" in stream_event:
            usage = stream_event["metadata"].get("usage", {})
            log.info(
                "tokens in=%s out=%s",
                usage.get("inputTokens"),
                usage.get("outputTokens"),
            )

    if text_buf:
        blocks.append({"text": text_buf})

    yield None, (blocks, stop_reason)
