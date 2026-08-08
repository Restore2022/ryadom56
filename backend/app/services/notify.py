import json
import logging
import urllib.error
import urllib.request

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Notification, User

logger = logging.getLogger(__name__)


def notify_user(
    db: Session,
    *,
    user_id: int,
    type: str,
    title: str,
    body: str | None = None,
    listing_id: int | None = None,
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
    _try_push(db, user_id=user_id, title=title, body=body or "")
    return item


def _try_push(db: Session, *, user_id: int, title: str, body: str) -> None:
    key = (settings.fcm_server_key or "").strip()
    if not key:
        return
    user = db.get(User, user_id)
    token = (getattr(user, "fcm_token", None) or "").strip() if user else ""
    if not token:
        return
    payload = {
        "to": token,
        "notification": {"title": title, "body": body},
        "data": {"click_action": "FLUTTER_NOTIFICATION_CLICK"},
        "priority": "high",
    }
    req = urllib.request.Request(
        "https://fcm.googleapis.com/fcm/send",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"key={key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            resp.read()
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        logger.warning("FCM push failed for user %s: %s", user_id, exc)
