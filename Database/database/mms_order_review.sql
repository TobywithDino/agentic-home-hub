-- public.mms_order_review definition

-- Drop table

-- DROP TABLE public.mms_order_review;

CREATE TABLE public.mms_order_review (
	record_id bigint NOT NULL,
	order_no varchar(50) NOT NULL,
	service_vendor_id int4 NOT NULL,
	service_id int4 NOT NULL,
	inbr_account_id uuid NOT NULL,
	overall_rating int4 NOT NULL,
	rating_detail jsonb NULL,
	review_content text NULL,
	media jsonb NULL,
	status varchar(2) DEFAULT '01'::character varying NOT NULL,
	is_deleted bool DEFAULT false NOT NULL,
	cre_id uuid NOT NULL,
	cre_time timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
	upd_id uuid NULL,
	upd_time timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
	CONSTRAINT pk_order_review PRIMARY KEY (record_id),
	CONSTRAINT chk_order_review_rating CHECK (overall_rating BETWEEN 1 AND 5)
);
CREATE INDEX idx_order_review_account ON public.mms_order_review USING btree (inbr_account_id);
CREATE INDEX idx_order_review_vendor ON public.mms_order_review USING btree (service_vendor_id);
CREATE INDEX idx_order_review_service ON public.mms_order_review USING btree (service_id);
CREATE INDEX idx_order_review_rating_detail ON public.mms_order_review USING gin (rating_detail);
COMMENT ON TABLE public.mms_order_review IS '訂單評價單，每筆訂單至多一筆評價（record_id 與 mms_order_record 共用主鍵值，非新產生序列）';

-- Column comments

COMMENT ON COLUMN public.mms_order_review.record_id IS '對應訂單ID(mms_order_record.record_id)，本表無獨立序列，1:1對應';
COMMENT ON COLUMN public.mms_order_review.order_no IS '訂單編號，冗餘自mms_order_record，避免查詢時join';
COMMENT ON COLUMN public.mms_order_review.service_vendor_id IS '服務提供商ID，冗餘欄位';
COMMENT ON COLUMN public.mms_order_review.service_id IS '服務ID，冗餘欄位';
COMMENT ON COLUMN public.mms_order_review.inbr_account_id IS '提交評價的會員編號，應與對應訂單之inbr_account_id一致(由API層驗證，本庫不設FK)';
COMMENT ON COLUMN public.mms_order_review.overall_rating IS '整體評分，1~5星';
COMMENT ON COLUMN public.mms_order_review.rating_detail IS '多維度評分/標籤，JSON格式，例如{"service":5,"attitude":4}';
COMMENT ON COLUMN public.mms_order_review.review_content IS '文字評價內容';
COMMENT ON COLUMN public.mms_order_review.media IS '評價附加照片/影片網址，JSON陣列格式';
COMMENT ON COLUMN public.mms_order_review.status IS '評價狀態，01:已送出, 02:已隱藏(違規下架), 依業務需求擴充';
COMMENT ON COLUMN public.mms_order_review.is_deleted IS '是否刪除';
COMMENT ON COLUMN public.mms_order_review.cre_id IS '新增者編號(通常等於inbr_account_id)';
COMMENT ON COLUMN public.mms_order_review.cre_time IS '新增日期時間';
COMMENT ON COLUMN public.mms_order_review.upd_id IS '異動者編號';
COMMENT ON COLUMN public.mms_order_review.upd_time IS '異動日期時間';
