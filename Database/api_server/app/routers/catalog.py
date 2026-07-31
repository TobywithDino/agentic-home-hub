# -*- coding: utf-8 -*-
"""
B/C. 服務商/服務項目主檔 + 標籤 API（對應 API_Reference.md #11-29）
cms_homepage_service_vendor, cms_homepage_service, label, service_label
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import PageParams, page_params
from app.models import (
    CmsHomepageService,
    CmsHomepageServiceVendor,
    Label,
    ServiceLabel,
)
from app.schemas import (
    LabelCreate,
    LabelOut,
    LabelUpdate,
    PagedResponse,
    ServiceCreate,
    ServiceLabelOut,
    ServiceOut,
    ServiceUpdate,
    ServiceVendorCreate,
    ServiceVendorOut,
    ServiceVendorUpdate,
)
from app.utils import SYSTEM_ACTOR_ID, now_utc, paginate

router = APIRouter(tags=["catalog"])


# --- cms_homepage_service_vendor --------------------------------------------
@router.get("/service-vendors", response_model=PagedResponse)
def list_service_vendors(db: Session = Depends(get_db), pp: PageParams = Depends(page_params)):
    stmt = select(CmsHomepageServiceVendor).order_by(CmsHomepageServiceVendor.id)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[ServiceVendorOut.model_validate(i) for i in items])


@router.get("/service-vendors/{service_vendor_id}", response_model=ServiceVendorOut)
def get_service_vendor(service_vendor_id: int, db: Session = Depends(get_db)):
    obj = db.get(CmsHomepageServiceVendor, service_vendor_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="服務商不存在")
    return obj


@router.post("/service-vendors", response_model=ServiceVendorOut, status_code=201)
def create_service_vendor(payload: ServiceVendorCreate, db: Session = Depends(get_db)):
    if db.get(CmsHomepageServiceVendor, payload.id) is not None:
        raise HTTPException(status_code=409, detail="服務商ID已存在")
    obj = CmsHomepageServiceVendor(id=payload.id, name=payload.name, description=payload.description)
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.patch("/service-vendors/{service_vendor_id}", response_model=ServiceVendorOut)
def update_service_vendor(service_vendor_id: int, payload: ServiceVendorUpdate, db: Session = Depends(get_db)):
    """對應【圖2：設定商家資訊-商家屬性部分】。"""
    obj = db.get(CmsHomepageServiceVendor, service_vendor_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="服務商不存在")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(obj, field, value)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/service-vendors/{service_vendor_id}", status_code=204)
def delete_service_vendor(service_vendor_id: int, db: Session = Depends(get_db)):
    """此表無 is_deleted 欄位，故採實體刪除；若日後需保留歷史紀錄建議改加欄位。"""
    obj = db.get(CmsHomepageServiceVendor, service_vendor_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="服務商不存在")
    db.delete(obj)
    db.commit()


# --- cms_homepage_service ----------------------------------------------------
@router.get("/services", response_model=PagedResponse)
def list_services(
    service_vendor_id: int | None = None,
    type: str | None = None,
    db: Session = Depends(get_db),
    pp: PageParams = Depends(page_params),
):
    stmt = select(CmsHomepageService).order_by(CmsHomepageService.id)
    if service_vendor_id is not None:
        stmt = stmt.where(CmsHomepageService.service_vendor_id == service_vendor_id)
    if type is not None:
        stmt = stmt.where(CmsHomepageService.type == type)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[ServiceOut.model_validate(i) for i in items])


@router.get("/services/{service_id}", response_model=ServiceOut)
def get_service(service_id: int, db: Session = Depends(get_db)):
    obj = db.get(CmsHomepageService, service_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="服務項目不存在")
    return obj


@router.get("/services/{service_id}/vendors", response_model=list[ServiceVendorOut])
def get_vendors_by_service(service_id: int, db: Session = Depends(get_db)):
    """【圖1：尋找特定服務的廠商】回傳所有符合 service_id 的 service_vendor_id。"""
    service = db.get(CmsHomepageService, service_id)
    if service is None:
        raise HTTPException(status_code=404, detail="服務項目不存在")
    stmt = select(CmsHomepageServiceVendor).where(
        CmsHomepageServiceVendor.id == service.service_vendor_id
    )
    return db.execute(stmt).scalars().all()


@router.post("/services", response_model=ServiceOut, status_code=201)
def create_service(payload: ServiceCreate, db: Session = Depends(get_db)):
    if db.get(CmsHomepageService, payload.id) is not None:
        raise HTTPException(status_code=409, detail="服務項目ID已存在")
    obj = CmsHomepageService(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.patch("/services/{service_id}", response_model=ServiceOut)
def update_service(service_id: int, payload: ServiceUpdate, db: Session = Depends(get_db)):
    obj = db.get(CmsHomepageService, service_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="服務項目不存在")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(obj, field, value)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/services/{service_id}", status_code=204)
def delete_service(service_id: int, db: Session = Depends(get_db)):
    """此表無 is_deleted 欄位，採實體刪除。"""
    obj = db.get(CmsHomepageService, service_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="服務項目不存在")
    db.delete(obj)
    db.commit()


# --- label / service_label ----------------------------------------------------
@router.get("/labels", response_model=PagedResponse)
def list_labels(db: Session = Depends(get_db), pp: PageParams = Depends(page_params)):
    stmt = select(Label).where(Label.is_deleted == "0").order_by(Label.sort)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[LabelOut.model_validate(i) for i in items])


@router.get("/labels/{label_id}", response_model=LabelOut)
def get_label(label_id: int, db: Session = Depends(get_db)):
    obj = db.get(Label, label_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="標籤不存在")
    return obj


@router.post("/labels", response_model=LabelOut, status_code=201)
def create_label(payload: LabelCreate, db: Session = Depends(get_db)):
    now = now_utc()
    obj = Label(
        name=payload.name, sort=payload.sort, is_enable=payload.is_enable,
        is_deleted="0", upd_time=now, cre_time=now, upd_id=None, cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.patch("/labels/{label_id}", response_model=LabelOut)
def update_label(label_id: int, payload: LabelUpdate, db: Session = Depends(get_db)):
    obj = db.get(Label, label_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="標籤不存在")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/labels/{label_id}", status_code=204)
def delete_label(label_id: int, db: Session = Depends(get_db)):
    obj = db.get(Label, label_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="標籤不存在")
    obj.is_deleted = "1"
    obj.upd_time = now_utc()
    db.commit()


@router.get("/services/{service_id}/labels", response_model=PagedResponse)
def list_labels_of_service(
    service_id: int, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    stmt = select(ServiceLabel).where(ServiceLabel.service_id == service_id)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[ServiceLabelOut.model_validate(i) for i in items])


@router.put("/services/{service_id}/labels/{label_id}", response_model=ServiceLabelOut, status_code=201)
def link_service_label(service_id: int, label_id: int, db: Session = Depends(get_db)):
    existing = db.get(ServiceLabel, (service_id, label_id))
    if existing is not None:
        return existing
    now = now_utc()
    obj = ServiceLabel(
        service_id=service_id, label_id=label_id,
        upd_time=now, cre_time=now, upd_id=None, cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/services/{service_id}/labels/{label_id}", status_code=204)
def unlink_service_label(service_id: int, label_id: int, db: Session = Depends(get_db)):
    obj = db.get(ServiceLabel, (service_id, label_id))
    if obj is None:
        raise HTTPException(status_code=404, detail="服務-標籤關聯不存在")
    db.delete(obj)
    db.commit()
