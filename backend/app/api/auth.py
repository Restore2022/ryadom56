from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import logging
from pathlib import Path
import secrets

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user, security
from app.core.config import settings
from app.core.database import get_db
from app.core.security import decode_access_token, hash_password, verify_password
from app.models import Listing, ListingReport, ListingStatus, PasswordReset, Settlement, User, UserSession
from app.schemas import (
    DeviceInfoIn,
    ForgotPasswordIn,
    LoginIn,
    MessageOut,
    ProfileUpdateIn,
    PublicUserOut,
    RegisterIn,
    ResetPasswordIn,
    VerifyPasswordIn,
    SessionOut,
    TokenOut,
    UserOut,
)
from app.services.mail import MailNotConfigured, MailSendError, mail_configured, send_email
from app.services.rate_limit import limiter
from app.services.sessions import bind_device_to_session, issue_user_token, revoke_all_sessions, revoke_session

logger = logging.getLogger(__name__)

_RESET_OK = "Если такой email есть в системе, мы отправили код на почту"

router = APIRouter(prefix="/auth", tags=["auth"])


def avatar_url_for(path: str | None) -> str | None:
    if not path:
        return None
    return f"/uploads/{path.replace(chr(92), '/')}"


def enrich_user_out(db: Session, user: User) -> UserOut:
    listings_count = int(
        db.execute(
            select(func.count(Listing.id)).where(
                Listing.author_id == user.id,
                Listing.status == ListingStatus.approved,
            )
        ).scalar_one()
    )
    reports_against = int(
        db.execute(
            select(func.count(ListingReport.id))
            .join(Listing, Listing.id == ListingReport.listing_id)
            .where(
                Listing.author_id == user.id,
                ListingReport.status.in_(["open", "reviewed"]),
            )
        ).scalar_one()
    )
    data = UserOut.model_validate(user)
    data.listings_count = listings_count
    data.reports_against = reports_against
    data.avatar_url = avatar_url_for(user.avatar_path)
    return data


def client_ip(request: Request) -> str | None:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()[:64]
    if request.client:
        return (request.client.host or "")[:64] or None
    return None


def touch_user(user: User, request: Request, device: DeviceInfoIn | None = None) -> None:
    user.last_ip = client_ip(request)
    user.last_seen_at = datetime.now(timezone.utc)
    if device:
        if device.device_brand is not None:
            user.device_brand = device.device_brand.strip() or None
        if device.device_model is not None:
            user.device_model = device.device_model.strip() or None
        if device.device_os is not None:
            user.device_os = device.device_os.strip() or None
        if device.app_version is not None:
            user.app_version = device.app_version.strip() or None
        if device.device_info is not None:
            user.device_info = device.device_info.strip() or None
        if device.fcm_token is not None:
            user.fcm_token = device.fcm_token.strip() or None


@router.post("/register", response_model=TokenOut)
def register(payload: RegisterIn, request: Request, db: Session = Depends(get_db)):
    ip = client_ip(request) or "unknown"
    if not limiter.allow(f"register:{ip}", limit=8, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много регистраций с этого адреса. Попробуйте позже")
    if not (payload.accepted_terms and payload.accepted_privacy and payload.accepted_listing_rules):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Нужно принять пользовательское соглашение, политику и правила объявлений",
        )
    exists = db.execute(select(User).where(User.email == payload.email.lower())).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=400, detail="Email уже зарегистрирован")
    settlement = db.execute(select(Settlement).where(Settlement.id == payload.settlement_id)).scalar_one_or_none()
    if not settlement:
        raise HTTPException(status_code=400, detail="Населённый пункт не найден")

    user = User(
        email=payload.email.lower(),
        password_hash=hash_password(payload.password),
        full_name=payload.full_name.strip(),
        phone=payload.phone.strip() if payload.phone else None,
        settlement_id=payload.settlement_id,
        accepted_terms=True,
    )
    touch_user(user, request)
    db.add(user)
    db.commit()
    db.refresh(user)
    token = issue_user_token(db, user, ip=client_ip(request))
    db.commit()
    return TokenOut(access_token=token)


@router.post("/login", response_model=TokenOut)
def login(payload: LoginIn, request: Request, db: Session = Depends(get_db)):
    ip = client_ip(request) or "unknown"
    if not limiter.allow(f"login:{ip}", limit=40, window_sec=600):
        raise HTTPException(status_code=429, detail="Слишком много попыток входа. Подождите")
    user = db.execute(select(User).where(User.email == payload.email.lower())).scalar_one_or_none()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Неверный email или пароль")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Аккаунт заблокирован")
    touch_user(user, request)
    token = issue_user_token(db, user, ip=client_ip(request))
    db.commit()
    return TokenOut(access_token=token)


@router.post("/verify-password", response_model=MessageOut)
def verify_account_password(
    payload: VerifyPasswordIn,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    ip = client_ip(request) or "unknown"
    if not limiter.allow(f"verify-pass:{user.id}:{ip}", limit=12, window_sec=600):
        raise HTTPException(status_code=429, detail="Слишком много попыток. Подождите")
    db_user = db.get(User, user.id)
    if not db_user or not verify_password(payload.password, db_user.password_hash):
        raise HTTPException(status_code=400, detail="Неверный пароль")
    return MessageOut(message="Пароль подтверждён")


def _reset_code_hash(email: str, code: str) -> str:
    raw = f"{email.lower().strip()}:{code}".encode("utf-8")
    return hmac.new(settings.secret_key.encode("utf-8"), raw, hashlib.sha256).hexdigest()


def _password_reset_email(code: str, minutes: int) -> tuple[str, str, str]:
    subject = "Код для смены пароля — Рядом56"
    text = (
        f"Здравствуйте!\n\n"
        f"Код для восстановления пароля в Рядом56: {code}\n\n"
        f"Код действует {minutes} минут. Если вы не запрашивали смену пароля, просто проигнорируйте это письмо.\n"
    )
    html = f"""
    <div style="font-family:Arial,sans-serif;line-height:1.5;color:#132016">
      <p>Здравствуйте!</p>
      <p>Код для восстановления пароля в <strong>Рядом56</strong>:</p>
      <p style="font-size:28px;letter-spacing:6px;font-weight:700">{code}</p>
      <p>Код действует {minutes} минут. Если вы не запрашивали смену пароля, просто проигнорируйте это письмо.</p>
    </div>
    """
    return subject, text, html


@router.post("/forgot-password", response_model=MessageOut)
def forgot_password(payload: ForgotPasswordIn, request: Request, db: Session = Depends(get_db)):
    ip = client_ip(request) or "unknown"
    email = payload.email.lower().strip()
    if not limiter.allow(f"forgot-ip:{ip}", limit=8, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много запросов. Подождите час")
    if not limiter.allow(f"forgot-email:{email}", limit=5, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много запросов на этот email. Подождите")
    if not mail_configured():
        logger.warning("forgot-password: SMTP is not configured")
        raise HTTPException(status_code=503, detail="Восстановление пароля временно недоступно")

    user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if not user or not user.is_active:
        return MessageOut(message=_RESET_OK)

    now = datetime.now(timezone.utc)
    pending = db.execute(
        select(PasswordReset).where(
            PasswordReset.user_id == user.id,
            PasswordReset.used_at.is_(None),
        )
    ).scalars().all()
    for row in pending:
        row.used_at = now

    code = f"{secrets.randbelow(1_000_000):06d}"
    ttl = max(5, int(settings.password_reset_ttl_minutes or 20))
    item = PasswordReset(
        user_id=user.id,
        email=email,
        code_hash=_reset_code_hash(email, code),
        attempts=0,
        expires_at=now + timedelta(minutes=ttl),
        created_ip=ip[:64],
    )
    db.add(item)
    db.flush()
    subject, text, html = _password_reset_email(code, ttl)
    try:
        send_email(to=email, subject=subject, text=text, html=html)
    except MailNotConfigured:
        db.rollback()
        raise HTTPException(status_code=503, detail="Восстановление пароля временно недоступно")
    except MailSendError:
        db.rollback()
        raise HTTPException(status_code=503, detail="Не удалось отправить письмо. Попробуйте позже")
    db.commit()
    return MessageOut(message=_RESET_OK)


@router.post("/reset-password", response_model=MessageOut)
def reset_password(payload: ResetPasswordIn, request: Request, db: Session = Depends(get_db)):
    ip = client_ip(request) or "unknown"
    if not limiter.allow(f"reset-ip:{ip}", limit=20, window_sec=600):
        raise HTTPException(status_code=429, detail="Слишком много попыток. Подождите")
    email = payload.email.lower().strip()
    code = payload.code.strip()
    user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if not user or not user.is_active:
        raise HTTPException(status_code=400, detail="Неверный код или срок действия истёк")

    now = datetime.now(timezone.utc)
    row = db.execute(
        select(PasswordReset)
        .where(
            PasswordReset.user_id == user.id,
            PasswordReset.used_at.is_(None),
            PasswordReset.expires_at > now,
        )
        .order_by(PasswordReset.created_at.desc())
    ).scalars().first()
    if not row:
        raise HTTPException(status_code=400, detail="Неверный код или срок действия истёк")
    if row.attempts >= 5:
        row.used_at = now
        db.commit()
        raise HTTPException(status_code=400, detail="Слишком много попыток. Запросите код снова")

    expected = _reset_code_hash(email, code)
    if not hmac.compare_digest(row.code_hash, expected):
        row.attempts += 1
        db.commit()
        left = max(0, 5 - row.attempts)
        raise HTTPException(status_code=400, detail=f"Неверный код. Осталось попыток: {left}")

    user.password_hash = hash_password(payload.password)
    row.used_at = now
    revoke_all_sessions(db, user)
    db.commit()
    return MessageOut(message="Пароль обновлён. Войдите с новым паролем")


@router.get("/me", response_model=UserOut)
def me(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    return enrich_user_out(db, db_user)


@router.get("/users/{user_id}/public", response_model=PublicUserOut)
def public_profile(user_id: int, db: Session = Depends(get_db)):
    u = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user_id)
    ).scalar_one_or_none()
    if not u or not u.is_active:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    listings_count = int(
        db.execute(
            select(func.count(Listing.id)).where(
                Listing.author_id == u.id,
                Listing.status == ListingStatus.approved,
            )
        ).scalar_one()
    )
    reports_against = int(
        db.execute(
            select(func.count(ListingReport.id))
            .join(Listing, Listing.id == ListingReport.listing_id)
            .where(
                Listing.author_id == u.id,
                ListingReport.status.in_(["open", "reviewed"]),
            )
        ).scalar_one()
    )
    return PublicUserOut(
        id=u.id,
        full_name=u.full_name,
        settlement_name=u.settlement.display_name if u.settlement else None,
        badge=u.badge,
        rating_score=u.rating_score,
        listings_count=listings_count,
        reports_against=reports_against,
        member_since=u.created_at,
        is_active=u.is_active,
        avatar_url=avatar_url_for(u.avatar_path),
    )


@router.patch("/me", response_model=UserOut)
def update_me(
    payload: ProfileUpdateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    creds: HTTPAuthorizationCredentials | None = Depends(security),
):
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    data = payload.model_dump(exclude_unset=True)
    if "password" in data and data["password"]:
        if not payload.current_password or not verify_password(payload.current_password, db_user.password_hash):
            raise HTTPException(status_code=400, detail="Неверный текущий пароль")
        db_user.password_hash = hash_password(data.pop("password"))
        # смена пароля выкидывает остальные телефоны, текущий остаётся
        current = _session_by_creds(db, db_user.id, creds)
        revoke_all_sessions(db, db_user, except_id=current.id if current else None)
    data.pop("current_password", None)
    if "settlement_id" in data and data["settlement_id"] is not None:
        settlement = db.execute(select(Settlement).where(Settlement.id == data["settlement_id"])).scalar_one_or_none()
        if not settlement:
            raise HTTPException(status_code=400, detail="Населённый пункт не найден")
    if "full_name" in data and data["full_name"]:
        db_user.full_name = data["full_name"].strip()
    if "phone" in data:
        phone = data["phone"]
        db_user.phone = phone.strip() if phone else None
    if "settlement_id" in data and data["settlement_id"] is not None:
        db_user.settlement_id = data["settlement_id"]
    db.commit()
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    return enrich_user_out(db, db_user)


AVATAR_ROOT = Path("data/uploads/avatars")
MAX_AVATAR_BYTES = 6 * 1024 * 1024
_AVATAR_TYPES = {"image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png", "image/webp": ".webp"}


@router.post("/me/avatar", response_model=UserOut)
async def upload_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="Пустой файл")
    if len(raw) > MAX_AVATAR_BYTES:
        raise HTTPException(status_code=400, detail="Фото больше 6 МБ")
    ext = _AVATAR_TYPES.get((file.content_type or "").lower())
    if raw[:3] == b"\xff\xd8\xff":
        ext = ".jpg"
    elif raw[:8] == b"\x89PNG\r\n\x1a\n":
        ext = ".png"
    elif len(raw) >= 12 and raw[:4] == b"RIFF" and raw[8:12] == b"WEBP":
        ext = ".webp"
    elif not ext:
        raise HTTPException(status_code=400, detail="Допустимы JPG, PNG, WEBP")
    AVATAR_ROOT.mkdir(parents=True, exist_ok=True)
    name = f"{user.id}_{secrets.token_hex(8)}{ext}"
    rel = f"avatars/{name}"
    (AVATAR_ROOT / name).write_bytes(raw)
    if db_user.avatar_path:
        old = Path("data/uploads") / db_user.avatar_path
        if old.is_file() and old.resolve().parent == AVATAR_ROOT.resolve():
            old.unlink(missing_ok=True)
    db_user.avatar_path = rel
    db.commit()
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    return enrich_user_out(db, db_user)


@router.delete("/me/avatar", response_model=UserOut)
def delete_avatar(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    if db_user.avatar_path:
        old = Path("data/uploads") / db_user.avatar_path
        if old.is_file() and old.resolve().parent == (Path("data/uploads") / "avatars").resolve():
            old.unlink(missing_ok=True)
    db_user.avatar_path = None
    db.commit()
    return enrich_user_out(db, db_user)


def _payload_from_creds(creds: HTTPAuthorizationCredentials | None) -> dict:
    if not creds:
        return {}
    return decode_access_token(creds.credentials) or {}


def _session_by_creds(db: Session, user_id: int, creds: HTTPAuthorizationCredentials | None) -> UserSession | None:
    jti = str(_payload_from_creds(creds).get("jti") or "").strip()
    if not jti:
        return None
    return db.execute(
        select(UserSession).where(
            UserSession.jti == jti,
            UserSession.user_id == user_id,
            UserSession.revoked_at.is_(None),
        )
    ).scalar_one_or_none()


@router.post("/device", response_model=UserOut)
def report_device(
    payload: DeviceInfoIn,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    creds: HTTPAuthorizationCredentials | None = Depends(security),
):
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    touch_user(db_user, request, payload)
    bind_device_to_session(
        db,
        db_user,
        jti=str(_payload_from_creds(creds).get("jti") or "").strip() or None,
        ip=client_ip(request),
        device_id=(payload.device_id or "").strip() or None,
        device_brand=payload.device_brand,
        device_model=payload.device_model,
        device_os=payload.device_os,
        app_version=payload.app_version,
        fcm_token=payload.fcm_token,
    )
    db.commit()
    db.refresh(db_user)
    return enrich_user_out(db, db_user)


@router.get("/sessions", response_model=list[SessionOut])
def list_sessions(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    creds: HTTPAuthorizationCredentials | None = Depends(security),
):
    current_jti = str(_payload_from_creds(creds).get("jti") or "").strip()
    rows = db.execute(
        select(UserSession)
        .where(UserSession.user_id == user.id, UserSession.revoked_at.is_(None))
        .order_by(UserSession.last_seen_at.desc(), UserSession.id.desc())
    ).scalars().all()
    out: list[SessionOut] = []
    for row in rows:
        item = SessionOut.model_validate(row)
        item.is_current = bool(current_jti and row.jti == current_jti)
        out.append(item)
    return out


@router.post("/sessions/revoke-all", response_model=MessageOut)
def sessions_revoke_all(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    n = revoke_all_sessions(db, user)
    db.commit()
    return MessageOut(message=f"Выполнен выход на всех устройствах ({n})")


@router.post("/sessions/revoke-others", response_model=MessageOut)
def sessions_revoke_others(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    creds: HTTPAuthorizationCredentials | None = Depends(security),
):
    current = _session_by_creds(db, user.id, creds)
    n = revoke_all_sessions(db, user, except_id=current.id if current else None)
    db.commit()
    return MessageOut(message=f"Выполнен выход на других устройствах ({n})")


@router.delete("/sessions/{session_id}", response_model=MessageOut)
def sessions_revoke_one(
    session_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    revoke_session(db, user, session_id)
    db.commit()
    return MessageOut(message="Устройство отключено")
