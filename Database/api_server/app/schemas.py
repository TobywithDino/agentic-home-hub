# -*- coding: utf-8 -*-
"""
Pydantic schemas：各資源的 Create / Update / Response 模型。
命名慣例：<Resource>Create / <Resource>Update / <Resource>Out
"""
import datetime as dt
import uuid
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

# JSONB 欄位可能儲存任意合法 JSON 結構（object 或 array），
# 不可預先假設一定是 dict，故統一用此型別別名放寬限制。
JsonValue = dict[str, Any] | list[Any]


# ---------------------------------------------------------------------------
# 共用
# ---------------------------------------------------------------------------
class Pagination(BaseModel):
    limit: int = Field(default=20, ge=1, le=200)
    offset: int = Field(default=0, ge=0)


class PagedResponse(BaseModel):
    total: int
    limit: int
    offset: int
    items: list[Any]


# ---------------------------------------------------------------------------
# A. 縣市 / 行政區
# ---------------------------------------------------------------------------
class CountyCreate(BaseModel):
    code: str = Field(max_length=2)
    name: str = Field(max_length=10)
    sort: int = 0


class CountyUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=10)
    sort: int | None = None


class CountyOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    code: str
    name: str
    sort: int
    is_deleted: str
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID


class DistrictCreate(BaseModel):
    code: str = Field(max_length=3)
    county_code: str = Field(max_length=2)
    name: str = Field(max_length=20)
    name_with_county: str = Field(max_length=20)
    zip: str = Field(max_length=6)
    sort: int = 0


class DistrictUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=20)
    name_with_county: str | None = Field(default=None, max_length=20)
    zip: str | None = Field(default=None, max_length=6)
    sort: int | None = None


class DistrictOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    code: str
    county_code: str
    name: str
    name_with_county: str
    zip: str
    sort: int
    is_deleted: str
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID


# ---------------------------------------------------------------------------
# B. 服務商 / 服務項目
# ---------------------------------------------------------------------------
class ServiceVendorCreate(BaseModel):
    id: int
    name: str = Field(max_length=50)
    description: str | None = Field(default=None, max_length=200)


class ServiceVendorUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=50)
    description: str | None = Field(default=None, max_length=200)


class ServiceVendorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    description: str | None


class ServiceCreate(BaseModel):
    id: int
    service_vendor_id: int
    type: str = Field(max_length=2)
    name: str = Field(max_length=100)
    img_url: str | None = Field(default=None, max_length=500)
    description: str | None = None
    form_id: int | None = None


class ServiceUpdate(BaseModel):
    service_vendor_id: int | None = None
    type: str | None = Field(default=None, max_length=2)
    name: str | None = Field(default=None, max_length=100)
    img_url: str | None = Field(default=None, max_length=500)
    description: str | None = None
    form_id: int | None = None


class ServiceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    service_vendor_id: int
    type: str
    name: str
    img_url: str | None
    description: str | None
    form_id: int | None


# ---------------------------------------------------------------------------
# C. 標籤
# ---------------------------------------------------------------------------
class LabelCreate(BaseModel):
    name: str = Field(max_length=50)
    sort: int = 0
    is_enable: str = "1"
    service_type: str | None = Field(default=None, max_length=2)


class LabelUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=50)
    sort: int | None = None
    is_enable: str | None = None
    service_type: str | None = Field(default=None, max_length=2)


class LabelOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    sort: int
    is_enable: str
    is_deleted: str
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID
    service_type: str | None


class ServiceLabelOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    service_id: int
    label_id: int
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID


# ---------------------------------------------------------------------------
# D. 會員帳號
# ---------------------------------------------------------------------------
class UserRegister(BaseModel):
    account: str = Field(max_length=100)
    password: str = Field(min_length=8, max_length=72)
    contact_name: str | None = None
    contact_mobile: str | None = None
    contact_email: str | None = None


class UserLogin(BaseModel):
    account: str
    password: str


class UserLoginOut(BaseModel):
    inbr_account_id: uuid.UUID


class UserUpdate(BaseModel):
    """更新聯絡方式/密碼。password 若提供則重新雜湊，contact_* 若提供則重新加密。"""
    password: str | None = Field(default=None, min_length=8, max_length=72)
    contact_name: str | None = None
    contact_mobile: str | None = None
    contact_email: str | None = None
    is_enable: str | None = None


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    account: str
    contact_name: str | None = None
    contact_name_hash: str | None = None
    contact_mobile: str | None = None
    contact_mobile_hash: str | None = None
    contact_email: str | None = None
    contact_email_hash: str | None = None
    is_2fa_enabled: str
    last_login_time: dt.datetime | None
    is_enable: str
    is_deleted: str
    upd_time: dt.datetime
    cre_time: dt.datetime


# ---------------------------------------------------------------------------
# E. 服務商後台帳號
# ---------------------------------------------------------------------------
class VendorAccountRegister(BaseModel):
    service_vendor_id: int
    account: str = Field(max_length=100)
    password: str = Field(min_length=8, max_length=72)
    contact_name: str | None = None
    contact_mobile: str | None = None
    contact_email: str | None = None


class VendorLogin(BaseModel):
    account: str
    password: str


class VendorLoginOut(BaseModel):
    service_vendor_id: int
    account_id: uuid.UUID


class VendorAccountUpdate(BaseModel):
    password: str | None = Field(default=None, min_length=8, max_length=72)
    contact_name: str | None = None
    contact_mobile: str | None = None
    contact_email: str | None = None
    is_enable: str | None = None


class VendorAccountOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    service_vendor_id: int
    account: str
    contact_name: str | None = None
    contact_name_hash: str | None = None
    contact_mobile: str | None = None
    contact_mobile_hash: str | None = None
    contact_email: str | None = None
    contact_email_hash: str | None = None
    is_2fa_enabled: str
    last_login_time: dt.datetime | None
    is_enable: str
    is_deleted: str
    upd_time: dt.datetime
    cre_time: dt.datetime


# ---------------------------------------------------------------------------
# F. 表單結構
# ---------------------------------------------------------------------------
class FormCreate(BaseModel):
    service_vendor_id: int
    type: str = Field(max_length=2)
    sub_type: str = Field(max_length=2)
    name: str = Field(max_length=50)
    intro_content: str | None = None
    notice_content: str | None = None
    terms_content: str | None = None
    is_enable: str = "1"
    feature: JsonValue | None = None


class FormUpdate(BaseModel):
    service_vendor_id: int | None = None
    type: str | None = Field(default=None, max_length=2)
    sub_type: str | None = Field(default=None, max_length=2)
    name: str | None = Field(default=None, max_length=50)
    intro_content: str | None = None
    notice_content: str | None = None
    terms_content: str | None = None
    is_enable: str | None = None
    feature: JsonValue | None = None


class FormReviewUpdate(BaseModel):
    review_status: str = Field(max_length=2)
    reviewed_id: uuid.UUID


class FormOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    service_vendor_id: int
    type: str
    sub_type: str
    name: str
    intro_content: str | None
    notice_content: str | None
    terms_content: str | None
    review_status: str
    reviewed_id: uuid.UUID | None
    reviewed_time: dt.datetime | None
    is_enable: str
    is_deleted: str
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID
    feature: JsonValue | None


class FormGroupCreate(BaseModel):
    name: str = Field(max_length=50)
    sort: int = 0
    feature: JsonValue | None = None


class FormGroupUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=50)
    sort: int | None = None
    feature: JsonValue | None = None


class FormGroupOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    form_id: int
    name: str
    sort: int
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID
    feature: JsonValue | None


class FormTopicCreate(BaseModel):
    form_group_id: int
    type: str = Field(max_length=2)
    title: str = Field(max_length=200)
    remark: str | None = Field(default=None, max_length=500)
    is_required: str = "0"
    sort: int = 0
    is_number_only: str | None = None
    minimum_medias_upload: int | None = None
    maximum_medias_upload: int | None = None
    specified_medias_upload: int | None = None
    start_date_offset_days: int | None = None
    end_date_offset_days: int | None = None
    feature: JsonValue | None = None


class FormTopicUpdate(BaseModel):
    form_group_id: int | None = None
    type: str | None = Field(default=None, max_length=2)
    title: str | None = Field(default=None, max_length=200)
    remark: str | None = Field(default=None, max_length=500)
    is_required: str | None = None
    sort: int | None = None
    is_number_only: str | None = None
    minimum_medias_upload: int | None = None
    maximum_medias_upload: int | None = None
    specified_medias_upload: int | None = None
    start_date_offset_days: int | None = None
    end_date_offset_days: int | None = None
    feature: JsonValue | None = None


class FormTopicOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    form_id: int
    form_group_id: int
    type: str
    title: str
    remark: str | None
    is_required: str
    sort: int
    is_number_only: str | None
    minimum_medias_upload: int | None
    maximum_medias_upload: int | None
    specified_medias_upload: int | None
    start_date_offset_days: int | None
    end_date_offset_days: int | None
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID
    feature: JsonValue | None


class TopicMediaCreate(BaseModel):
    img_url: str
    sort: int = 0


class TopicMediaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    form_id: int
    topic_id: int
    img_url: str
    sort: int
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID


class TopicOptionCreate(BaseModel):
    option_name: str = Field(max_length=200)
    unit_price: int | None = None
    unit: str | None = Field(default=None, max_length=30)
    is_quantity: str | None = None
    min_quantity: int | None = None
    max_quantity: int | None = None
    is_quoted_separately: str | None = None
    remark: str | None = Field(default=None, max_length=500)
    sort: int = 0
    feature: JsonValue | None = None


class TopicOptionUpdate(BaseModel):
    option_name: str | None = Field(default=None, max_length=200)
    unit_price: int | None = None
    unit: str | None = Field(default=None, max_length=30)
    is_quantity: str | None = None
    min_quantity: int | None = None
    max_quantity: int | None = None
    is_quoted_separately: str | None = None
    remark: str | None = Field(default=None, max_length=500)
    sort: int | None = None
    feature: JsonValue | None = None


class TopicOptionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    form_id: int
    topic_id: int
    option_name: str
    unit_price: int | None
    unit: str | None
    is_quantity: str | None
    min_quantity: int | None
    max_quantity: int | None
    is_quoted_separately: str | None
    remark: str | None
    sort: int
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID
    feature: JsonValue | None


class CountyDistrictRelationCreate(BaseModel):
    eff_ts_from: dt.datetime
    eff_ts_to: dt.datetime
    county_code: str = Field(max_length=2)
    district_code: str = Field(max_length=3)


class CountyDistrictRelationDelete(BaseModel):
    eff_ts_from: dt.datetime
    county_code: str = Field(max_length=2)
    district_code: str = Field(max_length=3)


class CountyDistrictRelationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    form_id: int
    topic_id: int
    eff_ts_from: dt.datetime
    eff_ts_to: dt.datetime
    county_code: str
    district_code: str
    upd_time: dt.datetime
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    cre_id: uuid.UUID


# ---------------------------------------------------------------------------
# G. 諮詢單回饋
# ---------------------------------------------------------------------------
class FeedbackCreate(BaseModel):
    feedback_no: str = Field(max_length=16)
    service_id: int
    platform_code: str = Field(max_length=2)
    form_id: int
    feedback_content: JsonValue
    form_type: str = Field(max_length=2)
    contact_name: str | None = None
    contact_mobile: str | None = None
    contact_landline: str | None = None
    contact_email: str | None = None
    preferred_contact_time: str | None = None
    contact_address_county: str | None = Field(default=None, max_length=10)
    contact_address_district: str | None = Field(default=None, max_length=20)
    contact_address_detail: str | None = None
    description: str | None = Field(default=None, max_length=1000)
    inbr_account_id: uuid.UUID


class FeedbackStatusUpdate(BaseModel):
    is_read: str | None = None
    status: str | None = None


class FeedbackOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    feedback_no: str
    service_id: int
    platform_code: str
    form_id: int
    feedback_content: JsonValue
    form_type: str
    is_read: str
    status: str
    contact_name: str | None = None
    contact_name_hash: str | None = None
    contact_mobile: str | None = None
    contact_mobile_hash: str | None = None
    contact_landline: str | None = None
    contact_landline_hash: str | None = None
    contact_email: str | None = None
    contact_email_hash: str | None = None
    preferred_contact_time: str | None
    contact_address_county: str | None
    contact_address_district: str | None
    contact_address_detail: str | None = None
    contact_address_detail_hash: str | None = None
    description: str | None
    inbr_account_id: uuid.UUID
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    upd_time: dt.datetime


# ---------------------------------------------------------------------------
# H. 訂單
# ---------------------------------------------------------------------------
class OrderCreate(BaseModel):
    order_no: str = Field(max_length=50)
    service_vendor_id: int
    service_id: int
    platform_code: str = Field(max_length=2)
    inbr_account_id: uuid.UUID
    member_name: str | None = None
    member_phone: str | None = None
    member_email: str | None = None
    order_type: str = Field(max_length=2)
    order_status: str = Field(max_length=2)
    order_time: dt.datetime
    deposit_amount: float = 0
    original_amount: float = 0
    discount_amount: float = 0
    shipping_fee_amount: float = 0
    final_amount: float = 0
    vendor_data: JsonValue | None = None
    order_items: JsonValue | None = None
    remark: str | None = None
    source_file: str | None = Field(default=None, max_length=200)
    import_batch: str | None = Field(default=None, max_length=50)
    cre_id: uuid.UUID
    upd_id: uuid.UUID


class OrderUpdate(BaseModel):
    """依 service_vendor_id 更新單筆訂單，開放服務商後台常見會異動的欄位。"""
    order_status: str | None = Field(default=None, max_length=2)
    deposit_time: dt.datetime | None = None
    confirm_time: dt.datetime | None = None
    service_time: dt.datetime | None = None
    complete_time: dt.datetime | None = None
    cancel_time: dt.datetime | None = None
    deposit_amount: float | None = None
    original_amount: float | None = None
    discount_amount: float | None = None
    shipping_fee_amount: float | None = None
    final_amount: float | None = None
    refund_amount: float | None = None
    order_points: float | None = None
    used_points: float | None = None
    refund_points: float | None = None
    earn_points: float | None = None
    point_status: str | None = None
    point_grant_time: dt.datetime | None = None
    vendor_data: JsonValue | None = None
    order_items: JsonValue | None = None
    remark: str | None = None
    cancel_reason: str | None = None
    refund_reason: str | None = None
    quote_approved_by: uuid.UUID | None = None
    quote_approved_time: dt.datetime | None = None
    quote_no: str | None = Field(default=None, max_length=64)
    comment_status: str | None = None
    is_deleted: bool | None = None
    upd_id: uuid.UUID


class OrderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    record_id: int
    order_no: str
    service_vendor_id: int
    service_id: int
    platform_code: str
    inbr_account_id: uuid.UUID
    member_name: str | None = None
    member_name_hash: str | None = None
    member_phone: str | None = None
    member_phone_hash: str | None = None
    member_email: str | None = None
    member_email_hash: str | None = None
    order_type: str
    order_status: str
    order_time: dt.datetime
    deposit_time: dt.datetime | None
    confirm_time: dt.datetime | None
    service_time: dt.datetime | None
    complete_time: dt.datetime | None
    cancel_time: dt.datetime | None
    deposit_amount: float
    original_amount: float
    discount_amount: float
    shipping_fee_amount: float
    final_amount: float
    refund_amount: float
    order_points: float
    used_points: float
    refund_points: float
    earn_points: float
    point_status: str
    point_grant_time: dt.datetime | None
    vendor_data: JsonValue | None
    order_items: JsonValue | None
    remark: str | None
    cancel_reason: str | None
    refund_reason: str | None
    source_file: str | None
    import_batch: str | None
    quote_approved_by: uuid.UUID | None
    quote_approved_time: dt.datetime | None
    quote_no: str | None
    comment_status: str
    is_deleted: bool
    cre_id: uuid.UUID
    cre_time: dt.datetime
    upd_id: uuid.UUID
    upd_time: dt.datetime


class OrderSummaryOut(BaseModel):
    """會員「查看訂單」拼接回應：未處理 feedback + orders"""
    feedbacks: list[FeedbackOut]
    orders: list[OrderOut]


# ---------------------------------------------------------------------------
# I. 訂單評價
# ---------------------------------------------------------------------------
class ReviewCreate(BaseModel):
    inbr_account_id: uuid.UUID
    overall_rating: int = Field(ge=1, le=5)
    rating_detail: JsonValue | None = None
    review_content: str | None = None
    media: JsonValue | None = None


class ReviewUpdate(BaseModel):
    """評價者本人修改內容用。依現有架構(無身分驗證中介層)，由呼叫端於路由層
    自行比對 inbr_account_id 是否與該筆評價一致，本 schema 僅負責欄位驗證。"""
    overall_rating: int | None = Field(default=None, ge=1, le=5)
    rating_detail: JsonValue | None = None
    review_content: str | None = None
    media: JsonValue | None = None


class ReviewOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    record_id: int
    order_no: str
    service_vendor_id: int
    service_id: int
    inbr_account_id: uuid.UUID
    overall_rating: int
    rating_detail: JsonValue | None
    review_content: str | None
    media: JsonValue | None
    status: str
    is_deleted: bool
    cre_id: uuid.UUID
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    upd_time: dt.datetime


class PublicReviewOut(BaseModel):
    """公開評價牆專用（GET /services/{service_id}/reviews，無需身分驗證即可呼叫）。
    刻意排除 inbr_account_id/order_no/service_vendor_id/status/is_deleted 等
    身分或內部狀態欄位，避免對外洩漏評價者身分或訂單資訊。"""
    model_config = ConfigDict(from_attributes=True)
    record_id: int
    overall_rating: int
    rating_detail: JsonValue | None
    review_content: str | None
    media: JsonValue | None
    cre_time: dt.datetime


class RatingSummaryOut(BaseModel):
    service_vendor_id: int
    service_id: int | None = None
    review_count: int
    average_rating: float | None


# ---------------------------------------------------------------------------
# I2. 評價AI摘要（新增功能）
# ---------------------------------------------------------------------------
class ReviewSummaryStatusUpdate(BaseModel):
    """僅更新生成狀態用，讓生成流程可以「先標記生成中」再非同步寫入完整內容。
    若目標 key 尚無記錄，路由層會自動建立一筆殼記錄（其餘欄位皆為 null）。"""
    generate_status: str = Field(max_length=2)
    error_message: str | None = None


class ServiceReviewSummaryUpsert(BaseModel):
    """完整覆寫語意：呼叫端（AI生成流程）應自行查詢當下最新的評價聚合值
    （筆數/平均分/最新時間）連同生成結果一起送出。generate_time 由伺服器端填入。"""
    service_vendor_id: int
    summary_content: str | None = None
    summary_highlights: JsonValue | None = None
    sentiment_stats: JsonValue | None = None
    source_review_count: int = 0
    source_avg_rating: float | None = None
    latest_review_cre_time: dt.datetime | None = None
    ai_model: str | None = Field(default=None, max_length=50)
    generate_status: str = Field(max_length=2)
    error_message: str | None = None


class ServiceReviewSummaryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    service_id: int
    service_vendor_id: int
    summary_content: str | None
    summary_highlights: JsonValue | None
    sentiment_stats: JsonValue | None
    source_review_count: int
    source_avg_rating: float | None
    latest_review_cre_time: dt.datetime | None
    ai_model: str | None
    generate_status: str
    generate_time: dt.datetime | None
    error_message: str | None
    is_deleted: bool
    cre_id: uuid.UUID
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    upd_time: dt.datetime
    is_stale: bool = False
    """計算欄位（非資料庫欄位）：即時比對 mms_order_review 目前的
    COUNT(*)/MAX(cre_time) 是否超過本筆摘要記錄的 source_review_count/
    latest_review_cre_time，True 代表有新評價尚未納入摘要，建議觸發重新生成。"""


class VendorReviewSummaryUpsert(BaseModel):
    """結構同 ServiceReviewSummaryUpsert，差異是無 service_vendor_id 冗餘欄位
    （PK 本身即為 service_vendor_id），多一個 service_breakdown 統計快取。"""
    summary_content: str | None = None
    summary_highlights: JsonValue | None = None
    sentiment_stats: JsonValue | None = None
    service_breakdown: JsonValue | None = None
    source_review_count: int = 0
    source_avg_rating: float | None = None
    latest_review_cre_time: dt.datetime | None = None
    ai_model: str | None = Field(default=None, max_length=50)
    generate_status: str = Field(max_length=2)
    error_message: str | None = None


class VendorReviewSummaryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    service_vendor_id: int
    summary_content: str | None
    summary_highlights: JsonValue | None
    sentiment_stats: JsonValue | None
    service_breakdown: JsonValue | None
    source_review_count: int
    source_avg_rating: float | None
    latest_review_cre_time: dt.datetime | None
    ai_model: str | None
    generate_status: str
    generate_time: dt.datetime | None
    error_message: str | None
    is_deleted: bool
    cre_id: uuid.UUID
    cre_time: dt.datetime
    upd_id: uuid.UUID | None
    upd_time: dt.datetime
    is_stale: bool = False
    """計算欄位（非資料庫欄位），語意同 ServiceReviewSummaryOut.is_stale，
    但比對範圍是該供應商名下全部服務的 mms_order_review。"""
