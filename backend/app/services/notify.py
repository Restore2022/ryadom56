from datetime import datetime, timedelta, timezone
import json
import logging
import time
import urllib.error
import urllib.request
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Notification, User, UserSession, GuestPushDevice

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
    ride_id: int | None = None,
    extra: dict | None = None,
) -> Notification:
    item = Notification(
        user_id=user_id,
        type=type,
        title=title,
        body=body,
        listing_id=listing_id,
        ride_id=ride_id,
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
    if ride_id is not None:
        data["ride_id"] = str(ride_id)
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


def guest_push_tokens(
    db: Session,
    *,
    exclude: set[str] | None = None,
    settlement_ids: list[int] | None = None,
) -> list[str]:
    """Токены гостей без входа — только общие рассылки."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=90)
    stmt = select(GuestPushDevice.fcm_token).where(
        GuestPushDevice.last_seen_at >= cutoff,
        GuestPushDevice.fcm_token.is_not(None),
        GuestPushDevice.fcm_token != "",
    )
    if settlement_ids:
        stmt = stmt.where(GuestPushDevice.settlement_id.in_(settlement_ids))
    rows = db.execute(stmt).scalars().all()
    skip = exclude or set()
    tokens: list[str] = []
    for raw in rows:
        t = (raw or "").strip()
        if t and t not in skip:
            tokens.append(t)
    return list(dict.fromkeys(tokens))


def push_tokens(
    tokens: list[str],
    *,
    title: str,
    body: str,
    data: dict,
    channel_id: str = "ryadom56_alerts",
) -> int:
    return _fcm_send_many(tokens, title=title, body=body, data=data, channel_id=channel_id)


def drop_guest_push_device(db: Session, device_id: str | None) -> None:
    did = (device_id or "").strip()
    if not did:
        return
    row = db.execute(select(GuestPushDevice).where(GuestPushDevice.device_id == did)).scalar_one_or_none()
    if row:
        db.delete(row)


def broadcast_audience(
    db: Session,
    *,
    settlement_ids: list[int] | None = None,
) -> tuple[list[User], list[str], list[str]]:
    """Активные аккаунты, их токены и гостевые токены без дублей."""
    stmt = select(User).where(User.is_active.is_(True))
    if settlement_ids:
        stmt = stmt.where(User.settlement_id.in_(settlement_ids))
    users = db.execute(stmt).scalars().all()
    user_tokens: list[str] = []
    for user in users:
        t = (user.fcm_token or "").strip()
        if t:
            user_tokens.append(t)
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
                user_tokens.append(t)
    user_tokens = list(dict.fromkeys(user_tokens))
    guest_tokens = guest_push_tokens(
        db,
        exclude=set(user_tokens),
        settlement_ids=settlement_ids,
    )
    return users, user_tokens, guest_tokens


def notify_broadcast(
    db: Session,
    *,
    type: str,
    title: str,
    body: str | None = None,
    listing_id: int | None = None,
    extra: dict | None = None,
    only_with_push: bool = False,
    audience: str = "all",
    settlement_ids: list[int] | None = None,
) -> tuple[int, int]:
    """Создаёт in-app уведомления и шлёт FCM. audience: all | users | guests."""
    target = (audience or "all").strip().lower()
    if target not in ("all", "users", "guests"):
        target = "all"
    users, user_tokens, guest_tokens = broadcast_audience(db, settlement_ids=settlement_ids)
    created = 0
    if target in ("all", "users"):
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
        db.flush()
    push_tokens: list[str] = []
    if target in ("all", "users"):
        push_tokens.extend(user_tokens)
    if target in ("all", "guests"):
        push_tokens.extend(guest_tokens)
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
    sent = _fcm_send_many(list(dict.fromkeys(push_tokens)), title=title, body=body or "", data=data)
    return created, sent


def _try_push(
    db: Session,
    *,
    user_id: int,
    title: str,
    body: str,
    data: dict | None = None,
    channel_id: str | None = None,
) -> int:
    tokens = fcm_tokens_for_user(db, user_id)
    if not tokens:
        return 0
    return _fcm_send_many(
        tokens, title=title, body=body, data=data or {}, channel_id=channel_id or "ryadom56_alerts"
    )


def push_user(
    db: Session,
    *,
    user_id: int,
    title: str,
    body: str,
    data: dict | None = None,
    channel_id: str | None = None,
) -> int:
    """FCM без записи в колокольчик — для входящего звонка."""
    return _try_push(db, user_id=user_id, title=title, body=body, data=data, channel_id=channel_id)


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


def _fcm_send_many(
    tokens: list[str], *, title: str, body: str, data: dict, channel_id: str = "ryadom56_alerts"
) -> int:
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
                        "channel_id": channel_id or "ryadom56_alerts",
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
