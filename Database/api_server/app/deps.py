# -*- coding: utf-8 -*-
"""共用 FastAPI 依賴：分頁參數。"""
from pydantic import BaseModel, Field


class PageParams(BaseModel):
    limit: int = Field(default=20, ge=1, le=200)
    offset: int = Field(default=0, ge=0)


def page_params(limit: int = 20, offset: int = 0) -> PageParams:
    return PageParams(limit=limit, offset=offset)
