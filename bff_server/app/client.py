# -*- coding: utf-8 -*-
"""
封裝對隊友「DB Access API」(Database/api_server) 的 HTTP 呼叫。

這一層的 router 不直接碰 SQL/DB，只透過這個 client 呼叫 api_server，
再把結果做排序、篩選、組裝等前端需要的邏輯後回傳。
"""
import httpx
from fastapi import HTTPException

from app.config import get_settings


class DbApiClient:
    def __init__(self) -> None:
        settings = get_settings()
        self._client = httpx.AsyncClient(base_url=settings.db_api_base_url, timeout=10.0)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def request(self, method: str, path: str, **kwargs) -> httpx.Response:
        try:
            resp = await self._client.request(method, path, **kwargs)
        except httpx.RequestError as exc:
            raise HTTPException(status_code=502, detail=f"呼叫 DB API 失敗: {exc}") from exc

        if resp.status_code >= 400:
            try:
                detail = resp.json().get("detail", resp.text)
            except ValueError:
                detail = resp.text
            raise HTTPException(status_code=resp.status_code, detail=detail)
        return resp

    async def get(self, path: str, **kwargs) -> httpx.Response:
        return await self.request("GET", path, **kwargs)

    async def get_optional(self, path: str, **kwargs) -> httpx.Response | None:
        """GET 但把 404 當作「此資源不存在」而非錯誤，回傳 None。

        用於 1:0..1 的可選關聯，例如訂單評價（一筆訂單至多一筆評價，
        沒評價時 api_server 回 404 是正常狀態，不該讓整支 BFF API 因此失敗）。
        """
        try:
            resp = await self._client.get(path, **kwargs)
        except httpx.RequestError as exc:
            raise HTTPException(status_code=502, detail=f"呼叫 DB API 失敗: {exc}") from exc

        if resp.status_code == 404:
            return None
        if resp.status_code >= 400:
            try:
                detail = resp.json().get("detail", resp.text)
            except ValueError:
                detail = resp.text
            raise HTTPException(status_code=resp.status_code, detail=detail)
        return resp

    async def post(self, path: str, **kwargs) -> httpx.Response:
        return await self.request("POST", path, **kwargs)

    async def put(self, path: str, **kwargs) -> httpx.Response:
        return await self.request("PUT", path, **kwargs)

    async def patch(self, path: str, **kwargs) -> httpx.Response:
        return await self.request("PATCH", path, **kwargs)

    async def delete(self, path: str, **kwargs) -> httpx.Response:
        return await self.request("DELETE", path, **kwargs)
