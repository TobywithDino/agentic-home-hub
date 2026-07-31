-- public.label definition

-- Drop table

-- DROP TABLE label;

CREATE TABLE label ( id serial4 NOT NULL, "name" varchar(50) NOT NULL, sort int4 DEFAULT 0 NOT NULL, is_enable varchar(2) NOT NULL, is_deleted varchar(2) NOT NULL, upd_time timestamptz NOT NULL, cre_time timestamptz NOT NULL, upd_id uuid NULL, cre_id uuid NOT NULL, CONSTRAINT label_pkey PRIMARY KEY (id), CONSTRAINT label_name_key UNIQUE ("name"));
COMMENT ON TABLE public.label IS '服務特徵標籤主檔';

-- Column comments

COMMENT ON COLUMN public.label.id IS '流水號';
COMMENT ON COLUMN public.label."name" IS '標籤名稱(例如:寵物友善、24小時營業、專業認證)';
COMMENT ON COLUMN public.label.sort IS '排序';
COMMENT ON COLUMN public.label.is_enable IS '是否啟用:0->禁用；1->啟用';
COMMENT ON COLUMN public.label.is_deleted IS '刪除註記:0->未刪除；1->已刪除';
COMMENT ON COLUMN public.label.upd_time IS '異動日期時間';
COMMENT ON COLUMN public.label.cre_time IS '新增日期時間';


-- public.service_label definition

-- Drop table

-- DROP TABLE service_label;

CREATE TABLE service_label ( service_id int4 NOT NULL, label_id int4 NOT NULL, upd_time timestamptz NOT NULL, cre_time timestamptz NOT NULL, upd_id uuid NULL, cre_id uuid NOT NULL, CONSTRAINT service_label_pkey PRIMARY KEY (service_id, label_id));
CREATE INDEX idx_service_label_label_id ON public.service_label USING btree (label_id);
COMMENT ON TABLE public.service_label IS '服務與標籤對應檔(多對多關聯橋接表)';

-- Column comments

COMMENT ON COLUMN public.service_label.service_id IS '服務ID(對應cms_homepage_service.id)';
COMMENT ON COLUMN public.service_label.label_id IS '標籤ID(對應label.id)';
COMMENT ON COLUMN public.service_label.upd_time IS '異動日期時間';
COMMENT ON COLUMN public.service_label.cre_time IS '新增日期時間';


-- public.vendor_accounts definition

-- Drop table

-- DROP TABLE vendor_accounts;

CREATE TABLE vendor_accounts ( id uuid NOT NULL, service_vendor_id int4 NOT NULL, account varchar(100) NOT NULL, password_hash varchar(255) NOT NULL, contact_name bytea NULL, contact_name_hash varchar(50) NULL, contact_mobile bytea NULL, contact_mobile_hash varchar(50) NULL, contact_email bytea NULL, contact_email_hash varchar(50) NULL, is_2fa_enabled varchar(2) DEFAULT '0'::character varying NOT NULL, totp_secret varchar(255) NULL, last_login_time timestamptz NULL, is_enable varchar(2) NOT NULL, is_deleted varchar(2) NOT NULL, upd_time timestamptz NOT NULL, cre_time timestamptz NOT NULL, upd_id uuid NULL, cre_id uuid NOT NULL, CONSTRAINT vendor_accounts_pkey PRIMARY KEY (id), CONSTRAINT vendor_accounts_account_key UNIQUE (account));
CREATE INDEX idx_vendor_accounts_service_vendor_id ON public.vendor_accounts USING btree (service_vendor_id);
COMMENT ON TABLE public.vendor_accounts IS '服務商後台管理帳號檔(一個服務商可有多個管理帳號)';

-- Column comments

COMMENT ON COLUMN public.vendor_accounts.id IS '帳號ID(uuid)';
COMMENT ON COLUMN public.vendor_accounts.service_vendor_id IS '服務提供商ID(對應cms_homepage_service_vendor.id)';
COMMENT ON COLUMN public.vendor_accounts.account IS '登入帳號';
COMMENT ON COLUMN public.vendor_accounts.password_hash IS '密碼雜湊值(不可逆雜湊演算法儲存,如bcrypt/argon2)';
COMMENT ON COLUMN public.vendor_accounts.contact_name IS '聯絡人姓名(aes256 gcm加密)';
COMMENT ON COLUMN public.vendor_accounts.contact_name_hash IS '聯絡人姓名hash';
COMMENT ON COLUMN public.vendor_accounts.contact_mobile IS '聯絡人手機(aes256 gcm加密)';
COMMENT ON COLUMN public.vendor_accounts.contact_mobile_hash IS '聯絡人手機hash';
COMMENT ON COLUMN public.vendor_accounts.contact_email IS '聯絡人E-mail(aes256 gcm加密)';
COMMENT ON COLUMN public.vendor_accounts.contact_email_hash IS '聯絡人E-mail hash';
COMMENT ON COLUMN public.vendor_accounts.is_2fa_enabled IS '雙因子認證啟用:0->未啟用；1->已啟用';
COMMENT ON COLUMN public.vendor_accounts.totp_secret IS '雙因子認證密鑰(TOTP secret)';
COMMENT ON COLUMN public.vendor_accounts.last_login_time IS '最後登入時間';
COMMENT ON COLUMN public.vendor_accounts.is_enable IS '是否啟用:0->禁用；1->啟用';
COMMENT ON COLUMN public.vendor_accounts.is_deleted IS '刪除註記:0->未刪除；1->已刪除';
COMMENT ON COLUMN public.vendor_accounts.upd_time IS '異動日期時間';
COMMENT ON COLUMN public.vendor_accounts.cre_time IS '新增日期時間';


-- public.user_accounts definition

-- Drop table

-- DROP TABLE user_accounts;

CREATE TABLE user_accounts ( id uuid NOT NULL, account varchar(100) NOT NULL, password_hash varchar(255) NOT NULL, contact_name bytea NULL, contact_name_hash varchar(50) NULL, contact_mobile bytea NULL, contact_mobile_hash varchar(50) NULL, contact_email bytea NULL, contact_email_hash varchar(50) NULL, is_2fa_enabled varchar(2) DEFAULT '0'::character varying NOT NULL, totp_secret varchar(255) NULL, last_login_time timestamptz NULL, is_enable varchar(2) NOT NULL, is_deleted varchar(2) NOT NULL, upd_time timestamptz NOT NULL, cre_time timestamptz NOT NULL, upd_id uuid NULL, cre_id uuid NOT NULL, CONSTRAINT user_accounts_pkey PRIMARY KEY (id), CONSTRAINT user_accounts_account_key UNIQUE (account));
COMMENT ON TABLE public.user_accounts IS '會員(使用者)登入帳號檔，統一管理登入憑證，並透過id(即inbr_account_id)關聯訂單與諮詢回饋紀錄';

-- Column comments

COMMENT ON COLUMN public.user_accounts.id IS '會員編號(uuid，對應mms_order_record.inbr_account_id / pms_form_feedback.inbr_account_id)';
COMMENT ON COLUMN public.user_accounts.account IS '登入帳號';
COMMENT ON COLUMN public.user_accounts.password_hash IS '密碼雜湊值(不可逆雜湊演算法儲存,如bcrypt/argon2)';
COMMENT ON COLUMN public.user_accounts.contact_name IS '會員姓名(aes256 gcm加密)';
COMMENT ON COLUMN public.user_accounts.contact_name_hash IS '會員姓名hash';
COMMENT ON COLUMN public.user_accounts.contact_mobile IS '會員手機(aes256 gcm加密)';
COMMENT ON COLUMN public.user_accounts.contact_mobile_hash IS '會員手機hash';
COMMENT ON COLUMN public.user_accounts.contact_email IS '會員E-mail(aes256 gcm加密)';
COMMENT ON COLUMN public.user_accounts.contact_email_hash IS '會員E-mail hash';
COMMENT ON COLUMN public.user_accounts.is_2fa_enabled IS '雙因子認證啟用:0->未啟用；1->已啟用';
COMMENT ON COLUMN public.user_accounts.totp_secret IS '雙因子認證密鑰(TOTP secret)';
COMMENT ON COLUMN public.user_accounts.last_login_time IS '最後登入時間';
COMMENT ON COLUMN public.user_accounts.is_enable IS '是否啟用:0->禁用；1->啟用';
COMMENT ON COLUMN public.user_accounts.is_deleted IS '刪除註記:0->未刪除；1->已刪除';
COMMENT ON COLUMN public.user_accounts.upd_time IS '異動日期時間';
COMMENT ON COLUMN public.user_accounts.cre_time IS '新增日期時間';
