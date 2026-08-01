# -*- coding: utf-8 -*-
"""
SQLAlchemy ORM models，映射 database/ 內既有 DDL 建立的 18 張資料表。

重要：這裡只做「映射」，不負責建表（不呼叫 Base.metadata.create_all）。
表結構的唯一真實來源是 database/*.sql，任何欄位異動請先改 DDL 再回來同步這裡。
"""
import uuid as uuid_mod

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    ForeignKey,
    Integer,
    LargeBinary,
    Numeric,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import JSONB, TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


# ---------------------------------------------------------------------------
# A. 縣市/行政區
# ---------------------------------------------------------------------------
class SysCounty(Base):
    __tablename__ = "sys_county"

    code: Mapped[str] = mapped_column(String(2), primary_key=True)
    name: Mapped[str] = mapped_column(String(10))
    sort: Mapped[int] = mapped_column(Integer)
    is_deleted: Mapped[str] = mapped_column(String(2))
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)


class SysDistrict(Base):
    __tablename__ = "sys_district"

    code: Mapped[str] = mapped_column(String(3), primary_key=True)
    county_code: Mapped[str] = mapped_column(String(2))
    name: Mapped[str] = mapped_column(String(20))
    name_with_county: Mapped[str] = mapped_column(String(20))
    zip: Mapped[str] = mapped_column(String(6))
    sort: Mapped[int] = mapped_column(Integer)
    is_deleted: Mapped[str] = mapped_column(String(2))
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)


# ---------------------------------------------------------------------------
# B. 服務商 / 服務項目主檔
# ---------------------------------------------------------------------------
class CmsHomepageServiceVendor(Base):
    __tablename__ = "cms_homepage_service_vendor"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(50))
    description: Mapped[str | None] = mapped_column(String(200), nullable=True)


class CmsHomepageService(Base):
    __tablename__ = "cms_homepage_service"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    service_vendor_id: Mapped[int] = mapped_column(Integer)
    type: Mapped[str] = mapped_column(String(2))
    name: Mapped[str] = mapped_column(String(100))
    img_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    form_id: Mapped[int | None] = mapped_column(Integer, nullable=True)


# ---------------------------------------------------------------------------
# C. 標籤
# ---------------------------------------------------------------------------
class Label(Base):
    __tablename__ = "label"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(50))
    sort: Mapped[int] = mapped_column(Integer, default=0)
    is_enable: Mapped[str] = mapped_column(String(2))
    is_deleted: Mapped[str] = mapped_column(String(2))
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    service_type: Mapped[str | None] = mapped_column(String(2), nullable=True)


class ServiceLabel(Base):
    __tablename__ = "service_label"

    service_id: Mapped[int] = mapped_column(Integer, primary_key=True)
    label_id: Mapped[int] = mapped_column(Integer, primary_key=True)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)


# ---------------------------------------------------------------------------
# D/E. 帳號
# ---------------------------------------------------------------------------
class VendorAccount(Base):
    __tablename__ = "vendor_accounts"

    id: Mapped[uuid_mod.UUID] = mapped_column(UUID, primary_key=True)
    service_vendor_id: Mapped[int] = mapped_column(Integer)
    account: Mapped[str] = mapped_column(String(100))
    password_hash: Mapped[str] = mapped_column(String(255))
    contact_name: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_name_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    contact_mobile: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_mobile_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    contact_email: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_email_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    is_2fa_enabled: Mapped[str] = mapped_column(String(2), default="0")
    totp_secret: Mapped[str | None] = mapped_column(String(255), nullable=True)
    last_login_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    is_enable: Mapped[str] = mapped_column(String(2))
    is_deleted: Mapped[str] = mapped_column(String(2))
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)


class UserAccount(Base):
    __tablename__ = "user_accounts"

    id: Mapped[uuid_mod.UUID] = mapped_column(UUID, primary_key=True)
    account: Mapped[str] = mapped_column(String(100))
    password_hash: Mapped[str] = mapped_column(String(255))
    contact_name: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_name_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    contact_mobile: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_mobile_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    contact_email: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_email_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    is_2fa_enabled: Mapped[str] = mapped_column(String(2), default="0")
    totp_secret: Mapped[str | None] = mapped_column(String(255), nullable=True)
    last_login_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    is_enable: Mapped[str] = mapped_column(String(2))
    is_deleted: Mapped[str] = mapped_column(String(2))
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)


# ---------------------------------------------------------------------------
# F. 表單結構
# ---------------------------------------------------------------------------
class PmsForm(Base):
    __tablename__ = "pms_form"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    service_vendor_id: Mapped[int] = mapped_column(Integer)
    type: Mapped[str] = mapped_column(String(2))
    sub_type: Mapped[str] = mapped_column(String(2))
    name: Mapped[str] = mapped_column(String(50))
    intro_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    notice_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    terms_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    review_status: Mapped[str] = mapped_column(String(2))
    reviewed_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    reviewed_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    is_enable: Mapped[str] = mapped_column(String(2))
    is_deleted: Mapped[str] = mapped_column(String(2))
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    feature: Mapped[dict | None] = mapped_column(JSONB, nullable=True)


class PmsFormGroup(Base):
    __tablename__ = "pms_form_group"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    form_id: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String(50))
    sort: Mapped[int] = mapped_column(Integer)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    feature: Mapped[dict | None] = mapped_column(JSONB, nullable=True)


class PmsFormTopic(Base):
    __tablename__ = "pms_form_topic"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    form_id: Mapped[int] = mapped_column(Integer)
    form_group_id: Mapped[int] = mapped_column(Integer)
    type: Mapped[str] = mapped_column(String(2))
    title: Mapped[str] = mapped_column(String(200))
    remark: Mapped[str | None] = mapped_column(String(500), nullable=True)
    is_required: Mapped[str] = mapped_column(String(2))
    sort: Mapped[int] = mapped_column(Integer)
    is_number_only: Mapped[str | None] = mapped_column(String(2), nullable=True)
    minimum_medias_upload: Mapped[int | None] = mapped_column(Integer, nullable=True)
    maximum_medias_upload: Mapped[int | None] = mapped_column(Integer, nullable=True)
    specified_medias_upload: Mapped[int | None] = mapped_column(Integer, nullable=True)
    start_date_offset_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    end_date_offset_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    feature: Mapped[dict | None] = mapped_column(JSONB, nullable=True)


class PmsTopicMedia(Base):
    __tablename__ = "pms_topic_media"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    form_id: Mapped[int] = mapped_column(Integer)
    topic_id: Mapped[int] = mapped_column(Integer)
    img_url: Mapped[str] = mapped_column(Text)
    sort: Mapped[int] = mapped_column(Integer)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)


class PmsTopicOption(Base):
    __tablename__ = "pms_topic_option"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    form_id: Mapped[int] = mapped_column(Integer)
    topic_id: Mapped[int] = mapped_column(Integer)
    option_name: Mapped[str] = mapped_column(String(200))
    unit_price: Mapped[int | None] = mapped_column(Integer, nullable=True)
    unit: Mapped[str | None] = mapped_column(String(30), nullable=True)
    is_quantity: Mapped[str | None] = mapped_column(String(2), nullable=True)
    min_quantity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    max_quantity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_quoted_separately: Mapped[str | None] = mapped_column(String(2), nullable=True)
    remark: Mapped[str | None] = mapped_column(String(500), nullable=True)
    sort: Mapped[int] = mapped_column(Integer)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    feature: Mapped[dict | None] = mapped_column(JSONB, nullable=True)


class PmsTopicCountyDistrictRelation(Base):
    __tablename__ = "pms_topic_county_district_relation"

    form_id: Mapped[int] = mapped_column(Integer, primary_key=True)
    topic_id: Mapped[int] = mapped_column(Integer, primary_key=True)
    eff_ts_from: Mapped[object] = mapped_column(TIMESTAMP(timezone=True), primary_key=True)
    eff_ts_to: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    county_code: Mapped[str] = mapped_column(String(2), primary_key=True)
    district_code: Mapped[str] = mapped_column(String(3), primary_key=True)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)


class PmsFormFeedback(Base):
    __tablename__ = "pms_form_feedback"

    feedback_no: Mapped[str] = mapped_column(String(16), primary_key=True)
    service_id: Mapped[int] = mapped_column(Integer)
    platform_code: Mapped[str] = mapped_column(String(2))
    form_id: Mapped[int] = mapped_column(Integer)
    feedback_content: Mapped[dict] = mapped_column(JSONB)
    form_type: Mapped[str] = mapped_column(String(2))
    is_read: Mapped[str] = mapped_column(String(2))
    status: Mapped[str] = mapped_column(String(2))
    contact_name: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_name_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    contact_mobile: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_mobile_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    contact_landline: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_landline_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    contact_email: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_email_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    preferred_contact_time: Mapped[str | None] = mapped_column(String(2), nullable=True)
    contact_address_county: Mapped[str | None] = mapped_column(String(10), nullable=True)
    contact_address_district: Mapped[str | None] = mapped_column(String(20), nullable=True)
    contact_address_detail: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    contact_address_detail_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    description: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    inbr_account_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))


# ---------------------------------------------------------------------------
# H. 訂單
# ---------------------------------------------------------------------------
class MmsOrderRecord(Base):
    __tablename__ = "mms_order_record"

    record_id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    order_no: Mapped[str] = mapped_column(String(50))
    service_vendor_id: Mapped[int] = mapped_column(Integer)
    service_id: Mapped[int] = mapped_column(Integer)
    platform_code: Mapped[str] = mapped_column(String(2))
    inbr_account_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    member_name: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    member_name_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    member_phone: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    member_phone_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    member_email: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    member_email_hash: Mapped[str | None] = mapped_column(String(50), nullable=True)
    order_type: Mapped[str] = mapped_column(String(2))
    order_status: Mapped[str] = mapped_column(String(2))
    order_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    deposit_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    confirm_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    service_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    complete_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    cancel_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    deposit_amount: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    original_amount: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    discount_amount: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    shipping_fee_amount: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    final_amount: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    refund_amount: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    order_points: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    used_points: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    refund_points: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    earn_points: Mapped[float] = mapped_column(Numeric(10, 2), default=0)
    point_status: Mapped[str] = mapped_column(String(2), default="01")
    point_grant_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    vendor_data: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    order_items: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    remark: Mapped[str | None] = mapped_column(Text, nullable=True)
    cancel_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    refund_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_file: Mapped[str | None] = mapped_column(String(200), nullable=True)
    import_batch: Mapped[str | None] = mapped_column(String(50), nullable=True)
    quote_approved_by: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    quote_approved_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    quote_no: Mapped[str | None] = mapped_column(String(64), nullable=True)
    comment_status: Mapped[str] = mapped_column(String(2), default="00")
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))


class MmsOrderReview(Base):
    """訂單評價單。record_id 與 mms_order_record 共用主鍵值(1:0..1對應)，
    本表無獨立序列，新增資料時 record_id 必須從對應訂單取得，不可自動產生。"""
    __tablename__ = "mms_order_review"

    record_id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=False)
    order_no: Mapped[str] = mapped_column(String(50))
    service_vendor_id: Mapped[int] = mapped_column(Integer)
    service_id: Mapped[int] = mapped_column(Integer)
    inbr_account_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    overall_rating: Mapped[int] = mapped_column(Integer)
    rating_detail: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    review_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    media: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    status: Mapped[str] = mapped_column(String(2), default="01")
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))


# ---------------------------------------------------------------------------
# I2. 評價AI摘要（新增功能）
# ---------------------------------------------------------------------------
class MmsReviewSummaryService(Base):
    """服務項目評價AI摘要，覆寫式快取：同一個 service_id 只保留最新1筆，
    重新生成時直接覆蓋既有資料，不留歷史版本。PK 為 service_id（與
    cms_homepage_service.id 共用值，無獨立序列）。"""
    __tablename__ = "mms_review_summary_service"

    service_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=False)
    service_vendor_id: Mapped[int] = mapped_column(Integer)
    summary_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    summary_highlights: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    sentiment_stats: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    source_review_count: Mapped[int] = mapped_column(Integer, default=0)
    source_avg_rating: Mapped[float | None] = mapped_column(Numeric(3, 2), nullable=True)
    latest_review_cre_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    ai_model: Mapped[str | None] = mapped_column(String(50), nullable=True)
    generate_status: Mapped[str] = mapped_column(String(2), default="00")
    generate_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))


class MmsReviewSummaryVendor(Base):
    """供應商整合評價AI摘要，覆寫式快取：同一個 service_vendor_id 只保留
    最新1筆，橫跨其名下所有服務彙整。PK 為 service_vendor_id（與
    cms_homepage_service_vendor.id 共用值，無獨立序列）。僅供供應商後台使用。"""
    __tablename__ = "mms_review_summary_vendor"

    service_vendor_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=False)
    summary_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    summary_highlights: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    sentiment_stats: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    service_breakdown: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    source_review_count: Mapped[int] = mapped_column(Integer, default=0)
    source_avg_rating: Mapped[float | None] = mapped_column(Numeric(3, 2), nullable=True)
    latest_review_cre_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    ai_model: Mapped[str | None] = mapped_column(String(50), nullable=True)
    generate_status: Mapped[str] = mapped_column(String(2), default="00")
    generate_time: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    cre_id: Mapped[uuid_mod.UUID] = mapped_column(UUID)
    cre_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
    upd_id: Mapped[uuid_mod.UUID | None] = mapped_column(UUID, nullable=True)
    upd_time: Mapped[object] = mapped_column(TIMESTAMP(timezone=True))
