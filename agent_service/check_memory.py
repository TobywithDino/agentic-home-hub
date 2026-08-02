# -*- coding: utf-8 -*-
"""
直接查 AgentCore Memory 有沒有萃取出偏好，不透過對話。

比看管家回話準——回話是模糊訊號（它可能只是猜對），這裡直接看
RetrieveMemoryRecords 有沒有真的存到東西。

用法：
    python check_memory.py demo-user-0001
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys

import boto3

sys.stdout.reconfigure(encoding="utf-8")

REGION = "us-west-2"


def load_dotenv(path: pathlib.Path) -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        if m := re.match(r'^\s*([A-Za-z_]+)\s*=\s*"?(.*?)"?\s*$', line):
            os.environ.setdefault(m.group(1), m.group(2))


def find_memory_id() -> str | None:
    """bedrock-agentcore-control 沒有 ListMemories API，所以用
    `agentcore status --json` 拿部署狀態，從 memory 資源的 ARN 尾段取 id。
    """
    try:
        out = subprocess.run(
            ["agentcore", "status", "--json"],
            cwd=pathlib.Path(__file__).resolve().parent,
            capture_output=True,
            text=True,
            timeout=60,
            shell=True,
        ).stdout
    except Exception:
        return None

    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return None

    for res in data.get("resources", []):
        if res.get("resourceType") == "memory":
            arn = res.get("identifier", "")
            if "/" in arn:
                return arn.rsplit("/", 1)[-1]
    return None


def main() -> int:
    actor_id = sys.argv[1] if len(sys.argv) > 1 else "demo-user-0001"

    load_dotenv(pathlib.Path(__file__).resolve().parent.parent / ".env")

    memory_id = find_memory_id()
    if not memory_id:
        print(
            "找不到 memory id，改用 `agentcore status --json` 手動確認後"
            "把值填進本檔案的 memory_id 變數再跑一次",
            file=sys.stderr,
        )
        return 1
    print(f"memory_id = {memory_id}\n")

    data = boto3.client("bedrock-agentcore", region_name=REGION)

    print("=== 使用者偏好 (/preferences/{actorId}) ===")
    resp = data.retrieve_memory_records(
        memoryId=memory_id,
        namespace=f"/preferences/{actor_id}",
        searchCriteria={"searchQuery": "餐廳 偏好 過敏 口味", "topK": 10},
    )
    records = resp.get("memoryRecords", [])
    if not records:
        print("  (空 —— 還沒萃取出來，可能要再等一下，或還沒送出過第一輪對話)")
    for r in records:
        print(" ", json.dumps(r.get("content"), ensure_ascii=False))

    print("\n=== 對話摘要 (/summaries/{actorId}/*) ===")
    resp2 = data.retrieve_memory_records(
        memoryId=memory_id,
        namespace=f"/summaries/{actor_id}",
        namespacePath=f"/summaries/{actor_id}",
        searchCriteria={"searchQuery": "訂餐廳", "topK": 5},
    )
    for r in resp2.get("memoryRecords", []):
        print(" ", json.dumps(r.get("content"), ensure_ascii=False))
    if not resp2.get("memoryRecords"):
        print("  (空)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
