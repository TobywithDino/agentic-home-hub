# -*- coding: utf-8 -*-
"""
Session 工作集。

為什麼需要這個：memory.load_history 只還原 USER/ASSISTANT 的純文字，
不還原 toolUse/toolResult（Converse API 要求 toolResult 必須配對同一輪的
toolUse，跨請求還原很容易組出不合法的 messages）。

結果是模型在第二輪之後不知道 vendor_id / form_id / topic_id 是多少，
只能憑印象猜 —— 實測會傳出 vendor_id=2、service_id=2002 這種幻覺值。

所以把「已經查到的實體」單獨記下來，每輪渲染成一小段文字放進系統提示。
比還原完整 tool 歷史便宜得多，也不會有 messages 結構問題。

存在 process 記憶體，AgentCore Runtime 實例被回收就沒了。回收後模型會
重新呼叫 find_service_vendors 補齊，只是多花一次往返，不會出錯。
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any


@dataclass
class SessionState:
    vendors: list[dict[str, Any]] = field(default_factory=list)
    selected_vendor_id: int | None = None
    selected_service_id: int | None = None
    form: dict[str, Any] | None = None
    touched_at: float = field(default_factory=time.time)

    def remember_vendors(self, service_type: str, vendors: list[dict[str, Any]]) -> None:
        self.vendors = [
            {
                "service_type": service_type,
                "vendor_id": int(v["vendor_id"]),
                "name": v["name"],
                "service_ids": [int(s["service_id"]) for s in v.get("services", [])],
            }
            for v in vendors
        ]
        self.touched_at = time.time()

    def remember_form(
        self, service_id: int, form_id: int, topics: list[dict[str, Any]]
    ) -> None:
        # 表單是掛在服務項目上的（cms_homepage_service.form_id），
        # 所以工作集記的是 service_id。順手回推 vendor_id 供提示顯示用。
        self.selected_service_id = service_id
        self.selected_vendor_id = next(
            (
                v["vendor_id"]
                for v in self.vendors
                if service_id in v.get("service_ids", [])
            ),
            self.selected_vendor_id,
        )
        self.form = {
            "service_id": service_id,
            "form_id": form_id,
            "topics": [
                {
                    "topic_id": t["topic_id"],
                    "title": t["title"],
                    "type": t["type"],
                    "required": t["is_required"],
                }
                for t in topics
            ],
        }
        self.touched_at = time.time()

    def render(self) -> str:
        """渲染成系統提示用的文字。沒東西就回空字串，不要塞無意義的區塊。"""
        if not self.vendors and not self.form:
            return ""

        lines: list[str] = []
        if self.vendors:
            lines.append("已查到的服務商（傳給 tool 時用這裡的數字，不要用序號）：")
            for v in self.vendors:
                sids = "、".join(str(i) for i in v["service_ids"]) or "無"
                lines.append(
                    f"- {v['name']}：vendor_id={v['vendor_id']}，service_id={sids}"
                )

        if self.form:
            f = self.form
            vendor_hint = (
                f"，vendor_id={self.selected_vendor_id}"
                if self.selected_vendor_id is not None
                else ""
            )
            lines.append(
                f"\n已取得的表單：service_id={f['service_id']}，"
                f"form_id={f['form_id']}{vendor_hint}"
            )
            lines.append("題目（topic_id 照抄，不要用題號）：")
            for t in f["topics"]:
                mark = "必填" if t["required"] else "選填"
                lines.append(
                    f"- topic_id={t['topic_id']}：{t['title']}（{mark}，型別 {t['type']}）"
                )

        return "\n## 本次對話已確認的資料\n" + "\n".join(lines) + "\n"


class SessionStore:
    """以 session_id 為 key 的工作集。超過 TTL 就丟掉，避免長跑 process 記憶體長大。"""

    def __init__(self, ttl_seconds: int = 3600) -> None:
        self._items: dict[str, SessionState] = {}
        self._ttl = ttl_seconds

    def get(self, session_id: str) -> SessionState:
        self._purge()
        state = self._items.get(session_id)
        if state is None:
            state = SessionState()
            self._items[session_id] = state
        return state

    def _purge(self) -> None:
        cutoff = time.time() - self._ttl
        for key in [k for k, v in self._items.items() if v.touched_at < cutoff]:
            self._items.pop(key, None)


session_store = SessionStore()
