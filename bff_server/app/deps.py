# -*- coding: utf-8 -*-
from fastapi import Request

from app.client import DbApiClient


def get_db_api_client(request: Request) -> DbApiClient:
    return request.app.state.db_api
