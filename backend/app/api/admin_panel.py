from datetime import datetime, timedelta, timezone
from collections import Counter

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, PlainTextResponse
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import require_roles
from app.api.listings import load_listing, to_out
from app.core.config import settings
from app.core.database import get_db
from app.models import (
    AuditLog,
    BlacklistEntry,
    DirectoryItem,
    Event,
    Listing,
    ListingReport,
    ListingStatus,
    Settlement,
    TransportRoute,
    User,
    UserRole,
)
from app.schemas import (
    AdminAlertsOut,
    AuditLogOut,
    BlacklistCreate,
    BlacklistOut,
    BulkModerateIn,
    CategoryStat,
    DayStat,
    ListingOut,
    ListingReportOut,
    ReportStatusUpdate,
    StatsOut,
    UserOut,
    UserRoleUpdate,
)
from app.services.audit import log_action
from app.services.blacklist import normalize_phone, normalize_word
from app.services.notify import notify_user

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/stats", response_model=StatsOut)
def stats(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator, UserRole.editor)),
):
    now = datetime.now(timezone.utc)
    day_ago = now - timedelta(hours=24)
    month_ago = now - timedelta(days=30)

    pending = db.execute(
        select(func.count(Listing.id)).where(Listing.status == ListingStatus.pending)
    ).scalar_one()
    pending_over = db.execute(
        select(func.count(Listing.id)).where(
            Listing.status == ListingStatus.pending,
            Listing.created_at < day_ago,
        )
    ).scalar_one()
    open_reports = db.execute(
        select(func.count(ListingReport.id)).where(ListingReport.status == "open")
    ).scalar_one()

    approved_30 = 0
    rejected_30 = 0
    logs = db.execute(
        select(AuditLog.action).where(
            AuditLog.created_at >= month_ago,
            or_(
                AuditLog.action.like("moderate:%"),
                AuditLog.action.like("bulk_moderate:%"),
            ),
        )
    ).scalars().all()
    for action in logs:
        if action.endswith("approved"):
            approved_30 += 1
        elif action.endswith("rejected"):
            rejected_30 += 1
    total_mod = approved_30 + rejected_30
    conversion = round(approved_30 / total_mod, 3) if total_mod else None

    per_day: list[DayStat] = []
    for i in range(6, -1, -1):
        start = (now - timedelta(days=i)).replace(hour=0, minute=0, second=0, microsecond=0)
        end = start + timedelta(days=1)
        count = db.execute(
            select(func.count(Listing.id)).where(Listing.created_at >= start, Listing.created_at < end)
        ).scalar_one()
        per_day.append(DayStat(day=start.date().isoformat(), count=int(count)))

    cat_rows = db.execute(
        select(Listing.category, func.count(Listing.id))
        .where(Listing.status == ListingStatus.approved)
        .group_by(Listing.category)
        .order_by(func.count(Listing.id).desc())
        .limit(6)
    ).all()
    top = [
        CategoryStat(category=c.value if hasattr(c, "value") else str(c), count=int(n))
        for c, n in cat_rows
    ]

    return StatsOut(
        users=db.execute(select(func.count(User.id))).scalar_one(),
        listings_pending=int(pending),
        listings_approved=db.execute(
            select(func.count(Listing.id)).where(Listing.status == ListingStatus.approved)
        ).scalar_one(),
        directory_items=db.execute(select(func.count(DirectoryItem.id))).scalar_one(),
        settlements=db.execute(select(func.count(Settlement.id))).scalar_one(),
        pending_over_24h=int(pending_over),
        open_reports=int(open_reports),
        moderated_approved_30d=approved_30,
        moderated_rejected_30d=rejected_30,
        moderation_conversion=conversion,
        listings_per_day=per_day,
        top_categories=top,
        events_total=int(db.execute(select(func.count(Event.id))).scalar_one()),
        events_upcoming=int(
            db.execute(
                select(func.count(Event.id)).where(
                    Event.is_published.is_(True),
                    Event.starts_at >= now,
                )
            ).scalar_one()
        ),
        transport_routes=int(db.execute(select(func.count(TransportRoute.id))).scalar_one()),
    )


@router.get("/backup")
def download_backup(
    user: User = Depends(require_roles(UserRole.admin)),
):
    # sqlite:///./data/ryadom56.db → data/ryadom56.db
    raw = settings.database_url.replace("sqlite:///", "")
    path = Path(raw)
    if not path.is_absolute():
        path = Path.cwd() / path
    if not path.exists():
        raise HTTPException(status_code=404, detail="Файл базы не найден")
    return FileResponse(
        path,
        filename="ryadom56-backup.db",
        media_type="application/octet-stream",
    )


@router.get("/alerts", response_model=AdminAlertsOut)
def alerts(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    day_ago = datetime.now(timezone.utc) - timedelta(hours=24)
    return AdminAlertsOut(
        pending=int(
            db.execute(
                select(func.count(Listing.id)).where(Listing.status == ListingStatus.pending)
            ).scalar_one()
        ),
        pending_over_24h=int(
            db.execute(
                select(func.count(Listing.id)).where(
                    Listing.status == ListingStatus.pending,
                    Listing.created_at < day_ago,
                )
            ).scalar_one()
        ),
        open_reports=int(
            db.execute(
                select(func.count(ListingReport.id)).where(ListingReport.status == "open")
            ).scalar_one()
        ),
    )


@router.get("/users", response_model=list[UserOut])
def list_users(
    q: str | None = None,
    suspicious: bool = False,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    stmt = select(User).options(selectinload(User.settlement)).order_by(User.created_at.desc())
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                User.full_name.ilike(like),
                User.email.ilike(like),
                User.phone.ilike(like),
                User.last_ip.ilike(like),
                User.device_brand.ilike(like),
                User.device_model.ilike(like),
                User.device_os.ilike(like),
                User.app_version.ilike(like),
            )
        )
    users = list(db.execute(stmt).scalars().unique().all())
    if suspicious:
        ip_counts = Counter(u.last_ip for u in users if u.last_ip)
        hot = {ip for ip, n in ip_counts.items() if n >= 2}
        users = [u for u in users if u.last_ip and u.last_ip in hot]
        users.sort(key=lambda u: (u.last_ip or "", -(u.id)))
    return users


@router.get("/users/export")
def export_users(
    q: str | None = None,
    suspicious: bool = False,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    rows = list_users(q=q, suspicious=suspicious, db=db, user=user)
    lines = [
        "id;name;email;phone;role;active;ip;device;os;app;last_seen",
    ]
    for u in rows:
        device = " ".join(x for x in [u.device_brand, u.device_model] if x)
        lines.append(
            ";".join(
                [
                    str(u.id),
                    (u.full_name or "").replace(";", ","),
                    u.email,
                    (u.phone or "").replace(";", ","),
                    u.role.value,
                    "1" if u.is_active else "0",
                    u.last_ip or "",
                    device.replace(";", ","),
                    (u.device_os or "").replace(";", ","),
                    u.app_version or "",
                    u.last_seen_at.isoformat() if u.last_seen_at else "",
                ]
            )
        )
    return PlainTextResponse("\n".join(lines) + "\n", media_type="text/csv; charset=utf-8")


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


@router.get("/blacklist", response_model=list[BlacklistOut])
def list_blacklist(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    return db.execute(select(BlacklistEntry).order_by(BlacklistEntry.created_at.desc())).scalars().all()


@router.post("/blacklist", response_model=BlacklistOut)
def add_blacklist(
    payload: BlacklistCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    value = normalize_phone(payload.value) if payload.kind == "phone" else normalize_word(payload.value)
    if not value:
        raise HTTPException(status_code=400, detail="Пустое значение")
    exists = db.execute(
        select(BlacklistEntry).where(BlacklistEntry.kind == payload.kind, BlacklistEntry.value == value)
    ).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=400, detail="Уже в списке")
    row = BlacklistEntry(
        kind=payload.kind,
        value=value if payload.kind == "phone" else payload.value.strip(),
        note=(payload.note or "").strip() or None,
        created_by_id=user.id,
    )
    if payload.kind == "word":
        row.value = normalize_word(payload.value)
    db.add(row)
    log_action(db, actor=user, action="blacklist.add", entity_type="blacklist", entity_id=None, details=f"{payload.kind}:{row.value}")
    db.commit()
    db.refresh(row)
    return row


@router.delete("/blacklist/{entry_id}")
def delete_blacklist(
    entry_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    row = db.get(BlacklistEntry, entry_id)
    if not row:
        raise HTTPException(status_code=404, detail="Не найдено")
    log_action(db, actor=user, action="blacklist.delete", entity_type="blacklist", entity_id=row.id, details=f"{row.kind}:{row.value}")
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.post("/listings/bulk-moderate", response_model=list[ListingOut])
def bulk_moderate(
    payload: BulkModerateIn,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    if payload.status not in (ListingStatus.approved, ListingStatus.rejected, ListingStatus.archived):
        raise HTTPException(status_code=400, detail="Недопустимый статус")
    if payload.status == ListingStatus.rejected and not (payload.moderation_note or "").strip():
        raise HTTPException(status_code=400, detail="Укажите причину отклонения")
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
        if payload.status == ListingStatus.approved:
            item.auto_flagged = False
            item.previous_snapshot = None
        if payload.status in (ListingStatus.rejected, ListingStatus.archived):
            item.is_pinned = False
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
            moderator_reply=getattr(r, "moderator_reply", None),
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
    reply = (payload.moderator_reply or "").strip() or None
    report.moderator_reply = reply
    log_action(
        db,
        actor=user,
        action=f"report.{payload.status}",
        entity_type="report",
        entity_id=report.id,
        details=f"listing={report.listing_id}; reply={reply or ''}",
    )
    title_txt = report.listing.title if report.listing else f"#{report.listing_id}"
    status_label = "просмотрена" if payload.status == "reviewed" else "отклонена"
    body = f"Ваша жалоба на «{title_txt}» {status_label}."
    if reply:
        body = f"{body} Ответ модератора: {reply}"
    notify_user(
        db,
        user_id=report.reporter_id,
        type="report_reviewed",
        title="Жалоба рассмотрена",
        body=body,
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
        moderator_reply=report.moderator_reply,
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
