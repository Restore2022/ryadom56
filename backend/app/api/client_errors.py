from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import delete, or_, select
from sqlalchemy.orm import Session

from app.api.deps import get_optional_user
from app.core.database import get_db
from app.models import ClientErrorLog, User
from app.schemas import ClientErrorIn, MessageOut
from app.services.rate_limit import limiter

router = APIRouter(prefix="/client-errors", tags=["client-errors"])

_KEEP = 2000


def _client_ip(request: Request) -> str | None:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()[:64]
    if request.client:
        return (request.client.host or "")[:64] or None
    return None


@router.post("", response_model=MessageOut)
def report_client_error(
    payload: ClientErrorIn,
    request: Request,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    ip = _client_ip(request) or "unknown"
    if not limiter.allow(f"cerr-ip:{ip}", limit=30, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много отчётов")
    row = ClientErrorLog(
        user_id=user.id if user else None,
        message=payload.message.strip()[:500],
        stack=(payload.stack or "")[:8000] or None,
        screen=(payload.screen or "")[:120] or None,
        app_version=(payload.app_version or "")[:40] or None,
        device_brand=(payload.device_brand or "")[:80] or None,
        device_model=(payload.device_model or "")[:120] or None,
        device_os=(payload.device_os or "")[:80] or None,
        client_ip=ip[:64],
    )
    db.add(row)
    extra = db.execute(select(ClientErrorLog.id).order_by(ClientErrorLog.id.desc()).offset(_KEEP)).scalars().all()
    if extra:
        db.execute(delete(ClientErrorLog).where(ClientErrorLog.id.in_(extra)))
    db.commit()
    return MessageOut(message="ok")
