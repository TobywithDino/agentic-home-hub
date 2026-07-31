# -*- coding: utf-8 -*-
"""
D/E. 會員帳號 / 服務商後台帳號 API（對應 API_Reference.md #30-40）
user_accounts, vendor_accounts

安全性提醒：
- 登入端點目前只做帳密核對並回傳識別碼，未簽發 JWT/Session token。
  正式串接後端應在此基礎上加上 Token 簽發與後續請求的驗證中介層，
  否則任何人拿到 inbr_account_id/service_vendor_id 就能呼叫其他端點存取該身分資料。
- 密碼一律使用 bcrypt 雜湊（不可逆），2FA 欄位保留但本階段未啟用相關流程。
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.crypto import decrypt_pii, encrypt_pii, sha256_hash
from app.database import get_db
from app.deps import PageParams, page_params
from app.models import UserAccount, VendorAccount
from app.schemas import (
    PagedResponse,
    UserLogin,
    UserLoginOut,
    UserOut,
    UserRegister,
    UserUpdate,
    VendorAccountOut,
    VendorAccountUpdate,
    VendorAccountRegister,
    VendorLogin,
    VendorLoginOut,
)
from app.security import hash_password, verify_password
from app.utils import SYSTEM_ACTOR_ID, now_utc, paginate, uuid7

router = APIRouter(tags=["accounts"])


# --- 輸出組裝（含PII解密） ----------------------------------------------------
def _build_user_out(obj: UserAccount) -> UserOut:
    return UserOut(
        id=obj.id, account=obj.account,
        contact_name=decrypt_pii(obj.contact_name), contact_name_hash=obj.contact_name_hash,
        contact_mobile=decrypt_pii(obj.contact_mobile), contact_mobile_hash=obj.contact_mobile_hash,
        contact_email=decrypt_pii(obj.contact_email), contact_email_hash=obj.contact_email_hash,
        is_2fa_enabled=obj.is_2fa_enabled, last_login_time=obj.last_login_time,
        is_enable=obj.is_enable, is_deleted=obj.is_deleted,
        upd_time=obj.upd_time, cre_time=obj.cre_time,
    )


def _build_vendor_account_out(obj: VendorAccount) -> VendorAccountOut:
    return VendorAccountOut(
        id=obj.id, service_vendor_id=obj.service_vendor_id, account=obj.account,
        contact_name=decrypt_pii(obj.contact_name), contact_name_hash=obj.contact_name_hash,
        contact_mobile=decrypt_pii(obj.contact_mobile), contact_mobile_hash=obj.contact_mobile_hash,
        contact_email=decrypt_pii(obj.contact_email), contact_email_hash=obj.contact_email_hash,
        is_2fa_enabled=obj.is_2fa_enabled, last_login_time=obj.last_login_time,
        is_enable=obj.is_enable, is_deleted=obj.is_deleted,
        upd_time=obj.upd_time, cre_time=obj.cre_time,
    )


# --- user_accounts -----------------------------------------------------------
@router.post("/auth/user/register", response_model=UserOut, status_code=201)
def register_user(payload: UserRegister, db: Session = Depends(get_db)):
    existing = db.execute(select(UserAccount).where(UserAccount.account == payload.account)).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=409, detail="帳號已被使用")
    now = now_utc()
    obj = UserAccount(
        id=uuid7(),
        account=payload.account,
        password_hash=hash_password(payload.password),
        contact_name=encrypt_pii(payload.contact_name),
        contact_name_hash=sha256_hash(payload.contact_name),
        contact_mobile=encrypt_pii(payload.contact_mobile),
        contact_mobile_hash=sha256_hash(payload.contact_mobile),
        contact_email=encrypt_pii(payload.contact_email),
        contact_email_hash=sha256_hash(payload.contact_email),
        is_2fa_enabled="0", totp_secret=None, last_login_time=None,
        is_enable="1", is_deleted="0",
        upd_time=now, cre_time=now, upd_id=None, cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return _build_user_out(obj)


@router.post("/auth/user/login", response_model=UserLoginOut)
def login_user(payload: UserLogin, db: Session = Depends(get_db)):
    """【圖1：登入】根據帳密，回傳 inbr_account_id 給 APP。最簡帳密驗證，不含2FA分支。"""
    obj = db.execute(select(UserAccount).where(UserAccount.account == payload.account)).scalar_one_or_none()
    if obj is None or obj.is_deleted == "1" or obj.is_enable != "1":
        raise HTTPException(status_code=401, detail="帳號或密碼錯誤")
    if not verify_password(payload.password, obj.password_hash):
        raise HTTPException(status_code=401, detail="帳號或密碼錯誤")
    obj.last_login_time = now_utc()
    db.commit()
    return UserLoginOut(inbr_account_id=obj.id)


@router.get("/users/{inbr_account_id}", response_model=UserOut)
def get_user(inbr_account_id: str, db: Session = Depends(get_db)):
    obj = db.get(UserAccount, inbr_account_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="會員不存在")
    return _build_user_out(obj)


@router.patch("/users/{inbr_account_id}", response_model=UserOut)
def update_user(inbr_account_id: str, payload: UserUpdate, db: Session = Depends(get_db)):
    """【圖1：設定會員資訊】更新聯絡方式/密碼。"""
    obj = db.get(UserAccount, inbr_account_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="會員不存在")
    data = payload.model_dump(exclude_unset=True)
    if "password" in data and data["password"] is not None:
        obj.password_hash = hash_password(data.pop("password"))
    else:
        data.pop("password", None)
    if "contact_name" in data:
        v = data.pop("contact_name")
        obj.contact_name = encrypt_pii(v)
        obj.contact_name_hash = sha256_hash(v)
    if "contact_mobile" in data:
        v = data.pop("contact_mobile")
        obj.contact_mobile = encrypt_pii(v)
        obj.contact_mobile_hash = sha256_hash(v)
    if "contact_email" in data:
        v = data.pop("contact_email")
        obj.contact_email = encrypt_pii(v)
        obj.contact_email_hash = sha256_hash(v)
    for field, value in data.items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return _build_user_out(obj)


@router.delete("/users/{inbr_account_id}", status_code=204)
def delete_user(inbr_account_id: str, db: Session = Depends(get_db)):
    obj = db.get(UserAccount, inbr_account_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="會員不存在")
    obj.is_deleted = "1"
    obj.upd_time = now_utc()
    db.commit()


# --- vendor_accounts -----------------------------------------------------------
@router.post("/auth/vendor/register", response_model=VendorAccountOut, status_code=201)
def register_vendor_account(payload: VendorAccountRegister, db: Session = Depends(get_db)):
    existing = db.execute(
        select(VendorAccount).where(VendorAccount.account == payload.account)
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=409, detail="帳號已被使用")
    now = now_utc()
    obj = VendorAccount(
        id=uuid7(),
        service_vendor_id=payload.service_vendor_id,
        account=payload.account,
        password_hash=hash_password(payload.password),
        contact_name=encrypt_pii(payload.contact_name),
        contact_name_hash=sha256_hash(payload.contact_name),
        contact_mobile=encrypt_pii(payload.contact_mobile),
        contact_mobile_hash=sha256_hash(payload.contact_mobile),
        contact_email=encrypt_pii(payload.contact_email),
        contact_email_hash=sha256_hash(payload.contact_email),
        is_2fa_enabled="0", totp_secret=None, last_login_time=None,
        is_enable="1", is_deleted="0",
        upd_time=now, cre_time=now, upd_id=None, cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return _build_vendor_account_out(obj)


@router.post("/auth/vendor/login", response_model=VendorLoginOut)
def login_vendor(payload: VendorLogin, db: Session = Depends(get_db)):
    """【圖2：登入】根據帳密，回傳 service_vendor_id 給後台。最簡帳密驗證，不含2FA分支。"""
    obj = db.execute(select(VendorAccount).where(VendorAccount.account == payload.account)).scalar_one_or_none()
    if obj is None or obj.is_deleted == "1" or obj.is_enable != "1":
        raise HTTPException(status_code=401, detail="帳號或密碼錯誤")
    if not verify_password(payload.password, obj.password_hash):
        raise HTTPException(status_code=401, detail="帳號或密碼錯誤")
    obj.last_login_time = now_utc()
    db.commit()
    return VendorLoginOut(service_vendor_id=obj.service_vendor_id, account_id=obj.id)


@router.get("/vendors/{service_vendor_id}/accounts", response_model=PagedResponse)
def list_vendor_accounts(
    service_vendor_id: int, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    stmt = (
        select(VendorAccount)
        .where(VendorAccount.service_vendor_id == service_vendor_id)
        .order_by(VendorAccount.cre_time)
    )
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[_build_vendor_account_out(i) for i in items])


@router.get("/vendors/{service_vendor_id}/accounts/{account_id}", response_model=VendorAccountOut)
def get_vendor_account(service_vendor_id: int, account_id: str, db: Session = Depends(get_db)):
    obj = db.get(VendorAccount, account_id)
    if obj is None or obj.service_vendor_id != service_vendor_id:
        raise HTTPException(status_code=404, detail="帳號不存在")
    return _build_vendor_account_out(obj)


@router.patch("/vendors/{service_vendor_id}/accounts/{account_id}", response_model=VendorAccountOut)
def update_vendor_account(
    service_vendor_id: int, account_id: str, payload: VendorAccountUpdate, db: Session = Depends(get_db)
):
    """【圖2：設定商家資訊-聯絡方式部分】更新該帳號聯絡方式/密碼。"""
    obj = db.get(VendorAccount, account_id)
    if obj is None or obj.service_vendor_id != service_vendor_id:
        raise HTTPException(status_code=404, detail="帳號不存在")
    data = payload.model_dump(exclude_unset=True)
    if "password" in data and data["password"] is not None:
        obj.password_hash = hash_password(data.pop("password"))
    else:
        data.pop("password", None)
    if "contact_name" in data:
        v = data.pop("contact_name")
        obj.contact_name = encrypt_pii(v)
        obj.contact_name_hash = sha256_hash(v)
    if "contact_mobile" in data:
        v = data.pop("contact_mobile")
        obj.contact_mobile = encrypt_pii(v)
        obj.contact_mobile_hash = sha256_hash(v)
    if "contact_email" in data:
        v = data.pop("contact_email")
        obj.contact_email = encrypt_pii(v)
        obj.contact_email_hash = sha256_hash(v)
    for field, value in data.items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return _build_vendor_account_out(obj)


@router.delete("/vendors/{service_vendor_id}/accounts/{account_id}", status_code=204)
def delete_vendor_account(service_vendor_id: int, account_id: str, db: Session = Depends(get_db)):
    obj = db.get(VendorAccount, account_id)
    if obj is None or obj.service_vendor_id != service_vendor_id:
        raise HTTPException(status_code=404, detail="帳號不存在")
    obj.is_deleted = "1"
    obj.upd_time = now_utc()
    db.commit()
