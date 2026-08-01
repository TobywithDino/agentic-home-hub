# -*- coding: utf-8 -*-
"""
BFF (Backend For Frontend) 層入口。

前端只呼叫這一層；這一層再呼叫 Database/api_server（隊友的 DB Access API），
中間做排序、篩選、資料組裝等前端需要的邏輯。
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.client import DbApiClient
from app.config import get_settings
from app.routers import app_api, merchant_api

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db_api = DbApiClient()
    yield
    await app.state.db_api.aclose()


app = FastAPI(
    title="智慧社區服務需求理解與媒合平台 - BFF API",
    description="包在 DB Access API (Database/api_server) 外層的中介層，"
    "負責排序/篩選/組裝等前端邏輯，前端只需呼叫這一層。",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.cors_allow_origins] if settings.cors_allow_origins != "*" else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(app_api.router)
app.include_router(merchant_api.router)


@app.get("/health", tags=["system"])
def health_check():
    return {"status": "ok"}
