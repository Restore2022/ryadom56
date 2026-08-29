import hashlib
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.auth import client_ip
from app.api.deps import get_optional_user
from app.core.database import get_db
from app.models import Presence, User
from app.schemas import MessageOut
from app.services.rate_limit import limiter

router = APIRouter(prefix="/presence", tags=["presence"])


class PresenceIn(BaseModel):
    source: str = Field(pattern="^(app|site)$")
    client_id: str = Field(min_length=8, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")


def client_key(source: str, client_id: str) -> str:
    raw = f"{source}:{client_id.strip().lower()}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:48]


@router.post("/ping", response_model=MessageOut)
def ping(
    payload: PresenceIn,
    request: Request,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    ip = client_ip(request) or "unknown"
    key = client_key(payload.source, payload.client_id)
    if not limiter.allow(f"presence:{key}", limit=8, window_sec=60):
        return MessageOut(message="ok")
    if not limiter.allow(f"presence-ip:{ip}", limit=180, window_sec=3600):
        return MessageOut(message="ok")

    now = datetime.now(timezone.utc)
    row = db.execute(select(Presence).where(Presence.client_key == key)).scalar_one_or_none()
    if row is None:
        row = Presence(
            client_key=key,
            source=payload.source,
            user_id=user.id if user else None,
            first_seen_at=now,
            last_seen_at=now,
        )
        db.add(row)
    else:
        row.last_seen_at = now
        row.user_id = user.id if user else None

    if limiter.allow("presence-gc", limit=1, window_sec=3600):
        cutoff = now - timedelta(days=40)
        db.execute(delete(Presence).where(Presence.last_seen_at < cutoff))

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        row = db.execute(select(Presence).where(Presence.client_key == key)).scalar_one_or_none()
        if row is not None:
            row.last_seen_at = now
            row.user_id = user.id if user else None
            db.commit()

    return MessageOut(message="ok")
