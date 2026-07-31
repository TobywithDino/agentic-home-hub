# -*- coding: utf-8 -*-
"""
A. 縣市/行政區參考資料 API（對應 API_Reference.md #1-10）
sys_county, sys_district
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import PageParams, page_params
from app.models import SysCounty, SysDistrict
from app.schemas import (
    CountyCreate,
    CountyOut,
    CountyUpdate,
    DistrictCreate,
    DistrictOut,
    DistrictUpdate,
    PagedResponse,
)
from app.utils import SYSTEM_ACTOR_ID, now_utc, paginate

router = APIRouter(tags=["geo"])


# --- sys_county -------------------------------------------------------------
@router.get("/counties", response_model=PagedResponse)
def list_counties(db: Session = Depends(get_db), pp: PageParams = Depends(page_params)):
    stmt = select(SysCounty).where(SysCounty.is_deleted == "0").order_by(SysCounty.sort)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[CountyOut.model_validate(i) for i in items])


@router.get("/counties/{county_code}", response_model=CountyOut)
def get_county(county_code: str, db: Session = Depends(get_db)):
    obj = db.get(SysCounty, county_code)
    if obj is None:
        raise HTTPException(status_code=404, detail="縣市不存在")
    return obj


@router.post("/counties", response_model=CountyOut, status_code=201)
def create_county(payload: CountyCreate, db: Session = Depends(get_db)):
    if db.get(SysCounty, payload.code) is not None:
        raise HTTPException(status_code=409, detail="縣市代碼已存在")
    now = now_utc()
    obj = SysCounty(
        code=payload.code, name=payload.name, sort=payload.sort,
        is_deleted="0", upd_time=now, cre_time=now, upd_id=None,
        cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.patch("/counties/{county_code}", response_model=CountyOut)
def update_county(county_code: str, payload: CountyUpdate, db: Session = Depends(get_db)):
    obj = db.get(SysCounty, county_code)
    if obj is None:
        raise HTTPException(status_code=404, detail="縣市不存在")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/counties/{county_code}", status_code=204)
def delete_county(county_code: str, db: Session = Depends(get_db)):
    obj = db.get(SysCounty, county_code)
    if obj is None:
        raise HTTPException(status_code=404, detail="縣市不存在")
    obj.is_deleted = "1"
    obj.upd_time = now_utc()
    db.commit()


# --- sys_district ------------------------------------------------------------
@router.get("/counties/{county_code}/districts", response_model=PagedResponse)
def list_districts_of_county(
    county_code: str, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    stmt = (
        select(SysDistrict)
        .where(SysDistrict.county_code == county_code, SysDistrict.is_deleted == "0")
        .order_by(SysDistrict.sort)
    )
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[DistrictOut.model_validate(i) for i in items])


@router.get("/districts/{district_code}", response_model=DistrictOut)
def get_district(district_code: str, db: Session = Depends(get_db)):
    obj = db.get(SysDistrict, district_code)
    if obj is None:
        raise HTTPException(status_code=404, detail="行政區不存在")
    return obj


@router.post("/districts", response_model=DistrictOut, status_code=201)
def create_district(payload: DistrictCreate, db: Session = Depends(get_db)):
    if db.get(SysDistrict, payload.code) is not None:
        raise HTTPException(status_code=409, detail="行政區代碼已存在")
    now = now_utc()
    obj = SysDistrict(
        code=payload.code, county_code=payload.county_code, name=payload.name,
        name_with_county=payload.name_with_county, zip=payload.zip, sort=payload.sort,
        is_deleted="0", upd_time=now, cre_time=now, upd_id=None,
        cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.patch("/districts/{district_code}", response_model=DistrictOut)
def update_district(district_code: str, payload: DistrictUpdate, db: Session = Depends(get_db)):
    obj = db.get(SysDistrict, district_code)
    if obj is None:
        raise HTTPException(status_code=404, detail="行政區不存在")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/districts/{district_code}", status_code=204)
def delete_district(district_code: str, db: Session = Depends(get_db)):
    obj = db.get(SysDistrict, district_code)
    if obj is None:
        raise HTTPException(status_code=404, detail="行政區不存在")
    obj.is_deleted = "1"
    obj.upd_time = now_utc()
    db.commit()
