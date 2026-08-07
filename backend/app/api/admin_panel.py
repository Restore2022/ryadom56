from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import require_roles
from app.core.database import get_db
from app.models import (
    AuditLog,
    DirectoryItem,
    Listing,
    ListingReport,
    ListingStatus,
    Settlement,
    User,
    UserRole,
)
from app.schemas import (
    AuditLogOut,
    BulkModerateIn,
    ListingOut,
    ListingReportOut,
    ReportStatusUpdate,
    StatsOut,
    UserOut,
    UserRoleUpdate,
)
from app.services.audit import log_action
from app.services.notify import notify_user
from app.api.listings import load_listing, to_out

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/stats", response_model=StatsOut)
def stats(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator, UserRole.editor)),
):
    return StatsOut(
        users=db.execute(select(func.count(User.id))).scalar_one(),
        listings_pending=db.execute(
            select(func.count(Listing.id)).where(Listing.status == ListingStatus.pending)
        ).scalar_one(),
        listings_approved=db.execute(
            select(func.count(Listing.id)).where(Listing.status == ListingStatus.approved)
        ).scalar_one(),
        directory_items=db.execute(select(func.count(DirectoryItem.id))).scalar_one(),
        settlements=db.execute(select(func.count(Settlement.id))).scalar_one(),
    )


@router.get("/users", response_model=list[UserOut])
def list_users(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    return db.execute(
        select(User).options(selectinload(User.settlement)).order_by(User.created_at.desc())
    ).scalars().all()


@router.patch("/users/{user_id}", response_model=UserOut)
def update_user(
    user_id: int,
    payload: UserRoleUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.admin)),
):
    target = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user_id)
    ).scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    data = payload.model_dump(exclude_unset=True)
    if "role" in data and target.id == admin.id and data["role"] != UserRole.admin:
        raise HTTPException(status_code=400, detail="Нельзя снять с себя роль админа")
    if "email" in data and data["email"]:
        email = str(data["email"]).lower()
        exists = db.execute(select(User).where(User.email == email, User.id != target.id)).scalar_one_or_none()
        if exists:
            raise HTTPException(status_code=400, detail="Email уже занят")
        target.email = email
        data.pop("email")
    if "settlement_id" in data and data["settlement_id"] is not None:
        settlement = db.execute(select(Settlement).where(Settlement.id == data["settlement_id"])).scalar_one_or_none()
        if not settlement:
            raise HTTPException(status_code=400, detail="Населённый пункт не найден")
    before = f"role={target.role.value}, active={target.is_active}"
    for key, value in data.items():
        setattr(target, key, value)

    log_action(
        db,
        actor=admin,
        action="user.update",
        entity_type="user",
        entity_id=target.id,
        details=f"{before} → {data}",
    )
    db.commit()
    target = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user_id)
    ).scalar_one()
    return target


@router.post("/listings/bulk-moderate", response_model=list[ListingOut])
def bulk_moderate(
    payload: BulkModerateIn,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    if payload.status not in (ListingStatus.approved, ListingStatus.rejected, ListingStatus.archived):
        raise HTTPException(status_code=400, detail="Недопустимый статус")
    items = db.execute(
        select(Listing)
        .options(selectinload(Listing.author), selectinload(Listing.settlement), selectinload(Listing.images))
        .where(Listing.id.in_(payload.ids))
    ).scalars().unique().all()
    result = []
    for item in items:
        old = item.status.value
        item.status = payload.status
        item.moderation_note = payload.moderation_note
        log_action(
            db,
            actor=user,
            action=f"bulk_moderate:{payload.status.value}",
            entity_type="listing",
            entity_id=item.id,
            details=f"{old} → {payload.status.value}",
        )
        if payload.status == ListingStatus.approved:
            notify_user(
                db,
                user_id=item.author_id,
                type="listing_approved",
                title="Объявление одобрено",
                body=f"«{item.title}» опубликовано и видно в ленте.",
                listing_id=item.id,
            )
        elif payload.status == ListingStatus.rejected:
            note = (payload.moderation_note or "").strip()
            body = f"«{item.title}» отклонено."
            if note:
                body = f"{body} Причина: {note}"
            notify_user(
                db,
                user_id=item.author_id,
                type="listing_rejected",
                title="Объявление отклонено",
                body=body,
                listing_id=item.id,
            )
        result.append(item)
    db.commit()
    return [to_out(load_listing(db, i.id)) for i in result]


@router.get("/reports", response_model=list[ListingReportOut])
def list_reports(
    status_filter: str | None = Query(default="open", alias="status"),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    stmt = select(ListingReport).options(
        selectinload(ListingReport.listing),
        selectinload(ListingReport.reporter),
    )
    if status_filter:
        stmt = stmt.where(ListingReport.status == status_filter)
    stmt = stmt.order_by(ListingReport.created_at.desc())
    rows = db.execute(stmt).scalars().unique().all()
    return [
        ListingReportOut(
            id=r.id,
            listing_id=r.listing_id,
            listing_title=r.listing.title if r.listing else None,
            reporter_id=r.reporter_id,
            reporter_name=r.reporter.full_name if r.reporter else None,
            reason=r.reason,
            note=r.note,
            status=r.status,
            created_at=r.created_at,
        )
        for r in rows
    ]


@router.patch("/reports/{report_id}", response_model=ListingReportOut)
def update_report(
    report_id: int,
    payload: ReportStatusUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    report = db.execute(
        select(ListingReport)
        .options(selectinload(ListingReport.listing), selectinload(ListingReport.reporter))
        .where(ListingReport.id == report_id)
    ).scalar_one_or_none()
    if not report:
        raise HTTPException(status_code=404, detail="Жалоба не найдена")
    report.status = payload.status
    report.reviewed_at = datetime.now(timezone.utc)
    report.reviewed_by_id = user.id
    log_action(
        db,
        actor=user,
        action=f"report.{payload.status}",
        entity_type="report",
        entity_id=report.id,
        details=f"listing={report.listing_id}",
    )
    title_txt = report.listing.title if report.listing else f"#{report.listing_id}"
    status_label = "просмотрена" if payload.status == "reviewed" else "отклонена"
    notify_user(
        db,
        user_id=report.reporter_id,
        type="report_reviewed",
        title="Жалоба рассмотрена",
        body=f"Ваша жалоба на «{title_txt}» {status_label}.",
        listing_id=report.listing_id,
    )
    db.commit()
    db.refresh(report)
    return ListingReportOut(
        id=report.id,
        listing_id=report.listing_id,
        listing_title=report.listing.title if report.listing else None,
        reporter_id=report.reporter_id,
        reporter_name=report.reporter.full_name if report.reporter else None,
        reason=report.reason,
        note=report.note,
        status=report.status,
        created_at=report.created_at,
    )


@router.get("/audit-log", response_model=list[AuditLogOut])
def audit_log(
    q: str | None = None,
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator, UserRole.editor)),
):
    stmt = select(AuditLog).options(selectinload(AuditLog.actor)).order_by(AuditLog.created_at.desc()).limit(limit)
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.join(AuditLog.actor).where(
            or_(
                AuditLog.action.ilike(like),
                AuditLog.details.ilike(like),
                AuditLog.entity_type.ilike(like),
                User.full_name.ilike(like),
                User.email.ilike(like),
            )
        )
    rows = db.execute(stmt).scalars().unique().all()
    return [
        AuditLogOut(
            id=r.id,
            actor_id=r.actor_id,
            actor_name=r.actor.full_name if r.actor else None,
            action=r.action,
            entity_type=r.entity_type,
            entity_id=r.entity_id,
            details=r.details,
            created_at=r.created_at,
        )
        for r in rows
    ]
