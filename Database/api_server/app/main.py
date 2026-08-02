# -*- coding: utf-8 -*-
"""
FastAPI 應用程式入口。

安全性提醒（務必在正式串接前處理）：
1. 目前所有端點皆無身分驗證中介層。/auth/user/login、/auth/vendor/login
   只做帳密核對後回傳識別碼，並未簽發 JWT/Session token。任何知道
   inbr_account_id 或 service_vendor_id 的人都能呼叫其他端點讀寫該身分的資料。
   正式環境上線前必須加上驗證機制（例如 OAuth2/JWT），並在各業務端點
   檢查「呼叫者是否有權操作該資源」。
2. CORS 預設為允許所有來源（開發用），正式環境請改為白名單。
3. PII 加解密金鑰（PII_ENCRYPTION_KEY_B64）未設定時，加密欄位一律回傳 null，
   這是刻意的安全預設值（避免產生無法復原的假密文），正式環境務必設定金鑰。
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.routers import accounts, catalog, feedbacks, forms, geo, orders, reviews, summaries

settings = get_settings()

app = FastAPI(
    title="智慧社區服務需求理解與媒合平台 - DB Access API",
    description="供主要專案程式使用的資料庫存取 API server",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.cors_allow_origins] if settings.cors_allow_origins != "*" else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(geo.router)
app.include_router(catalog.router)
app.include_router(accounts.router)
app.include_router(forms.router)
app.include_router(feedbacks.router)
app.include_router(orders.router)
app.include_router(reviews.router)
app.include_router(summaries.router)


@app.get("/health", tags=["system"])
def health_check():
    return {"status": "ok"}
