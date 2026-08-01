# -*- coding: utf-8 -*-
"""
B/C. 服務商/服務項目主檔 + 標籤 API（對應 API_Reference.md #11-29）
cms_homepage_service_vendor, cms_homepage_service, label, service_label
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_, select
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
def list_labels(
    service_type: str | None = None, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    """標籤列表。不帶 service_type 回傳全部啟用中標籤；帶 service_type 時
    回傳「通用標籤(service_type IS NULL) + 該類型專屬標籤」，
    供商家後台編輯服務項目時只顯示跟該服務類型相關的標籤可勾選。"""
    stmt = select(Label).where(Label.is_deleted == "0").order_by(Label.sort)
    if service_type is not None:
        stmt = stmt.where(or_(Label.service_type == service_type, Label.service_type.is_(None)))
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[LabelOut.model_validate(i) for i in items])


@router.get("/labels/{label_id}", response_model=LabelOut)
def get_label(label_id: int, db: Session = Depends(get_db)):
    obj = db.get(Label, label_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="標籤不存在")
    return obj


def _find_duplicate_label(db: Session, name: str, service_type: str | None, exclude_id: int | None = None):
    """依標籤唯一性規則查詢是否已存在同名標籤：
    - service_type 有值：僅在同一 service_type 內查重複（對應 UNIQUE(service_type, name)）
    - service_type 為 None（通用標籤）：全域查重複（對應 partial unique index）
    exclude_id 用於 PATCH 排除自己這筆。"""
    if service_type is not None:
        stmt = select(Label).where(Label.service_type == service_type, Label.name == name)
    else:
        stmt = select(Label).where(Label.service_type.is_(None), Label.name == name)
    if exclude_id is not None:
        stmt = stmt.where(Label.id != exclude_id)
    return db.execute(stmt).scalar_one_or_none()


@router.post("/labels", response_model=LabelOut, status_code=201)
def create_label(payload: LabelCreate, db: Session = Depends(get_db)):
    if _find_duplicate_label(db, payload.name, payload.service_type) is not None:
        detail = "此服務類型下已存在同名標籤" if payload.service_type is not None else "標籤名稱已存在"
        raise HTTPException(status_code=409, detail=detail)

    now = now_utc()
    obj = Label(
        name=payload.name, sort=payload.sort, is_enable=payload.is_enable,
        service_type=payload.service_type,
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

    data = payload.model_dump(exclude_unset=True)
    # 若這次異動涉及 name 或 service_type，需重新檢查唯一性（排除自己這筆）
    if "name" in data or "service_type" in data:
        new_name = data.get("name", obj.name)
        new_service_type = data.get("service_type", obj.service_type)
        if _find_duplicate_label(db, new_name, new_service_type, exclude_id=label_id) is not None:
            detail = "此服務類型下已存在同名標籤" if new_service_type is not None else "標籤名稱已存在"
            raise HTTPException(status_code=409, detail=detail)

    for field, value in data.items():
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
