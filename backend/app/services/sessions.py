from datetime import datetime, timezone
import uuid

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import create_access_token
from app.models import User, UserSession


def issue_user_token(db: Session, user: User, *, ip: str | None = None) -> str:
    now = datetime.now(timezone.utc)
    row = UserSession(
        user_id=user.id,
        jti=uuid.uuid4().hex,
        last_ip=(ip or "")[:64] or None,
        created_at=now,
        last_seen_at=now,
    )
    db.add(row)
    db.flush()
    return create_access_token(
        str(user.id),
        {
            "role": user.role.value,
            "jti": row.jti,
            "tv": int(user.token_version or 0),
        },
    )


def assert_token_session(db: Session, user: User, payload: dict) -> None:
    tv = int(user.token_version or 0)
    try:
        token_tv = int(payload.get("tv") or 0)
    except (TypeError, ValueError):
        token_tv = 0
    if token_tv != tv:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Сессия сброшена. Войдите снова",
        )
    jti = str(payload.get("jti") or "").strip()
    if not jti:
        if tv == 0:
            return
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Сессия сброшена. Войдите снова")
    row = db.execute(
        select(UserSession).where(UserSession.jti == jti, UserSession.user_id == user.id)
    ).scalar_one_or_none()
    if not row or row.revoked_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Сессия сброшена. Войдите снова")


def bind_device_to_session(
    db: Session,
    user: User,
    *,
    jti: str | None,
    ip: str | None,
    device_id: str | None,
    device_brand: str | None,
    device_model: str | None,
    device_os: str | None,
    app_version: str | None,
    fcm_token: str | None,
) -> None:
    now = datetime.now(timezone.utc)
    row = None
    if jti:
        row = db.execute(
            select(UserSession).where(
                UserSession.jti == jti,
                UserSession.user_id == user.id,
                UserSession.revoked_at.is_(None),
            )
        ).scalar_one_or_none()
    if row is None and device_id:
        row = db.execute(
            select(UserSession)
            .where(
                UserSession.user_id == user.id,
                UserSession.device_id == device_id,
                UserSession.revoked_at.is_(None),
            )
            .order_by(UserSession.last_seen_at.desc())
        ).scalars().first()
    if row is None:
        return
    if device_id:
        row.device_id = device_id[:64]
    if device_brand is not None:
        row.device_brand = device_brand.strip() or None
    if device_model is not None:
        row.device_model = device_model.strip() or None
    if device_os is not None:
        row.device_os = device_os.strip() or None
    if app_version is not None:
        row.app_version = app_version.strip() or None
    if fcm_token is not None:
        row.fcm_token = fcm_token.strip() or None
    if ip:
        row.last_ip = ip[:64]
    row.last_seen_at = now


def revoke_all_sessions(db: Session, user: User, *, except_id: int | None = None) -> int:
    now = datetime.now(timezone.utc)
    rows = list(
        db.execute(
            select(UserSession).where(UserSession.user_id == user.id, UserSession.revoked_at.is_(None))
        ).scalars().all()
    )
    n = 0
    keep_fcm = None
    for row in rows:
        if except_id is not None and row.id == except_id:
            keep_fcm = row.fcm_token
            continue
        row.revoked_at = now
        n += 1
    if except_id is None:
        user.token_version = int(user.token_version or 0) + 1
        user.fcm_token = None
    else:
        user.fcm_token = keep_fcm
    return n


def revoke_session(db: Session, user: User, session_id: int) -> UserSession:
    row = db.execute(
        select(UserSession).where(UserSession.id == session_id, UserSession.user_id == user.id)
    ).scalar_one_or_none()
    if not row or row.revoked_at is not None:
        raise HTTPException(status_code=404, detail="Сессия не найдена")
    row.revoked_at = datetime.now(timezone.utc)
    if user.fcm_token and row.fcm_token and user.fcm_token == row.fcm_token:
        user.fcm_token = None
    return row
