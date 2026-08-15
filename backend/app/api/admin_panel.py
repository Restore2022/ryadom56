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
from app.core.security import hash_password
from app.models import (
    AuditLog,
    BlacklistEntry,
    ClientErrorLog,
    DirectoryFavorite,
    DirectoryItem,
    DirectoryReport,
    DistrictAlert,
    DistrictNews,
    Event,
    Favorite,
    Listing,
    ListingMessage,
    ListingReport,
    ListingStatus,
    Settlement,
    TransportFavorite,
    TransportRoute,
    User,
    UserReport,
    UserRole,
    UserSession,
)
from app.schemas import (
    AdminAlertsOut,
    AdminChatMessageOut,
    AdminConversationOut,
    AuditLogOut,
    BlacklistCreate,
    BlacklistOut,
    BulkModerateIn,
    CategoryStat,
    ClientErrorOut,
    DayStat,
    DirectoryReportOut,
    ListingOut,
    ListingReportOut,
    ReportStatusUpdate,
    SettlementStat,
    StatsOut,
    AdminPushIn,
    AdminPushOut,
    AdminUserCreate,
    UserOut,
    UserReportOut,
    UserRoleUpdate,
)
from app.services.audit import log_action
from app.services.blacklist import looks_like_chat_spam, match_blacklist, normalize_phone, normalize_word
from app.services.notify import fcm_tokens_for_user, notify_user
from app.services.sessions import revoke_all_sessions


def _chat_flag_reasons(db: Session, body: str) -> list[str]:
    reasons: list[str] = []
    hits = match_blacklist(db, title="", description=body)
    reasons.extend(hits)
    if looks_like_chat_spam(body):
        reasons.append("подозрение на спам/ссылки")
    return reasons


def _attach_push_flags(db: Session, users: list[User]) -> list[UserOut]:
    if not users:
        return []
    ids = [u.id for u in users]
    session_ids = set(
        db.execute(
            select(UserSession.user_id).where(
                UserSession.user_id.in_(ids),
                UserSession.revoked_at.is_(None),
                UserSession.fcm_token.is_not(None),
                UserSession.fcm_token != "",
            )
        ).scalars().all()
    )
    out: list[UserOut] = []
    for u in users:
        item = UserOut.model_validate(u)
        item.has_push = bool((u.fcm_token or "").strip()) or u.id in session_ids
        item.avatar_url = f"/uploads/{u.avatar_path.replace(chr(92), '/')}" if u.avatar_path else None
        out.append(item)
    return out


def _user_out(db: Session, user: User) -> UserOut:
    return _attach_push_flags(db, [user])[0]

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
    open_listing_reports = int(
        db.execute(select(func.count(ListingReport.id)).where(ListingReport.status == "open")).scalar_one()
    )
    open_directory_reports = int(
        db.execute(select(func.count(DirectoryReport.id)).where(DirectoryReport.status == "open")).scalar_one()
    )
    open_user_reports = int(
        db.execute(select(func.count(UserReport.id)).where(UserReport.status == "open")).scalar_one()
    )
    open_reports = open_listing_reports + open_directory_reports + open_user_reports

    listing_by_settlement = {
        sid: int(n)
        for sid, n in db.execute(
            select(Listing.settlement_id, func.count(Listing.id))
            .where(Listing.status == ListingStatus.approved)
            .group_by(Listing.settlement_id)
        ).all()
    }
    directory_opens_by_settlement = {
        sid: int(n or 0)
        for sid, n in db.execute(
            select(DirectoryItem.settlement_id, func.coalesce(func.sum(DirectoryItem.view_count), 0)).group_by(
                DirectoryItem.settlement_id
            )
        ).all()
    }
    settlements_rows = db.execute(select(Settlement).order_by(Settlement.display_name)).scalars().all()
    by_settlement: list[SettlementStat] = []
    for s in settlements_rows:
        listings_n = listing_by_settlement.get(s.id, 0)
        opens_n = directory_opens_by_settlement.get(s.id, 0)
        if listings_n or opens_n:
            by_settlement.append(
                SettlementStat(
                    settlement_id=s.id,
                    settlement_name=s.display_name,
                    listings_count=listings_n,
                    directory_opens=opens_n,
                )
            )
    # без привязки к селу
    unassigned_listings = listing_by_settlement.get(None, 0)
    unassigned_opens = directory_opens_by_settlement.get(None, 0)
    if unassigned_listings or unassigned_opens:
        by_settlement.append(
            SettlementStat(
                settlement_id=None,
                settlement_name="Без населённого пункта",
                listings_count=unassigned_listings,
                directory_opens=unassigned_opens,
            )
        )
    by_settlement.sort(key=lambda x: (-(x.listings_count + x.directory_opens), x.settlement_name))

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
        open_reports=open_reports,
        open_directory_reports=open_directory_reports,
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
        news_total=int(db.execute(select(func.count(DistrictNews.id))).scalar_one()),
        active_alerts=int(
            db.execute(select(func.count(DistrictAlert.id)).where(DistrictAlert.is_active.is_(True))).scalar_one()
        ),
        top_events=[
            {
                "id": eid,
                "title": title,
                "views": int(views or 0),
                "favorites": int(favs or 0),
            }
            for eid, title, views, favs in db.execute(
                select(Event.id, Event.title, Event.view_count, Event.favorite_add_count)
                .order_by(Event.view_count.desc())
                .limit(5)
            ).all()
        ],
        top_routes=[
            {
                "id": rid,
                "title": title,
                "views": int(views or 0),
                "favorites": int(favs or 0),
            }
            for rid, title, views, favs in db.execute(
                select(
                    TransportRoute.id,
                    TransportRoute.title,
                    TransportRoute.view_count,
                    TransportRoute.favorite_count,
                )
                .order_by(TransportRoute.view_count.desc())
                .limit(5)
            ).all()
        ],
        transport_favorites_total=int(db.execute(select(func.count(TransportFavorite.id))).scalar_one()),
        listing_favorites_total=int(db.execute(select(func.count(Favorite.id))).scalar_one()),
        directory_favorites_total=int(db.execute(select(func.count(DirectoryFavorite.id))).scalar_one()),
        event_favorite_adds_total=int(
            db.execute(select(func.coalesce(func.sum(Event.favorite_add_count), 0))).scalar_one()
        ),
        by_settlement=by_settlement,
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
            db.execute(select(func.count(ListingReport.id)).where(ListingReport.status == "open")).scalar_one()
        )
        + int(
            db.execute(select(func.count(DirectoryReport.id)).where(DirectoryReport.status == "open")).scalar_one()
        )
        + int(
            db.execute(select(func.count(UserReport.id)).where(UserReport.status == "open")).scalar_one()
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
    return _attach_push_flags(db, users)


@router.post("/users", response_model=UserOut)
def create_user(
    payload: AdminUserCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.admin)),
):
    email = payload.email.lower().strip()
    exists = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=400, detail="Email уже зарегистрирован")
    settlement = db.execute(select(Settlement).where(Settlement.id == payload.settlement_id)).scalar_one_or_none()
    if not settlement:
        raise HTTPException(status_code=400, detail="Населённый пункт не найден")
    badge = (payload.badge or "").strip() or None
    if badge and badge not in ("new", "trusted", "caution", "verified"):
        raise HTTPException(status_code=400, detail="Неизвестная метка пользователя")
    user = User(
        email=email,
        password_hash=hash_password(payload.password),
        full_name=payload.full_name.strip(),
        phone=payload.phone.strip() if payload.phone else None,
        settlement_id=payload.settlement_id,
        role=payload.role,
        is_active=payload.is_active,
        accepted_terms=True,
        badge=badge,
    )
    db.add(user)
    db.flush()
    log_action(
        db,
        actor=admin,
        action="user.create",
        entity_type="user",
        entity_id=user.id,
        details=f"{user.email} role={user.role.value} active={user.is_active}",
    )
    db.commit()
    created = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    return _user_out(db, created)


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
    if "password" in data and data["password"]:
        target.password_hash = hash_password(data.pop("password"))
        revoke_all_sessions(db, target)
    if "badge" in data:
        badge = (data["badge"] or "").strip() or None
        if badge and badge not in ("new", "trusted", "caution", "verified"):
            raise HTTPException(status_code=400, detail="Неизвестная метка пользователя")
        target.badge = badge
        data.pop("badge")
    if "settlement_id" in data and data["settlement_id"] is not None:
        settlement = db.execute(select(Settlement).where(Settlement.id == data["settlement_id"])).scalar_one_or_none()
        if not settlement:
            raise HTTPException(status_code=400, detail="Населённый пункт не найден")
    before = f"role={target.role.value}, active={target.is_active}"
    was_active = target.is_active
    for key, value in data.items():
        setattr(target, key, value)
    if target.is_active and not was_active:
        target.ban_reason = None
    elif not target.is_active and was_active and not (target.ban_reason or "").strip():
        target.ban_reason = "Заблокирован модератором"
    if target.is_active:
        target.ban_reason = None

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
    return _user_out(db, target)


@router.post("/users/{user_id}/revoke-sessions")
def admin_revoke_sessions(
    user_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.admin)),
):
    target = db.execute(select(User).where(User.id == user_id)).scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    n = revoke_all_sessions(db, target)
    log_action(
        db,
        actor=admin,
        action="user.revoke_sessions",
        entity_type="user",
        entity_id=target.id,
        details=f"revoked={n}",
    )
    db.commit()
    return {"ok": True, "message": f"Выполнен выход на всех устройствах ({n})"}


@router.post("/users/{user_id}/push", response_model=AdminPushOut)
def admin_push_user(
    user_id: int,
    payload: AdminPushIn,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.admin)),
):
    target = db.execute(select(User).where(User.id == user_id)).scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    title = (payload.title or "").strip() or "Рядом56"
    body = (payload.body or "").strip()
    if not body:
        raise HTTPException(status_code=400, detail="Напишите текст сообщения")
    item = notify_user(
        db,
        user_id=target.id,
        type="admin_message",
        title=title,
        body=body,
    )
    devices = len(fcm_tokens_for_user(db, target.id))
    log_action(
        db,
        actor=admin,
        action="user.push",
        entity_type="user",
        entity_id=target.id,
        details=f"title={title[:40]} devices={devices}",
    )
    db.commit()
    if devices:
        message = f"Пуш отправлен на {devices} {_devices_word(devices)}"
    else:
        message = "Сохранено в уведомлениях приложения, но пуш не ушёл — нет токена (человек не открывал приложение с пушами)"
    return AdminPushOut(ok=True, notification_id=item.id, devices=devices, message=message)


def _devices_word(n: int) -> str:
    n = abs(n) % 100
    if 11 <= n <= 14:
        return "устройств"
    last = n % 10
    if last == 1:
        return "устройство"
    if 2 <= last <= 4:
        return "устройства"
    return "устройств"


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


@router.get("/directory-reports", response_model=list[DirectoryReportOut])
def list_directory_reports(
    status_filter: str | None = Query(default="open", alias="status"),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin, UserRole.editor)),
):
    stmt = select(DirectoryReport).options(
        selectinload(DirectoryReport.directory_item),
        selectinload(DirectoryReport.reporter),
    )
    if status_filter:
        stmt = stmt.where(DirectoryReport.status == status_filter)
    stmt = stmt.order_by(DirectoryReport.created_at.desc())
    rows = db.execute(stmt).scalars().unique().all()
    return [
        DirectoryReportOut(
            id=r.id,
            directory_id=r.directory_id,
            directory_title=r.directory_item.title if r.directory_item else None,
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


@router.patch("/directory-reports/{report_id}", response_model=DirectoryReportOut)
def update_directory_report(
    report_id: int,
    payload: ReportStatusUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin, UserRole.editor)),
):
    report = db.execute(
        select(DirectoryReport)
        .options(selectinload(DirectoryReport.directory_item), selectinload(DirectoryReport.reporter))
        .where(DirectoryReport.id == report_id)
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
        action=f"directory_report.{payload.status}",
        entity_type="directory_report",
        entity_id=report.id,
        details=f"directory={report.directory_id}; reply={reply or ''}",
    )
    title_txt = report.directory_item.title if report.directory_item else f"#{report.directory_id}"
    status_label = "просмотрена" if payload.status == "reviewed" else "отклонена"
    body = f"Ваша жалоба на контакт «{title_txt}» {status_label}."
    if reply:
        body = f"{body} Ответ: {reply}"
    notify_user(
        db,
        user_id=report.reporter_id,
        type="directory_report_update",
        title="Жалоба на контакт",
        body=body,
        listing_id=None,
    )
    db.commit()
    return DirectoryReportOut(
        id=report.id,
        directory_id=report.directory_id,
        directory_title=report.directory_item.title if report.directory_item else None,
        reporter_id=report.reporter_id,
        reporter_name=report.reporter.full_name if report.reporter else None,
        reason=report.reason,
        note=report.note,
        status=report.status,
        moderator_reply=report.moderator_reply,
        created_at=report.created_at,
    )


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


def _user_report_out(r: UserReport) -> UserReportOut:
    return UserReportOut(
        id=r.id,
        target_id=r.target_id,
        target_name=r.target.full_name if r.target else None,
        reporter_id=r.reporter_id,
        reporter_name=r.reporter.full_name if r.reporter else None,
        listing_id=r.listing_id,
        listing_title=r.listing.title if r.listing else None,
        reason=r.reason,
        note=r.note,
        status=r.status,
        moderator_reply=r.moderator_reply,
        created_at=r.created_at,
    )


@router.get("/user-reports", response_model=list[UserReportOut])
def list_user_reports(
    status_filter: str | None = Query(default="open", alias="status"),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    stmt = select(UserReport).options(
        selectinload(UserReport.target),
        selectinload(UserReport.reporter),
        selectinload(UserReport.listing),
    )
    if status_filter:
        stmt = stmt.where(UserReport.status == status_filter)
    stmt = stmt.order_by(UserReport.created_at.desc())
    rows = db.execute(stmt).scalars().unique().all()
    return [_user_report_out(r) for r in rows]


@router.patch("/user-reports/{report_id}", response_model=UserReportOut)
def update_user_report(
    report_id: int,
    payload: ReportStatusUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    report = db.execute(
        select(UserReport)
        .options(
            selectinload(UserReport.target),
            selectinload(UserReport.reporter),
            selectinload(UserReport.listing),
        )
        .where(UserReport.id == report_id)
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
        action=f"user_report.{payload.status}",
        entity_type="user_report",
        entity_id=report.id,
        details=f"target={report.target_id}; reply={reply or ''}",
    )
    who = report.target.full_name if report.target else f"#{report.target_id}"
    status_label = "просмотрена" if payload.status == "reviewed" else "отклонена"
    body = f"Ваша жалоба на пользователя «{who}» {status_label}."
    if reply:
        body = f"{body} Ответ: {reply}"
    notify_user(
        db,
        user_id=report.reporter_id,
        type="user_report_update",
        title="Жалоба на человека",
        body=body,
        listing_id=report.listing_id,
    )
    db.commit()
    return _user_report_out(report)


@router.get("/chats", response_model=list[AdminConversationOut])
def list_chats(
    q: str | None = None,
    flagged_only: bool = Query(default=False),
    limit: int = Query(default=100, ge=1, le=300),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    pairs = db.execute(
        select(ListingMessage.listing_id, ListingMessage.buyer_id)
        .where(ListingMessage.buyer_id.is_not(None))
        .distinct()
    ).all()
    out: list[AdminConversationOut] = []
    needle = (q or "").strip().lower()
    for lid, buyer_id in pairs:
        if buyer_id is None:
            continue
        item = db.execute(select(Listing).where(Listing.id == lid)).scalar_one_or_none()
        if not item:
            continue
        msgs = (
            db.execute(
                select(ListingMessage)
                .where(ListingMessage.listing_id == lid, ListingMessage.buyer_id == buyer_id)
                .order_by(ListingMessage.created_at.desc())
            )
            .scalars()
            .all()
        )
        if not msgs:
            continue
        last = msgs[0]
        flag_reasons: list[str] = []
        for m in msgs:
            for reason in _chat_flag_reasons(db, m.body):
                if reason not in flag_reasons:
                    flag_reasons.append(reason)
        seller = db.execute(select(User).where(User.id == item.author_id)).scalar_one_or_none()
        buyer = db.execute(select(User).where(User.id == buyer_id)).scalar_one_or_none()
        row = AdminConversationOut(
            listing_id=lid,
            buyer_id=buyer_id,
            listing_title=item.title,
            listing_status=item.status.value if hasattr(item.status, "value") else str(item.status),
            seller_id=item.author_id,
            seller_name=seller.full_name if seller else None,
            buyer_name=buyer.full_name if buyer else None,
            last_message=last.body[:200],
            last_message_at=last.created_at,
            message_count=len(msgs),
            flagged=bool(flag_reasons),
            flag_reasons=flag_reasons[:8],
        )
        if flagged_only and not row.flagged:
            continue
        if needle:
            hay = " ".join(
                [
                    row.listing_title,
                    row.seller_name or "",
                    row.buyer_name or "",
                    row.last_message or "",
                    " ".join(row.flag_reasons),
                ]
            ).lower()
            if needle not in hay:
                continue
        out.append(row)
    out.sort(key=lambda r: (r.last_message_at or datetime.min.replace(tzinfo=timezone.utc)), reverse=True)
    return out[:limit]


@router.get("/chats/{listing_id}/{buyer_id}", response_model=list[AdminChatMessageOut])
def get_chat_thread(
    listing_id: int,
    buyer_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    msgs = (
        db.execute(
            select(ListingMessage)
            .where(ListingMessage.listing_id == listing_id, ListingMessage.buyer_id == buyer_id)
            .order_by(ListingMessage.created_at.asc())
        )
        .scalars()
        .all()
    )
    sender_ids = {m.sender_id for m in msgs}
    names = {}
    if sender_ids:
        for u in db.execute(select(User).where(User.id.in_(sender_ids))).scalars().all():
            names[u.id] = u.full_name
    result: list[AdminChatMessageOut] = []
    for m in msgs:
        reasons = _chat_flag_reasons(db, m.body)
        result.append(
            AdminChatMessageOut(
                id=m.id,
                listing_id=m.listing_id,
                buyer_id=m.buyer_id,
                sender_id=m.sender_id,
                sender_name=names.get(m.sender_id),
                body=m.body,
                created_at=m.created_at,
                flagged=bool(reasons),
                flag_reasons=reasons,
            )
        )
    return result


@router.delete("/chat-messages/{message_id}")
def delete_chat_message(
    message_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    msg = db.execute(select(ListingMessage).where(ListingMessage.id == message_id)).scalar_one_or_none()
    if not msg:
        raise HTTPException(status_code=404, detail="Сообщение не найдено")
    lid, buyer_id, preview = msg.listing_id, msg.buyer_id, msg.body[:80]
    db.delete(msg)
    log_action(
        db,
        actor=user,
        action="chat.message_delete",
        entity_type="listing_message",
        entity_id=message_id,
        details=f"listing={lid}; buyer_id={buyer_id}; body={preview}",
    )
    db.commit()
    return {"ok": True}


@router.delete("/chats/{listing_id}/{buyer_id}")
def delete_chat_thread(
    listing_id: int,
    buyer_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    msgs = (
        db.execute(
            select(ListingMessage).where(
                ListingMessage.listing_id == listing_id, ListingMessage.buyer_id == buyer_id
            )
        )
        .scalars()
        .all()
    )
    if not msgs:
        raise HTTPException(status_code=404, detail="Переписка не найдена")
    count = len(msgs)
    for m in msgs:
        db.delete(m)
    log_action(
        db,
        actor=user,
        action="chat.thread_delete",
        entity_type="listing_chat",
        entity_id=listing_id,
        details=f"buyer_id={buyer_id}; messages={count}",
    )
    db.commit()
    return {"ok": True, "deleted": count}


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


@router.get("/client-errors", response_model=list[ClientErrorOut])
def list_client_errors(
    q: str | None = None,
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    stmt = select(ClientErrorLog).order_by(ClientErrorLog.created_at.desc()).limit(limit)
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                ClientErrorLog.message.ilike(like),
                ClientErrorLog.stack.ilike(like),
                ClientErrorLog.device_model.ilike(like),
                ClientErrorLog.app_version.ilike(like),
                ClientErrorLog.screen.ilike(like),
            )
        )
    return db.execute(stmt).scalars().all()
