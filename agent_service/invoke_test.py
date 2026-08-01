# -*- coding: utf-8 -*-
"""
呼叫已部署的 AgentCore Runtime，把事件印出來。

不透過 `agentcore invoke` CLI，是因為它會把整段 prompt 包成
`{"prompt": "..."}` 送出，跟我們 main.py 期待的
`{"message": ..., "actor_id": ...}` 對不上。這裡直接用 boto3 送出
我們自己的 payload 結構。

用法：
    python invoke_test.py "我想吃晚餐"
    python invoke_test.py "日式的，兩個人" --session <同一個 id 延續對話>

session id 必須至少 33 字元 —— 標準 UUID（36 字元含連字號）剛好符合。
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import uuid

import boto3

sys.stdout.reconfigure(encoding="utf-8")

# 固定寫死，不要讀 AWS_REGION 環境變數 —— PowerShell session 裡很容易殘留
# 之前設過的其他值（例如裝 skill 時用過的 us-east-1），一旦殘留就會蓋掉這裡
# 想要的預設值，導致查錯區域看起來像是「runtime 不存在」。
# 對齊 agentcore/aws-targets.json 的 region。
REGION = "us-west-2"

# CDK 把 runtime 命名為 <專案名>_<runtime名>，不是單純的 runtime 名稱，
# 所以用 endswith 比對，而不是 == "AiButler"。
RUNTIME_NAME_SUFFIX = "_AiButler"


def load_dotenv(path: pathlib.Path) -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        if m := re.match(r'^\s*([A-Za-z_]+)\s*=\s*"?(.*?)"?\s*$', line):
            os.environ.setdefault(m.group(1), m.group(2))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("message")
    ap.add_argument("--session", default=None, help="延續同一段對話就傳同一個 id")
    ap.add_argument("--actor", default="demo-user-0001", help="inbr_account_id")
    args = ap.parse_args()

    root = pathlib.Path(__file__).resolve().parent
    load_dotenv(root.parent / ".env")  # repo 根目錄的臨時憑證

    session_id = args.session or f"sess-{uuid.uuid4()}-{uuid.uuid4().hex[:8]}"
    if len(session_id) < 33:
        print("session id 至少要 33 字元", file=sys.stderr)
        return 1

    ctl = boto3.client("bedrock-agentcore-control", region_name=REGION)
    runtimes = ctl.list_agent_runtimes().get("agentRuntimes", [])
    match = [
        r for r in runtimes if r.get("agentRuntimeName", "").endswith(RUNTIME_NAME_SUFFIX)
    ]
    if not match:
        names = [r.get("agentRuntimeName") for r in runtimes]
        print(f"找不到符合 *{RUNTIME_NAME_SUFFIX} 的 runtime。目前有：{names}", file=sys.stderr)
        return 1
    arn = match[0]["agentRuntimeArn"]

    data = boto3.client("bedrock-agentcore", region_name=REGION)
    resp = data.invoke_agent_runtime(
        agentRuntimeArn=arn,
        runtimeSessionId=session_id,
        contentType="application/json",
        accept="text/event-stream",
        payload=json.dumps(
            {
                "message": args.message,
                "actor_id": args.actor,
                "session_id": session_id,
            }
        ).encode("utf-8"),
    )

    print(f"session: {session_id}\n{'-' * 60}")
    for raw in resp["response"].iter_lines():
        if not raw:
            continue
        line = raw.decode("utf-8", errors="replace")
        if not line.startswith("data:"):
            continue
        body = json.loads(line[5:].strip())
        kind = body.pop("type", "?")
        if kind == "text_delta":
            print(body.get("text", ""), end="", flush=True)
        else:
            print(f"\n  <{kind}> {json.dumps(body, ensure_ascii=False)[:400]}")
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
