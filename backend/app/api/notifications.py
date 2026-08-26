from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import Notification, User
from app.schemas import NotificationOut

router = APIRouter(prefix="/notifications", tags=["notifications"])

# Сообщения чата и пропущенные звонки живут во вкладке «Чаты», не в колокольчике.
_CHAT_INBOX_TYPES = ("listing_message", "missed_call")


@router.get("", response_model=list[NotificationOut])
def list_notifications(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    limit: int = 50,
):
    rows = db.execute(
        select(Notification)
        .where(
            Notification.user_id == user.id,
            Notification.type.notin_(_CHAT_INBOX_TYPES),
        )
        .order_by(Notification.created_at.desc())
        .limit(min(max(limit, 1), 100))
    ).scalars().all()
    return rows


@router.get("/unread-count")
def unread_count(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    count = db.execute(
        select(func.count())
        .select_from(Notification)
        .where(
            Notification.user_id == user.id,
            Notification.is_read.is_(False),
            Notification.type.notin_(_CHAT_INBOX_TYPES),
        )
    ).scalar_one()
    return {"count": int(count)}


@router.post("/{notification_id}/read", response_model=NotificationOut)
def mark_read(
    notification_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = db.execute(
        select(Notification).where(Notification.id == notification_id, Notification.user_id == user.id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Уведомление не найдено")
    item.is_read = True
    db.commit()
    db.refresh(item)
    return item


@router.post("/read-all")
def mark_all_read(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    rows = db.execute(
        select(Notification).where(Notification.user_id == user.id, Notification.is_read.is_(False))
    ).scalars().all()
    for row in rows:
        row.is_read = True
    db.commit()
    return {"ok": True, "updated": len(rows)}
