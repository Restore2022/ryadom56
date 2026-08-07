from sqlalchemy.orm import Session

from app.models import Notification


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
    return item
