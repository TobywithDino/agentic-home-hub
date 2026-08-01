-- public.mms_review_summary_service definition
-- 服務項目評價AI摘要表(面向使用者與供應商共用，1個service_id對應1筆最新摘要)

-- Drop table

-- DROP TABLE public.mms_review_summary_service;

CREATE TABLE public.mms_review_summary_service (
	service_id int4 NOT NULL,
	service_vendor_id int4 NOT NULL,
	summary_content text NULL,
	summary_highlights jsonb NULL,
	sentiment_stats jsonb NULL,
	source_review_count int4 DEFAULT 0 NOT NULL,
	source_avg_rating numeric(3, 2) NULL,
	latest_review_cre_time timestamptz NULL,
	ai_model varchar(50) NULL,
	generate_status varchar(2) DEFAULT '00'::character varying NOT NULL,
	generate_time timestamptz NULL,
	error_message text NULL,
	is_deleted bool DEFAULT false NOT NULL,
	cre_id uuid NOT NULL,
	cre_time timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
	upd_id uuid NULL,
	upd_time timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
	CONSTRAINT pk_review_summary_service PRIMARY KEY (service_id)
);
CREATE INDEX idx_review_summary_service_vendor ON public.mms_review_summary_service USING btree (service_vendor_id);
COMMENT ON TABLE public.mms_review_summary_service IS '服務項目評價AI摘要表，彙整單一service_id底下所有mms_order_review的AI摘要，每個service_id僅保留最新1筆(覆寫式快取)，面向使用者與供應商共用同一份內容';

-- Column comments

COMMENT ON COLUMN public.mms_review_summary_service.service_id IS '服務項目ID(對應cms_homepage_service.id)，本表PK即為此值';
COMMENT ON COLUMN public.mms_review_summary_service.service_vendor_id IS '服務提供商ID，冗餘欄位，方便供應商一次查詢名下所有服務的摘要';
COMMENT ON COLUMN public.mms_review_summary_service.summary_content IS 'AI生成的摘要文字，面向使用者/供應商顯示的整體評語';
COMMENT ON COLUMN public.mms_review_summary_service.summary_highlights IS '結構化重點，JSON格式，例如{"pros":["服務態度好","準時"],"cons":["價格偏高"]}';
COMMENT ON COLUMN public.mms_review_summary_service.sentiment_stats IS '情感分布統計，JSON格式，例如{"positive":12,"neutral":3,"negative":2}';
COMMENT ON COLUMN public.mms_review_summary_service.source_review_count IS '本次摘要納入計算的評價筆數(is_deleted=false)，供前端顯示「根據X則評價」';
COMMENT ON COLUMN public.mms_review_summary_service.source_avg_rating IS '納入計算的評價平均分數快取';
COMMENT ON COLUMN public.mms_review_summary_service.latest_review_cre_time IS '納入計算的最新一筆評價建立時間，用於判斷摘要是否過期(有新評價晚於此時間即代表需重新生成)';
COMMENT ON COLUMN public.mms_review_summary_service.ai_model IS '生成本筆摘要所用的AI模型名稱/版本，例如gpt-4o-mini';
COMMENT ON COLUMN public.mms_review_summary_service.generate_status IS '生成狀態，00:待生成, 01:生成中, 02:已完成, 03:失敗';
COMMENT ON COLUMN public.mms_review_summary_service.generate_time IS '本次摘要生成完成時間';
COMMENT ON COLUMN public.mms_review_summary_service.error_message IS '生成失敗時的錯誤訊息';
COMMENT ON COLUMN public.mms_review_summary_service.is_deleted IS '是否刪除';
COMMENT ON COLUMN public.mms_review_summary_service.cre_id IS '新增者編號';
COMMENT ON COLUMN public.mms_review_summary_service.cre_time IS '新增日期時間';
COMMENT ON COLUMN public.mms_review_summary_service.upd_id IS '異動者編號(通常為觸發重新生成的排程/系統帳號)';
COMMENT ON COLUMN public.mms_review_summary_service.upd_time IS '異動日期時間';


-- public.mms_review_summary_vendor definition
-- 供應商整合評價AI摘要表(面向供應商，跨其名下所有service彙整的總摘要)

-- Drop table

-- DROP TABLE public.mms_review_summary_vendor;

CREATE TABLE public.mms_review_summary_vendor (
	service_vendor_id int4 NOT NULL,
	summary_content text NULL,
	summary_highlights jsonb NULL,
	sentiment_stats jsonb NULL,
	service_breakdown jsonb NULL,
	source_review_count int4 DEFAULT 0 NOT NULL,
	source_avg_rating numeric(3, 2) NULL,
	latest_review_cre_time timestamptz NULL,
	ai_model varchar(50) NULL,
	generate_status varchar(2) DEFAULT '00'::character varying NOT NULL,
	generate_time timestamptz NULL,
	error_message text NULL,
	is_deleted bool DEFAULT false NOT NULL,
	cre_id uuid NOT NULL,
	cre_time timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
	upd_id uuid NULL,
	upd_time timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
	CONSTRAINT pk_review_summary_vendor PRIMARY KEY (service_vendor_id)
);
COMMENT ON TABLE public.mms_review_summary_vendor IS '供應商整合評價AI摘要表，彙整單一service_vendor_id底下所有服務的評價，每個service_vendor_id僅保留最新1筆(覆寫式快取)，僅供供應商後台使用';

-- Column comments

COMMENT ON COLUMN public.mms_review_summary_vendor.service_vendor_id IS '服務提供商ID(對應cms_homepage_service_vendor.id)，本表PK即為此值';
COMMENT ON COLUMN public.mms_review_summary_vendor.summary_content IS 'AI生成的整合摘要文字，橫跨該供應商名下所有服務的評價';
COMMENT ON COLUMN public.mms_review_summary_vendor.summary_highlights IS '結構化重點，JSON格式，同mms_review_summary_service.summary_highlights';
COMMENT ON COLUMN public.mms_review_summary_vendor.sentiment_stats IS '情感分布統計，JSON格式，同mms_review_summary_service.sentiment_stats';
COMMENT ON COLUMN public.mms_review_summary_vendor.service_breakdown IS '各服務項目的簡易統計快取，JSON陣列，例如[{"service_id":1,"review_count":10,"avg_rating":4.5}]，避免前端需另外逐一查詢mms_review_summary_service';
COMMENT ON COLUMN public.mms_review_summary_vendor.source_review_count IS '納入計算的評價總筆數(跨全部服務,is_deleted=false)';
COMMENT ON COLUMN public.mms_review_summary_vendor.source_avg_rating IS '納入計算的評價總平均分數快取';
COMMENT ON COLUMN public.mms_review_summary_vendor.latest_review_cre_time IS '納入計算的最新一筆評價建立時間，用於判斷摘要是否過期';
COMMENT ON COLUMN public.mms_review_summary_vendor.ai_model IS '生成本筆摘要所用的AI模型名稱/版本';
COMMENT ON COLUMN public.mms_review_summary_vendor.generate_status IS '生成狀態，00:待生成, 01:生成中, 02:已完成, 03:失敗';
COMMENT ON COLUMN public.mms_review_summary_vendor.generate_time IS '本次摘要生成完成時間';
COMMENT ON COLUMN public.mms_review_summary_vendor.error_message IS '生成失敗時的錯誤訊息';
COMMENT ON COLUMN public.mms_review_summary_vendor.is_deleted IS '是否刪除';
COMMENT ON COLUMN public.mms_review_summary_vendor.cre_id IS '新增者編號';
COMMENT ON COLUMN public.mms_review_summary_vendor.cre_time IS '新增日期時間';
COMMENT ON COLUMN public.mms_review_summary_vendor.upd_id IS '異動者編號';
COMMENT ON COLUMN public.mms_review_summary_vendor.upd_time IS '異動日期時間';
