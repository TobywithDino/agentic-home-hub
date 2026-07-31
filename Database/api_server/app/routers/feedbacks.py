# -*- coding: utf-8 -*-
"""
G. 諮詢單回饋 API（對應 API_Reference.md #66-70）
pms_form_feedback
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.crypto import decrypt_pii, encrypt_pii, sha256_hash
from app.database import get_db
from app.deps import PageParams, page_params
from app.models import PmsFormFeedback
from app.schemas import FeedbackCreate, FeedbackOut, FeedbackStatusUpdate, PagedResponse
from app.utils import now_utc, paginate

router = APIRouter(tags=["feedbacks"])


def build_feedback_out(obj: PmsFormFeedback) -> FeedbackOut:
    return FeedbackOut(
        feedback_no=obj.feedback_no, service_id=obj.service_id, platform_code=obj.platform_code,
        form_id=obj.form_id, feedback_content=obj.feedback_content, form_type=obj.form_type,
        is_read=obj.is_read, status=obj.status,
        contact_name=decrypt_pii(obj.contact_name), contact_name_hash=obj.contact_name_hash,
        contact_mobile=decrypt_pii(obj.contact_mobile), contact_mobile_hash=obj.contact_mobile_hash,
        contact_landline=decrypt_pii(obj.contact_landline), contact_landline_hash=obj.contact_landline_hash,
        contact_email=decrypt_pii(obj.contact_email), contact_email_hash=obj.contact_email_hash,
        preferred_contact_time=obj.preferred_contact_time,
        contact_address_county=obj.contact_address_county,
        contact_address_district=obj.contact_address_district,
        contact_address_detail=decrypt_pii(obj.contact_address_detail),
        contact_address_detail_hash=obj.contact_address_detail_hash,
        description=obj.description, inbr_account_id=obj.inbr_account_id,
        cre_time=obj.cre_time, upd_id=obj.upd_id, upd_time=obj.upd_time,
    )


@router.post("/feedbacks", response_model=FeedbackOut, status_code=201)
def create_feedback(payload: FeedbackCreate, db: Session = Depends(get_db)):
    """【圖1：建立feedback】判斷feedback類型內容，更新DB。

    feedback_content 的內容結構由前端依 pms_form_topic.type 組裝完成後傳入，
    本端點負責的是「儲存」，不重複驗證每個題目型別的內容格式（該驗證屬於表單引擎邏輯，
    非資料存取層職責）。
    """
    if db.get(PmsFormFeedback, payload.feedback_no) is not None:
        raise HTTPException(status_code=409, detail="回饋單號已存在")
    now = now_utc()
    obj = PmsFormFeedback(
        feedback_no=payload.feedback_no, service_id=payload.service_id,
        platform_code=payload.platform_code, form_id=payload.form_id,
        feedback_content=payload.feedback_content, form_type=payload.form_type,
        is_read="0", status="0",
        contact_name=encrypt_pii(payload.contact_name), contact_name_hash=sha256_hash(payload.contact_name),
        contact_mobile=encrypt_pii(payload.contact_mobile), contact_mobile_hash=sha256_hash(payload.contact_mobile),
        contact_landline=encrypt_pii(payload.contact_landline),
        contact_landline_hash=sha256_hash(payload.contact_landline),
        contact_email=encrypt_pii(payload.contact_email), contact_email_hash=sha256_hash(payload.contact_email),
        preferred_contact_time=payload.preferred_contact_time,
        contact_address_county=payload.contact_address_county,
        contact_address_district=payload.contact_address_district,
        contact_address_detail=encrypt_pii(payload.contact_address_detail),
        contact_address_detail_hash=sha256_hash(payload.contact_address_detail),
        description=payload.description, inbr_account_id=payload.inbr_account_id,
        cre_time=now, upd_id=None, upd_time=now,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return build_feedback_out(obj)


@router.get("/feedbacks/{feedback_no}", response_model=FeedbackOut)
def get_feedback(feedback_no: str, db: Session = Depends(get_db)):
    obj = db.get(PmsFormFeedback, feedback_no)
    if obj is None:
        raise HTTPException(status_code=404, detail="回饋單不存在")
    return build_feedback_out(obj)


@router.get("/vendors/{service_vendor_id}/feedbacks", response_model=PagedResponse)
def list_feedbacks_by_vendor(
    service_vendor_id: int,
    status: str | None = None,
    db: Session = Depends(get_db),
    pp: PageParams = Depends(page_params),
):
    """【圖2：查看feedback】根據 service_vendor_id 抓取 feedbacks。

    pms_form_feedback 表本身沒有 service_vendor_id 欄位（只有 service_id），
    因此透過 cms_homepage_service.service_vendor_id 間接篩選，
    對應圖面「後端 server 會做的事」中隱含的跨表查詢邏輯。
    """
    from app.models import CmsHomepageService

    service_ids = db.execute(
        select(CmsHomepageService.id).where(CmsHomepageService.service_vendor_id == service_vendor_id)
    ).scalars().all()
    if not service_ids:
        return PagedResponse(total=0, limit=pp.limit, offset=pp.offset, items=[])

    stmt = (
        select(PmsFormFeedback)
        .where(PmsFormFeedback.service_id.in_(service_ids))
        .order_by(PmsFormFeedback.cre_time.desc())
    )
    if status is not None:
        stmt = stmt.where(PmsFormFeedback.status == status)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[build_feedback_out(i) for i in items])


@router.patch("/feedbacks/{feedback_no}/status", response_model=FeedbackOut)
def update_feedback_status(feedback_no: str, payload: FeedbackStatusUpdate, db: Session = Depends(get_db)):
    """【圖2：更新feedback status】改 feedback 的 is_read 或 status。"""
    obj = db.get(PmsFormFeedback, feedback_no)
    if obj is None:
        raise HTTPException(status_code=404, detail="回饋單不存在")
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return build_feedback_out(obj)


@router.get("/users/{inbr_account_id}/feedbacks", response_model=PagedResponse)
def list_feedbacks_by_user(
    inbr_account_id: str, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    stmt = (
        select(PmsFormFeedback)
        .where(PmsFormFeedback.inbr_account_id == inbr_account_id)
        .order_by(PmsFormFeedback.cre_time.desc())
    )
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[build_feedback_out(i) for i in items])
