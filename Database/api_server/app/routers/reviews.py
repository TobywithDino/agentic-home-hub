# -*- coding: utf-8 -*-
"""
I. 訂單評價 API
mms_order_review

設計要點（詳見 部署手冊.md 討論記錄 / API_Reference.md 本節）：
- record_id 與 mms_order_record 共用主鍵值（1:0..1 對應），新增評價時直接沿用
  對應訂單的 record_id，不產生新序列。重複評價會直接撞 PK，轉成 409。
- 只有「已完成」（order_status='80'）的訂單可以被評價。
- 新增評價成功後，同步將對應訂單的 comment_status 更新為 '02'（已評價）。
- 修改評價（PATCH /orders/{record_id}/review）依現有架構（無身分驗證中介層），
  由呼叫端於 payload 帶 inbr_account_id，路由層比對與該筆評價是否一致，
  不一致回 403。這跟 update_order 比對 service_vendor_id 是同一等級的信任模型，
  非本功能新增的安全坑，是整個 API 現有的已知限制。
- GET /services/{service_id}/reviews 為公開評價牆，無需身分驗證即可呼叫，
  回傳 PublicReviewOut（刻意排除身分/內部狀態欄位）。
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import PageParams, page_params
from app.models import MmsOrderRecord, MmsOrderReview
from app.schemas import (
    PagedResponse,
    PublicReviewOut,
    RatingSummaryOut,
    ReviewCreate,
    ReviewOut,
    ReviewUpdate,
)
from app.utils import now_utc, paginate

router = APIRouter(tags=["reviews"])

# 只有訂單狀態為「已完成」才允許評價（比對 mms_order_record.sql 對 order_status
# 欄位的註解：01系列服務訂單以外的類型皆用 80 代表已完成）。
COMPLETED_ORDER_STATUS = "80"
REVIEWED_COMMENT_STATUS = "02"


def build_review_out(obj: MmsOrderReview) -> ReviewOut:
    return ReviewOut(
        record_id=obj.record_id, order_no=obj.order_no, service_vendor_id=obj.service_vendor_id,
        service_id=obj.service_id, inbr_account_id=obj.inbr_account_id,
        overall_rating=obj.overall_rating, rating_detail=obj.rating_detail,
        review_content=obj.review_content, media=obj.media, status=obj.status,
        is_deleted=obj.is_deleted, cre_id=obj.cre_id, cre_time=obj.cre_time,
        upd_id=obj.upd_id, upd_time=obj.upd_time,
    )


def _get_order_or_404(db: Session, record_id: int) -> MmsOrderRecord:
    order = db.get(MmsOrderRecord, record_id)
    if order is None:
        raise HTTPException(status_code=404, detail="訂單不存在")
    return order


def _get_review_or_404(db: Session, record_id: int) -> MmsOrderReview:
    obj = db.get(MmsOrderReview, record_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="該訂單尚未評價")
    return obj


@router.post("/orders/{record_id}/review", response_model=ReviewOut, status_code=201)
def create_review(record_id: int, payload: ReviewCreate, db: Session = Depends(get_db)):
    """提交訂單評價。要求訂單已完成、呼叫者為該訂單的下單會員、且尚未評價過。"""
    order = _get_order_or_404(db, record_id)

    if order.order_status != COMPLETED_ORDER_STATUS:
        raise HTTPException(status_code=409, detail="訂單尚未完成，無法評價")
    if str(order.inbr_account_id) != str(payload.inbr_account_id):
        raise HTTPException(status_code=403, detail="僅該訂單的下單會員可提交評價")
    if db.get(MmsOrderReview, record_id) is not None:
        raise HTTPException(status_code=409, detail="此訂單已評價過")

    now = now_utc()
    obj = MmsOrderReview(
        record_id=record_id, order_no=order.order_no, service_vendor_id=order.service_vendor_id,
        service_id=order.service_id, inbr_account_id=payload.inbr_account_id,
        overall_rating=payload.overall_rating, rating_detail=payload.rating_detail,
        review_content=payload.review_content, media=payload.media, status="01",
        is_deleted=False, cre_id=payload.inbr_account_id, cre_time=now,
        upd_id=None, upd_time=now,
    )
    db.add(obj)
    order.comment_status = REVIEWED_COMMENT_STATUS
    order.upd_time = now
    db.commit()
    db.refresh(obj)
    return build_review_out(obj)


@router.get("/orders/{record_id}/review", response_model=ReviewOut)
def get_review(record_id: int, db: Session = Depends(get_db)):
    """查看單筆訂單的評價。404 代表該訂單尚未被評價。"""
    obj = _get_review_or_404(db, record_id)
    return build_review_out(obj)


@router.patch("/users/{inbr_account_id}/orders/{record_id}/review", response_model=ReviewOut)
def update_review(inbr_account_id: str, record_id: int, payload: ReviewUpdate, db: Session = Depends(get_db)):
    """評價者本人修改評價內容。inbr_account_id 以路徑參數帶入以比對權限
    （比照 update_order 用 service_vendor_id 作路徑參數的信任模型：依現有架構
    無身分驗證中介層，比對不一致回403，非本功能新增的安全坑）。"""
    obj = _get_review_or_404(db, record_id)
    if str(obj.inbr_account_id) != str(inbr_account_id):
        raise HTTPException(status_code=403, detail="僅評價者本人可修改此評價")

    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return build_review_out(obj)


@router.get("/users/{inbr_account_id}/reviews", response_model=PagedResponse)
def list_reviews_by_user(
    inbr_account_id: str, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    """會員查看自己送出過的所有評價。"""
    stmt = (
        select(MmsOrderReview)
        .where(MmsOrderReview.inbr_account_id == inbr_account_id, MmsOrderReview.is_deleted.is_(False))
        .order_by(MmsOrderReview.cre_time.desc())
    )
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[build_review_out(i) for i in items])


@router.get("/vendors/{service_vendor_id}/reviews", response_model=PagedResponse)
def list_reviews_by_vendor(
    service_vendor_id: int,
    service_id: int | None = None,
    db: Session = Depends(get_db),
    pp: PageParams = Depends(page_params),
):
    """供應商查看自己收到的所有評價，可選依 service_id 篩選。"""
    stmt = (
        select(MmsOrderReview)
        .where(MmsOrderReview.service_vendor_id == service_vendor_id, MmsOrderReview.is_deleted.is_(False))
        .order_by(MmsOrderReview.cre_time.desc())
    )
    if service_id is not None:
        stmt = stmt.where(MmsOrderReview.service_id == service_id)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[build_review_out(i) for i in items])


@router.get("/vendors/{service_vendor_id}/rating-summary", response_model=RatingSummaryOut)
def get_vendor_rating_summary(
    service_vendor_id: int, service_id: int | None = None, db: Session = Depends(get_db)
):
    """供應商/公開頁使用的評分聚合：評價數與平均分。可選依 service_id 細分。"""
    stmt = select(
        func.count(MmsOrderReview.record_id), func.avg(MmsOrderReview.overall_rating)
    ).where(MmsOrderReview.service_vendor_id == service_vendor_id, MmsOrderReview.is_deleted.is_(False))
    if service_id is not None:
        stmt = stmt.where(MmsOrderReview.service_id == service_id)
    count, avg_rating = db.execute(stmt).one()
    return RatingSummaryOut(
        service_vendor_id=service_vendor_id, service_id=service_id,
        review_count=count or 0, average_rating=float(avg_rating) if avg_rating is not None else None,
    )


@router.get("/services/{service_id}/reviews", response_model=PagedResponse)
def list_public_reviews_by_service(
    service_id: int, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    """公開評價牆：給潛在顧客看該服務項目的評價，無需身分驗證即可呼叫。
    回傳 PublicReviewOut，刻意排除評價者身分與訂單等內部資訊。"""
    stmt = (
        select(MmsOrderReview)
        .where(MmsOrderReview.service_id == service_id, MmsOrderReview.is_deleted.is_(False))
        .order_by(MmsOrderReview.cre_time.desc())
    )
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[PublicReviewOut.model_validate(i) for i in items])
