# -*- coding: utf-8 -*-
"""
H. 訂單 API（對應 API_Reference.md #71-76）
mms_order_record

含【圖1：查看訂單】的拼接邏輯：
  去 feedback_record 抓 status 未處理的 feedbacks
  去 order_record 抓 order
  feedbacks + orders 拼在一起回傳
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.crypto import decrypt_pii, encrypt_pii, sha256_hash
from app.database import get_db
from app.deps import PageParams, page_params
from app.models import CmsHomepageService, MmsOrderRecord, PmsFormFeedback
from app.routers.feedbacks import build_feedback_out
from app.schemas import OrderCreate, OrderOut, OrderSummaryOut, OrderUpdate, PagedResponse
from app.utils import now_utc, paginate

router = APIRouter(tags=["orders"])

# 諮詢單「未處理」的 status 值。schema 註解僅說明 status 為「回饋狀態」，
# 未明確定義各代碼意義；比對 mms_order_record.order_status 慣例('01'系列表示待處理階段)，
# 這裡採用 status != '1'（已處理）視為未處理，'0' 為建立feedback時的預設初始值。
UNPROCESSED_FEEDBACK_STATUS = "0"


def build_order_out(obj: MmsOrderRecord) -> OrderOut:
    return OrderOut(
        record_id=obj.record_id, order_no=obj.order_no, service_vendor_id=obj.service_vendor_id,
        service_id=obj.service_id, platform_code=obj.platform_code, inbr_account_id=obj.inbr_account_id,
        member_name=decrypt_pii(obj.member_name), member_name_hash=obj.member_name_hash,
        member_phone=decrypt_pii(obj.member_phone), member_phone_hash=obj.member_phone_hash,
        member_email=decrypt_pii(obj.member_email), member_email_hash=obj.member_email_hash,
        order_type=obj.order_type, order_status=obj.order_status, order_time=obj.order_time,
        deposit_time=obj.deposit_time, confirm_time=obj.confirm_time, service_time=obj.service_time,
        complete_time=obj.complete_time, cancel_time=obj.cancel_time,
        deposit_amount=float(obj.deposit_amount), original_amount=float(obj.original_amount),
        discount_amount=float(obj.discount_amount), shipping_fee_amount=float(obj.shipping_fee_amount),
        final_amount=float(obj.final_amount), refund_amount=float(obj.refund_amount),
        order_points=float(obj.order_points), used_points=float(obj.used_points),
        refund_points=float(obj.refund_points), earn_points=float(obj.earn_points),
        point_status=obj.point_status, point_grant_time=obj.point_grant_time,
        vendor_data=obj.vendor_data, order_items=obj.order_items, remark=obj.remark,
        cancel_reason=obj.cancel_reason, refund_reason=obj.refund_reason,
        source_file=obj.source_file, import_batch=obj.import_batch,
        quote_approved_by=obj.quote_approved_by, quote_approved_time=obj.quote_approved_time,
        quote_no=obj.quote_no, comment_status=obj.comment_status, is_deleted=obj.is_deleted,
        cre_id=obj.cre_id, cre_time=obj.cre_time, upd_id=obj.upd_id, upd_time=obj.upd_time,
    )


@router.post("/orders", response_model=OrderOut, status_code=201)
def create_order(payload: OrderCreate, db: Session = Depends(get_db)):
    """【圖2：建立order】新增至 mm_order_record。"""
    existing = db.execute(
        select(MmsOrderRecord).where(
            MmsOrderRecord.order_no == payload.order_no,
            MmsOrderRecord.service_id == payload.service_id,
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=409, detail="order_no + service_id 組合已存在(UNIQUE KEY衝突)")

    now = now_utc()
    obj = MmsOrderRecord(
        order_no=payload.order_no, service_vendor_id=payload.service_vendor_id,
        service_id=payload.service_id, platform_code=payload.platform_code,
        inbr_account_id=payload.inbr_account_id,
        member_name=encrypt_pii(payload.member_name), member_name_hash=sha256_hash(payload.member_name),
        member_phone=encrypt_pii(payload.member_phone), member_phone_hash=sha256_hash(payload.member_phone),
        member_email=encrypt_pii(payload.member_email), member_email_hash=sha256_hash(payload.member_email),
        order_type=payload.order_type, order_status=payload.order_status, order_time=payload.order_time,
        deposit_amount=payload.deposit_amount, original_amount=payload.original_amount,
        discount_amount=payload.discount_amount, shipping_fee_amount=payload.shipping_fee_amount,
        final_amount=payload.final_amount, refund_amount=0, order_points=0, used_points=0,
        refund_points=0, earn_points=0, point_status="01", point_grant_time=None,
        vendor_data=payload.vendor_data, order_items=payload.order_items, remark=payload.remark,
        cancel_reason=None, refund_reason=None, source_file=payload.source_file,
        import_batch=payload.import_batch, quote_approved_by=None, quote_approved_time=None,
        quote_no=None, comment_status="00", is_deleted=False,
        cre_id=payload.cre_id, cre_time=now, upd_id=payload.upd_id, upd_time=now,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return build_order_out(obj)


@router.get("/orders/{record_id}", response_model=OrderOut)
def get_order(record_id: int, db: Session = Depends(get_db)):
    obj = db.get(MmsOrderRecord, record_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="訂單不存在")
    return build_order_out(obj)


@router.get("/vendors/{service_vendor_id}/orders", response_model=PagedResponse)
def list_orders_by_vendor(
    service_vendor_id: int,
    order_status: str | None = None,
    db: Session = Depends(get_db),
    pp: PageParams = Depends(page_params),
):
    """【圖2：查看order】根據 service_vendor_id 抓取 orders。"""
    stmt = (
        select(MmsOrderRecord)
        .where(MmsOrderRecord.service_vendor_id == service_vendor_id, MmsOrderRecord.is_deleted.is_(False))
        .order_by(MmsOrderRecord.order_time.desc())
    )
    if order_status is not None:
        stmt = stmt.where(MmsOrderRecord.order_status == order_status)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[build_order_out(i) for i in items])


@router.patch("/vendors/{service_vendor_id}/orders/{record_id}", response_model=OrderOut)
def update_order(service_vendor_id: int, record_id: int, payload: OrderUpdate, db: Session = Depends(get_db)):
    """【圖2：更新order】根據 service_vendor_id 更新單筆特定訂單。"""
    obj = db.get(MmsOrderRecord, record_id)
    if obj is None or obj.service_vendor_id != service_vendor_id:
        raise HTTPException(status_code=404, detail="訂單不存在")
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return build_order_out(obj)


@router.get("/users/{inbr_account_id}/orders", response_model=PagedResponse)
def list_orders_by_user(
    inbr_account_id: str, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    stmt = (
        select(MmsOrderRecord)
        .where(MmsOrderRecord.inbr_account_id == inbr_account_id, MmsOrderRecord.is_deleted.is_(False))
        .order_by(MmsOrderRecord.order_time.desc())
    )
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[build_order_out(i) for i in items])


@router.get("/users/{inbr_account_id}/order-summary", response_model=OrderSummaryOut)
def get_order_summary(inbr_account_id: str, db: Session = Depends(get_db)):
    """【圖1：查看訂單】
    去 feedback_record 抓 status 未處理的 feedbacks
    去 order_record 抓 order
    feedbacks + orders 拼在一起回傳
    """
    feedbacks = db.execute(
        select(PmsFormFeedback)
        .where(
            PmsFormFeedback.inbr_account_id == inbr_account_id,
            PmsFormFeedback.status == UNPROCESSED_FEEDBACK_STATUS,
        )
        .order_by(PmsFormFeedback.cre_time.desc())
    ).scalars().all()

    orders = db.execute(
        select(MmsOrderRecord)
        .where(MmsOrderRecord.inbr_account_id == inbr_account_id, MmsOrderRecord.is_deleted.is_(False))
        .order_by(MmsOrderRecord.order_time.desc())
    ).scalars().all()

    return OrderSummaryOut(
        feedbacks=[build_feedback_out(f) for f in feedbacks],
        orders=[build_order_out(o) for o in orders],
    )
