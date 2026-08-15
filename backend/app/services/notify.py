import json
import logging
import time
import urllib.error
import urllib.request
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Notification, User, UserSession

logger = logging.getLogger(__name__)

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_cached_token: str | None = None
_cached_token_exp: float = 0.0


def notify_user(
    db: Session,
    *,
    user_id: int,
    type: str,
    title: str,
    body: str | None = None,
    listing_id: int | None = None,
    extra: dict | None = None,
) -> Notification:
    item = Notification(
        user_id=user_id,
        type=type,
        title=title,
        body=body,
        listing_id=listing_id,
        is_read=False,
    )
    db.add(item)
    db.flush()
    data = {
        "type": type,
        "notification_id": str(item.id),
        "click_action": "FLUTTER_NOTIFICATION_CLICK",
    }
    if listing_id is not None:
        data["listing_id"] = str(listing_id)
    if extra:
        for k, v in extra.items():
            if v is None:
                continue
            data[str(k)] = str(v)
    _try_push(db, user_id=user_id, title=title, body=body or "", data=data)
    return item


def fcm_tokens_for_user(db: Session, user_id: int) -> list[str]:
    """Токены с профиля и активных сессий — пуш на все телефоны человека."""
    tokens: list[str] = []
    user = db.get(User, user_id)
    if user:
        t = (user.fcm_token or "").strip()
        if t:
            tokens.append(t)
    rows = db.execute(
        select(UserSession.fcm_token).where(
            UserSession.user_id == user_id,
            UserSession.revoked_at.is_(None),
            UserSession.fcm_token.is_not(None),
            UserSession.fcm_token != "",
        )
    ).scalars().all()
    for raw in rows:
        t = (raw or "").strip()
        if t:
            tokens.append(t)
    return list(dict.fromkeys(tokens))


def notify_broadcast(
    db: Session,
    *,
    type: str,
    title: str,
    body: str | None = None,
    listing_id: int | None = None,
    extra: dict | None = None,
    only_with_push: bool = False,
) -> int:
    """Создаёт in-app уведомления и шлёт FCM всем активным пользователям."""
    stmt = select(User).where(User.is_active.is_(True))
    if only_with_push:
        stmt = stmt.where(User.fcm_token.is_not(None), User.fcm_token != "")
    users = db.execute(stmt).scalars().all()
    created = 0
    tokens: list[str] = []
    for user in users:
        db.add(
            Notification(
                user_id=user.id,
                type=type,
                title=title,
                body=body,
                listing_id=listing_id,
                is_read=False,
            )
        )
        created += 1
        token = (user.fcm_token or "").strip()
        if token:
            tokens.append(token)
    if users:
        session_tokens = db.execute(
            select(UserSession.fcm_token).where(
                UserSession.user_id.in_([u.id for u in users]),
                UserSession.revoked_at.is_(None),
                UserSession.fcm_token.is_not(None),
                UserSession.fcm_token != "",
            )
        ).scalars().all()
        for raw in session_tokens:
            t = (raw or "").strip()
            if t:
                tokens.append(t)
    db.flush()
    data = {
        "type": type,
        "click_action": "FLUTTER_NOTIFICATION_CLICK",
    }
    if listing_id is not None:
        data["listing_id"] = str(listing_id)
    if extra:
        for k, v in extra.items():
            if v is None:
                continue
            data[str(k)] = str(v)
    _fcm_send_many(tokens, title=title, body=body or "", data=data)
    return created


def _try_push(
    db: Session,
    *,
    user_id: int,
    title: str,
    body: str,
    data: dict | None = None,
) -> int:
    tokens = fcm_tokens_for_user(db, user_id)
    if not tokens:
        return 0
    return _fcm_send_many(tokens, title=title, body=body, data=data or {})


def _service_account_path() -> Path | None:
    raw = (settings.fcm_service_account_file or "").strip()
    if not raw:
        # удобный дефолт на VPS
        candidates = [
            Path("data/firebase-service-account.json"),
            Path("/opt/ryadom56/backend/data/firebase-service-account.json"),
        ]
        for p in candidates:
            if p.is_file():
                return p
        return None
    p = Path(raw)
    return p if p.is_file() else None


def _fcm_access_token() -> str | None:
    global _cached_token, _cached_token_exp
    now = time.time()
    if _cached_token and now < _cached_token_exp - 60:
        return _cached_token
    path = _service_account_path()
    if not path:
        logger.warning("FCM v1: service account JSON not found — set FCM_SERVICE_ACCOUNT_FILE")
        return None
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
    except ImportError:
        logger.warning("FCM v1: install google-auth and requests")
        return None
    creds = service_account.Credentials.from_service_account_file(
        str(path),
        scopes=[_FCM_SCOPE],
    )
    creds.refresh(Request())
    _cached_token = creds.token
    # типичный TTL ~3600с
    _cached_token_exp = now + 3500
    return _cached_token


def _fcm_project_id() -> str:
    pid = (settings.fcm_project_id or "").strip()
    if pid:
        return pid
    path = _service_account_path()
    if path:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return str(data.get("project_id") or "ryadom56")
        except Exception:
            pass
    return "ryadom56"


def _fcm_send_many(tokens: list[str], *, title: str, body: str, data: dict) -> int:
    if not tokens:
        return 0
    access = _fcm_access_token()
    if not access:
        return 0
    project = _fcm_project_id()
    url = f"https://fcm.googleapis.com/v1/projects/{project}/messages:send"
    unique = list(dict.fromkeys(tokens))
    ok = 0
    for token in unique:
        payload = {
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                "data": {str(k): str(v) for k, v in data.items()},
                "android": {
                    "priority": "HIGH",
                    "notification": {
                        "channel_id": "ryadom56_alerts",
                        "sound": "default",
                        "click_action": "FLUTTER_NOTIFICATION_CLICK",
                    },
                },
            }
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {access}",
                "Content-Type": "application/json; charset=UTF-8",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
                resp.read()
                ok += 1
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", "replace")[:400]
            logger.warning("FCM v1 HTTP %s token=…%s: %s", exc.code, token[-8:], err_body)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            logger.warning("FCM v1 failed token=…%s: %s", token[-8:], exc)
    logger.info("FCM v1 sent ok=%s / %s", ok, len(unique))
    return ok
