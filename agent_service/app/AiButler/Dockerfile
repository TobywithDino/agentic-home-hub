# AgentCore Runtime 跑在 Graviton，**必須** ARM64，x86 映像不會啟動。
# base image 釘到 patch 版號，避免 tag 被換掉造成供應鏈風險。
FROM --platform=linux/arm64 python:3.12.4-slim AS builder

WORKDIR /app
RUN python -m venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt


FROM --platform=linux/arm64 python:3.12.4-slim

# 非 root 執行
RUN useradd -r -u 1001 appuser

WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY app ./app

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER appuser
EXPOSE 8080

# 綁 0.0.0.0 是因為 AgentCore 從內網路由進來。
# 不要把這個 port 直接對外開放 —— 容器本身沒有驗證層。
# uvicorn 原生處理 SIGTERM，會等現有請求收尾再退出。
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
