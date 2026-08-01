# -*- coding: utf-8 -*-
"""
I2. 評價AI摘要 API（新增功能，圖面未涵蓋）
mms_review_summary_service, mms_review_summary_vendor

設計要點（詳見 API_Reference.md 本節 / mms_review_summary.sql 欄位註解）：
- 本 server 只負責「讀取摘要」與「寫入/更新摘要結果」，不呼叫 LLM。實際呼叫
  AI 模型產生摘要內容的流程屬於更上層服務（例如 bff_server 或獨立排程），
  這裡的 PUT 端點是給該流程寫回生成結果用。
- 兩張表皆為「覆寫式快取」：同一個 service_id / service_vendor_id 只保留
  最新1筆，PUT 為完整覆寫語意（key 不存在則新建回201，存在則覆蓋回200），
  不留歷史版本。
- PATCH .../status 只更新生成狀態，若目標 key 尚無記錄會自動建立一筆殼記錄
  （其餘欄位皆為 null），讓生成流程可以「先標記01生成中」再非同步寫入完整
  內容，不用等 LLM 回應才第一次寫資料。
- GET 回應多附帶計算欄位 is_stale：即時比對 mms_order_review 目前的
  COUNT(*)/MAX(cre_time) 是否超過本筆摘要記錄的 source_review_count/
  latest_review_cre_time，True 代表有新評價尚未納入摘要，呼叫端可據此決定
  是否觸發重新生成。
- 因無身分驗證中介層，cre_id/upd_id 暫填 SYSTEM_ACTOR_ID（比照 catalog.py
  等管理端 CRUD 的既有慣例），無法追蹤是哪個服務觸發的生成。
- DELETE 為軟刪除（is_deleted=true），之後 GET 視為 404，但不清空欄位內容。
"""
from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import PageParams, page_params
from app.models import (
    CmsHomepageService,
    CmsHomepageServiceVendor,
    MmsOrderReview,
    MmsReviewSummaryService,
    MmsReviewSummaryVendor,
)
from app.schemas import (
    PagedResponse,
    ReviewSummaryStatusUpdate,
    ServiceReviewSummaryOut,
    ServiceReviewSummaryUpsert,
    VendorReviewSummaryOut,
    VendorReviewSummaryUpsert,
)
from app.utils import SYSTEM_ACTOR_ID, now_utc, paginate

router = APIRouter(tags=["review-summaries"])


# ---------------------------------------------------------------------------
# 共用：is_stale 計算
# ---------------------------------------------------------------------------
def _is_stale(current_count: int, current_max_time, stored_count: int, stored_max_time) -> bool:
    """比對即時聚合值與摘要記錄存的快取值，判斷是否有新評價尚未納入摘要。"""
    if current_count != stored_count:
        return True
    if current_max_time is not None:
        if stored_max_time is None or current_max_time > stored_max_time:
            return True
    return False


def _service_review_aggregate(db: Session, service_id: int):
    stmt = select(
        func.count(MmsOrderReview.record_id), func.max(MmsOrderReview.cre_time)
    ).where(MmsOrderReview.service_id == service_id, MmsOrderReview.is_deleted.is_(False))
    count, max_time = db.execute(stmt).one()
    return count or 0, max_time


def _vendor_review_aggregate(db: Session, service_vendor_id: int):
    stmt = select(
        func.count(MmsOrderReview.record_id), func.max(MmsOrderReview.cre_time)
    ).where(MmsOrderReview.service_vendor_id == service_vendor_id, MmsOrderReview.is_deleted.is_(False))
    count, max_time = db.execute(stmt).one()
    return count or 0, max_time


def build_service_summary_out(obj: MmsReviewSummaryService, db: Session) -> ServiceReviewSummaryOut:
    current_count, current_max_time = _service_review_aggregate(db, obj.service_id)
    stale = _is_stale(current_count, current_max_time, obj.source_review_count, obj.latest_review_cre_time)
    return ServiceReviewSummaryOut(
        service_id=obj.service_id, service_vendor_id=obj.service_vendor_id,
        service_name=obj.service_name,
        summary_content=obj.summary_content, summary_highlights=obj.summary_highlights,
        sentiment_stats=obj.sentiment_stats, source_review_count=obj.source_review_count,
        source_avg_rating=float(obj.source_avg_rating) if obj.source_avg_rating is not None else None,
        latest_review_cre_time=obj.latest_review_cre_time, ai_model=obj.ai_model,
        generate_status=obj.generate_status, generate_time=obj.generate_time,
        error_message=obj.error_message, is_deleted=obj.is_deleted, cre_id=obj.cre_id,
        cre_time=obj.cre_time, upd_id=obj.upd_id, upd_time=obj.upd_time, is_stale=stale,
    )


def build_vendor_summary_out(obj: MmsReviewSummaryVendor, db: Session) -> VendorReviewSummaryOut:
    current_count, current_max_time = _vendor_review_aggregate(db, obj.service_vendor_id)
    stale = _is_stale(current_count, current_max_time, obj.source_review_count, obj.latest_review_cre_time)
    return VendorReviewSummaryOut(
        service_vendor_id=obj.service_vendor_id, vendor_name=obj.vendor_name,
        summary_content=obj.summary_content,
        summary_highlights=obj.summary_highlights, sentiment_stats=obj.sentiment_stats,
        service_breakdown=obj.service_breakdown, source_review_count=obj.source_review_count,
        source_avg_rating=float(obj.source_avg_rating) if obj.source_avg_rating is not None else None,
        latest_review_cre_time=obj.latest_review_cre_time, ai_model=obj.ai_model,
        generate_status=obj.generate_status, generate_time=obj.generate_time,
        error_message=obj.error_message, is_deleted=obj.is_deleted, cre_id=obj.cre_id,
        cre_time=obj.cre_time, upd_id=obj.upd_id, upd_time=obj.upd_time, is_stale=stale,
    )


def _get_service_summary_or_404(db: Session, service_id: int) -> MmsReviewSummaryService:
    obj = db.get(MmsReviewSummaryService, service_id)
    if obj is None or obj.is_deleted:
        raise HTTPException(status_code=404, detail="該服務項目尚無評價AI摘要")
    return obj


def _get_vendor_summary_or_404(db: Session, service_vendor_id: int) -> MmsReviewSummaryVendor:
    obj = db.get(MmsReviewSummaryVendor, service_vendor_id)
    if obj is None or obj.is_deleted:
        raise HTTPException(status_code=404, detail="該供應商尚無整合評價AI摘要")
    return obj


# ---------------------------------------------------------------------------
# mms_review_summary_service
# ---------------------------------------------------------------------------
@router.get("/services/{service_id}/review-summary", response_model=ServiceReviewSummaryOut)
def get_service_review_summary(service_id: int, db: Session = Depends(get_db)):
    """查看服務項目的評價AI摘要，使用者/供應商共用同一份內容。
    404 代表尚未生成過摘要。"""
    obj = _get_service_summary_or_404(db, service_id)
    return build_service_summary_out(obj, db)


@router.put("/services/{service_id}/review-summary", response_model=ServiceReviewSummaryOut)
def upsert_service_review_summary(
    service_id: int, payload: ServiceReviewSummaryUpsert, response: Response, db: Session = Depends(get_db)
):
    """完整覆寫服務項目摘要，供AI生成流程寫回結果。key不存在則新建(201)，
    存在則整包覆蓋(200)。generate_time 由伺服器端填入當前時間。"""
    now = now_utc()
    obj = db.get(MmsReviewSummaryService, service_id)
    if obj is None:
        obj = MmsReviewSummaryService(
            service_id=service_id, service_vendor_id=payload.service_vendor_id,
            service_name=payload.service_name,
            summary_content=payload.summary_content, summary_highlights=payload.summary_highlights,
            sentiment_stats=payload.sentiment_stats, source_review_count=payload.source_review_count,
            source_avg_rating=payload.source_avg_rating, latest_review_cre_time=payload.latest_review_cre_time,
            ai_model=payload.ai_model, generate_status=payload.generate_status,
            generate_time=now, error_message=payload.error_message, is_deleted=False,
            cre_id=SYSTEM_ACTOR_ID, cre_time=now, upd_id=None, upd_time=now,
        )
        db.add(obj)
        response.status_code = 201
    else:
        obj.service_vendor_id = payload.service_vendor_id
        obj.service_name = payload.service_name
        obj.summary_content = payload.summary_content
        obj.summary_highlights = payload.summary_highlights
        obj.sentiment_stats = payload.sentiment_stats
        obj.source_review_count = payload.source_review_count
        obj.source_avg_rating = payload.source_avg_rating
        obj.latest_review_cre_time = payload.latest_review_cre_time
        obj.ai_model = payload.ai_model
        obj.generate_status = payload.generate_status
        obj.generate_time = now
        obj.error_message = payload.error_message
        obj.is_deleted = False
        obj.upd_id = SYSTEM_ACTOR_ID
        obj.upd_time = now
        response.status_code = 200
    db.commit()
    db.refresh(obj)
    return build_service_summary_out(obj, db)


@router.patch("/services/{service_id}/review-summary/status", response_model=ServiceReviewSummaryOut)
def update_service_review_summary_status(
    service_id: int, payload: ReviewSummaryStatusUpdate, db: Session = Depends(get_db)
):
    """僅更新生成狀態。目標key尚無記錄時自動建立殼記錄（其餘欄位皆為null），
    讓生成流程能在呼叫LLM前先標記01生成中，不用等LLM回應才第一次寫資料。
    殼記錄的 service_vendor_id/service_name 由 cms_homepage_service 查得（值相等關聯，非FK）。"""
    now = now_utc()
    obj = db.get(MmsReviewSummaryService, service_id)
    if obj is None:
        service = db.get(CmsHomepageService, service_id)
        if service is None:
            raise HTTPException(status_code=404, detail="服務項目不存在，無法建立摘要殼記錄")
        obj = MmsReviewSummaryService(
            service_id=service_id, service_vendor_id=service.service_vendor_id,
            service_name=service.name,
            summary_content=None, summary_highlights=None, sentiment_stats=None,
            source_review_count=0, source_avg_rating=None, latest_review_cre_time=None,
            ai_model=None, generate_status=payload.generate_status, generate_time=None,
            error_message=payload.error_message, is_deleted=False,
            cre_id=SYSTEM_ACTOR_ID, cre_time=now, upd_id=None, upd_time=now,
        )
        db.add(obj)
    else:
        obj.generate_status = payload.generate_status
        obj.error_message = payload.error_message
        obj.upd_id = SYSTEM_ACTOR_ID
        obj.upd_time = now
    db.commit()
    db.refresh(obj)
    return build_service_summary_out(obj, db)


@router.delete("/services/{service_id}/review-summary", status_code=204)
def delete_service_review_summary(service_id: int, db: Session = Depends(get_db)):
    """軟刪除摘要，之後GET視為404，但不清空欄位內容。"""
    obj = db.get(MmsReviewSummaryService, service_id)
    if obj is None or obj.is_deleted:
        raise HTTPException(status_code=404, detail="該服務項目尚無評價AI摘要")
    obj.is_deleted = True
    obj.upd_id = SYSTEM_ACTOR_ID
    obj.upd_time = now_utc()
    db.commit()


# ---------------------------------------------------------------------------
# mms_review_summary_vendor
# ---------------------------------------------------------------------------
@router.get("/vendors/{service_vendor_id}/review-summaries", response_model=PagedResponse)
def list_service_review_summaries_by_vendor(
    service_vendor_id: int, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    """供應商查看名下所有服務項目的評價AI摘要清單(分頁)。"""
    stmt = (
        select(MmsReviewSummaryService)
        .where(
            MmsReviewSummaryService.service_vendor_id == service_vendor_id,
            MmsReviewSummaryService.is_deleted.is_(False),
        )
        .order_by(MmsReviewSummaryService.service_id)
    )
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[build_service_summary_out(i, db) for i in items])


@router.get("/vendors/{service_vendor_id}/review-summary", response_model=VendorReviewSummaryOut)
def get_vendor_review_summary(service_vendor_id: int, db: Session = Depends(get_db)):
    """查看供應商整合評價AI摘要，橫跨其名下所有服務彙整。404代表尚未生成過。"""
    obj = _get_vendor_summary_or_404(db, service_vendor_id)
    return build_vendor_summary_out(obj, db)


@router.put("/vendors/{service_vendor_id}/review-summary", response_model=VendorReviewSummaryOut)
def upsert_vendor_review_summary(
    service_vendor_id: int, payload: VendorReviewSummaryUpsert, response: Response, db: Session = Depends(get_db)
):
    """完整覆寫供應商整合摘要。key不存在則新建(201)，存在則整包覆蓋(200)。"""
    now = now_utc()
    obj = db.get(MmsReviewSummaryVendor, service_vendor_id)
    if obj is None:
        obj = MmsReviewSummaryVendor(
            service_vendor_id=service_vendor_id, vendor_name=payload.vendor_name,
            summary_content=payload.summary_content,
            summary_highlights=payload.summary_highlights, sentiment_stats=payload.sentiment_stats,
            service_breakdown=payload.service_breakdown, source_review_count=payload.source_review_count,
            source_avg_rating=payload.source_avg_rating, latest_review_cre_time=payload.latest_review_cre_time,
            ai_model=payload.ai_model, generate_status=payload.generate_status,
            generate_time=now, error_message=payload.error_message, is_deleted=False,
            cre_id=SYSTEM_ACTOR_ID, cre_time=now, upd_id=None, upd_time=now,
        )
        db.add(obj)
        response.status_code = 201
    else:
        obj.vendor_name = payload.vendor_name
        obj.summary_content = payload.summary_content
        obj.summary_highlights = payload.summary_highlights
        obj.sentiment_stats = payload.sentiment_stats
        obj.service_breakdown = payload.service_breakdown
        obj.source_review_count = payload.source_review_count
        obj.source_avg_rating = payload.source_avg_rating
        obj.latest_review_cre_time = payload.latest_review_cre_time
        obj.ai_model = payload.ai_model
        obj.generate_status = payload.generate_status
        obj.generate_time = now
        obj.error_message = payload.error_message
        obj.is_deleted = False
        obj.upd_id = SYSTEM_ACTOR_ID
        obj.upd_time = now
        response.status_code = 200
    db.commit()
    db.refresh(obj)
    return build_vendor_summary_out(obj, db)


@router.patch("/vendors/{service_vendor_id}/review-summary/status", response_model=VendorReviewSummaryOut)
def update_vendor_review_summary_status(
    service_vendor_id: int, payload: ReviewSummaryStatusUpdate, db: Session = Depends(get_db)
):
    """僅更新生成狀態。目標key尚無記錄時自動建立殼記錄（其餘欄位皆為null）。
    殼記錄的 vendor_name 由 cms_homepage_service_vendor 查得（值相等關聯，非FK）。"""
    now = now_utc()
    obj = db.get(MmsReviewSummaryVendor, service_vendor_id)
    if obj is None:
        vendor = db.get(CmsHomepageServiceVendor, service_vendor_id)
        if vendor is None:
            raise HTTPException(status_code=404, detail="服務提供商不存在，無法建立摘要殼記錄")
        obj = MmsReviewSummaryVendor(
            service_vendor_id=service_vendor_id, vendor_name=vendor.name,
            summary_content=None, summary_highlights=None,
            sentiment_stats=None, service_breakdown=None, source_review_count=0,
            source_avg_rating=None, latest_review_cre_time=None, ai_model=None,
            generate_status=payload.generate_status, generate_time=None,
            error_message=payload.error_message, is_deleted=False,
            cre_id=SYSTEM_ACTOR_ID, cre_time=now, upd_id=None, upd_time=now,
        )
        db.add(obj)
    else:
        obj.generate_status = payload.generate_status
        obj.error_message = payload.error_message
        obj.upd_id = SYSTEM_ACTOR_ID
        obj.upd_time = now
    db.commit()
    db.refresh(obj)
    return build_vendor_summary_out(obj, db)


@router.delete("/vendors/{service_vendor_id}/review-summary", status_code=204)
def delete_vendor_review_summary(service_vendor_id: int, db: Session = Depends(get_db)):
    """軟刪除摘要，之後GET視為404，但不清空欄位內容。"""
    obj = db.get(MmsReviewSummaryVendor, service_vendor_id)
    if obj is None or obj.is_deleted:
        raise HTTPException(status_code=404, detail="該供應商尚無整合評價AI摘要")
    obj.is_deleted = True
    obj.upd_id = SYSTEM_ACTOR_ID
    obj.upd_time = now_utc()
    db.commit()
