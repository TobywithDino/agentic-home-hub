-- public.cms_homepage_service_vendor definition

-- Drop table

-- DROP TABLE cms_homepage_service_vendor;

CREATE TABLE cms_homepage_service_vendor ( id int4 NOT NULL, "name" varchar(50) NOT NULL, description varchar(200) NULL, CONSTRAINT cms_homepage_service_vendor_pkey PRIMARY KEY (id));
COMMENT ON TABLE public.cms_homepage_service_vendor IS '首頁服務商主檔';

-- Column comments

COMMENT ON COLUMN public.cms_homepage_service_vendor.id IS '服務商ID';
COMMENT ON COLUMN public.cms_homepage_service_vendor."name" IS '服務商名稱(如:清潔、寄件、餐廳訂位)';
COMMENT ON COLUMN public.cms_homepage_service_vendor.description IS '服務商描述';


-- public.cms_homepage_service definition

-- Drop table

-- DROP TABLE cms_homepage_service;

CREATE TABLE cms_homepage_service ( id int4 NOT NULL, service_vendor_id int4 NOT NULL, "type" varchar(2) NOT NULL, "name" varchar(100) NOT NULL, img_url varchar(500) NULL, description text NULL, form_id int4 NULL, CONSTRAINT cms_homepage_service_pkey PRIMARY KEY (id));
CREATE INDEX idx_cms_homepage_service_vendor_id ON public.cms_homepage_service USING btree (service_vendor_id);
CREATE INDEX idx_cms_homepage_service_form_id ON public.cms_homepage_service USING btree (form_id);
COMMENT ON TABLE public.cms_homepage_service IS '首頁服務項目主檔';

-- Column comments

COMMENT ON COLUMN public.cms_homepage_service.id IS '服務項目ID';
COMMENT ON COLUMN public.cms_homepage_service.service_vendor_id IS '服務提供商ID(對應cms_homepage_service_vendor.id)';
COMMENT ON COLUMN public.cms_homepage_service."type" IS '服務類型代碼:1一般居家清潔/2家電清洗/3包裹寄送/6餐廳訂位/9美食外送/10水電修繕/11商城購物';
COMMENT ON COLUMN public.cms_homepage_service."name" IS '服務項目名稱';
COMMENT ON COLUMN public.cms_homepage_service.img_url IS '服務項目圖片網址';
COMMENT ON COLUMN public.cms_homepage_service.description IS '服務項目說明(可含HTML)';
COMMENT ON COLUMN public.cms_homepage_service.form_id IS '此服務項目對應的諮詢表單ID(對應pms_form.id,可為NULL代表尚未設定專屬表單)。一個表單可被多個服務項目共用；若該服務商還有B端/客服/轉訂單流程等通用表單，與此欄位無關，那些表單仍透過pms_form.service_vendor_id + GET /vendors/{id}/forms查詢。';
