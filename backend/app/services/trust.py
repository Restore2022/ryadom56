from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Listing, ListingReport, User, UserReport, UserRole
from app.services.notify import notify_user
from app.services.sessions import revoke_all_sessions

USER_REPORT_BAN_THRESHOLD = 3
LISTING_REPORT_BAN_THRESHOLD = 5


def ban_user(db: Session, user: User, reason: str) -> bool:
    if not user.is_active or user.role != UserRole.user:
        return False
    user.is_active = False
    user.badge = "caution"
    user.ban_reason = (reason or "").strip()[:255] or "Слишком много жалоб"
    revoke_all_sessions(db, user)
    notify_user(
        db,
        user_id=user.id,
        type="account_limited",
        title="Аккаунт ограничен",
        body="Слишком много жалоб. Напишите в поддержку, если это ошибка.",
        listing_id=None,
    )
    return True


def count_listing_reports_against(db: Session, author_id: int) -> int:
    return int(
        db.execute(
            select(func.count(ListingReport.id))
            .join(Listing, Listing.id == ListingReport.listing_id)
            .where(Listing.author_id == author_id, ListingReport.status.in_(["open", "reviewed"]))
        ).scalar_one()
    )


def count_user_reports_against(db: Session, target_id: int) -> int:
    return int(
        db.execute(
            select(func.count(UserReport.id)).where(
                UserReport.target_id == target_id,
                UserReport.status.in_(["open", "reviewed"]),
            )
        ).scalar_one()
    )


def maybe_autoban_from_listing_reports(db: Session, author: User) -> None:
    against = count_listing_reports_against(db, author.id)
    if against >= LISTING_REPORT_BAN_THRESHOLD:
        ban_user(db, author, f"Автобан: {against} жалоб на объявления")
    elif against >= 2:
        author.badge = "caution"


def maybe_autoban_from_user_reports(db: Session, target: User) -> None:
    against = count_user_reports_against(db, target.id)
    if against >= USER_REPORT_BAN_THRESHOLD:
        ban_user(db, target, f"Автобан: {against} жалоб на человека")
    elif against >= 2:
        target.badge = "caution"
