from datetime import datetime, timedelta, timezone
from collections import Counter

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, PlainTextResponse
from sqlalchemy import and_, delete, func, or_, select, update
from sqlalchemy.orm import Session, selectinload

from app.api.deps import require_roles
from app.api.listings import load_listing, to_out
from app.core.config import settings
from app.core.database import get_db
from app.core.security import hash_password
from app.services.call_hub import hub
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
    Presence,
    PromoHit,
    Ride,
    Settlement,
    SiteContact,
    TransportFavorite,
    TransportRoute,
    User,
    UserReport,
    UserRole,
    UserSession,
    VkNewsRun,
)
from app.schemas import (
    AdminAlertsOut,
    AdminChatMessageOut,
    AdminConversationOut,
    AuditLogOut,
    AuditLogPageOut,
    BackupListOut,
    BackupFileOut,
    HostMetricsOut,
    BlacklistCreate,
    BlacklistOut,
    BulkModerateIn,
    CategoryStat,
    ClientErrorOut,
    ClientErrorPageOut,
    ClientErrorPatch,
    DayStat,
    DirectoryReportOut,
    ListingOut,
    ListingReportOut,
    ReportStatusUpdate,
    SettlementStat,
    SiteContactOut,
    SiteContactPageOut,
    SiteContactPatch,
    StatsOut,
    AdminPushIn,
    AdminPushOut,
    BroadcastIn,
    BroadcastOut,
    BroadcastPreviewOut,
    AdminUserCreate,
    UserOut,
    UserReportOut,
    UserRoleUpdate,
    VkNewsRunOut,
    VkNewsRunPageOut,
)
from app.services.audit import log_action
from app.services.apk_stats import download_counts
from app.services.backup import backup_meta, create_backup, disk_info, ensure_daily_backup, list_backup_files
from app.services.host_metrics import snapshot as host_snapshot
from app.services.blacklist import looks_like_chat_spam, match_blacklist, normalize_phone, normalize_word
from app.services.notify import broadcast_audience, fcm_tokens_for_user, notify_broadcast, notify_user
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

    online_since = now - timedelta(minutes=5)
    yekat = timezone(timedelta(hours=5))
    today_start = datetime.now(yekat).replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)
    week_ago = now - timedelta(days=7)
    users_total = int(db.execute(select(func.count(User.id))).scalar_one() or 0)
    users_new_7d = int(
        db.execute(select(func.count(User.id)).where(User.created_at >= week_ago)).scalar_one() or 0
    )
    users_new_today = int(
        db.execute(select(func.count(User.id)).where(User.created_at >= today_start)).scalar_one() or 0
    )
    users_active_30d = int(
        db.execute(select(func.count(User.id)).where(User.last_seen_at >= month_ago)).scalar_one() or 0
    )
    session_ids = {
        uid
        for uid in db.execute(
            select(UserSession.user_id).where(
                UserSession.revoked_at.is_(None),
                UserSession.last_seen_at >= online_since,
            )
        ).scalars().all()
        if uid
    }
    presence_user_ids = {
        uid
        for uid in db.execute(
            select(Presence.user_id).where(
                Presence.source == "app",
                Presence.user_id.is_not(None),
                Presence.last_seen_at >= online_since,
            )
        ).scalars().all()
        if uid
    }
    online_app_users = len(session_ids | presence_user_ids)
    online_app_guests = int(
        db.execute(
            select(func.count(Presence.id)).where(
                Presence.source == "app",
                Presence.user_id.is_(None),
                Presence.last_seen_at >= online_since,
            )
        ).scalar_one()
        or 0
    )
    online_site = int(
        db.execute(
            select(func.count(Presence.id)).where(
                Presence.source == "site",
                Presence.last_seen_at >= online_since,
            )
        ).scalar_one()
        or 0
    )
    site_today = int(
        db.execute(
            select(func.count(Presence.id)).where(
                Presence.source == "site",
                Presence.last_seen_at >= today_start,
            )
        ).scalar_one()
        or 0
    )
    app_guests_today = int(
        db.execute(
            select(func.count(Presence.id)).where(
                Presence.source == "app",
                Presence.user_id.is_(None),
                Presence.last_seen_at >= today_start,
            )
        ).scalar_one()
        or 0
    )
    apk_total, apk_unique, apk_today = download_counts(db)

    return StatsOut(
        users=users_total,
        listings_pending=int(pending),
        listings_approved=db.execute(
            select(func.count(Listing.id)).where(Listing.status == ListingStatus.approved)
        ).scalar_one(),
        directory_items=db.execute(select(func.count(DirectoryItem.id))).scalar_one(),
        settlements=db.execute(select(func.count(Settlement.id))).scalar_one(),
        pending_over_24h=int(pending_over),
        open_reports=open_reports,
        open_directory_reports=open_directory_reports,
        open_contacts=int(
            db.execute(select(func.count(SiteContact.id)).where(SiteContact.status == "new")).scalar_one()
        ),
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
                    or_(
                        Event.starts_at >= now,
                        Event.ends_at >= now,
                        and_(Event.ends_at.is_(None), Event.starts_at >= now - timedelta(hours=12)),
                    ),
                )
            ).scalar_one()
        ),
        transport_routes=int(db.execute(select(func.count(TransportRoute.id))).scalar_one()),
        rides_open=int(
            db.execute(
                select(func.count(Ride.id)).where(
                    Ride.status == "open",
                    Ride.depart_at >= now - timedelta(hours=3),
                )
            ).scalar_one()
        ),
        news_total=int(db.execute(select(func.count(DistrictNews.id))).scalar_one()),
        active_alerts=int(
            db.execute(
                select(func.count(DistrictAlert.id)).where(
                    DistrictAlert.is_active.is_(True),
                    or_(DistrictAlert.starts_at.is_(None), DistrictAlert.starts_at <= now),
                    or_(DistrictAlert.ends_at.is_(None), DistrictAlert.ends_at >= now),
                )
            ).scalar_one()
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
        online_site=online_site,
        online_app=online_app_users + online_app_guests,
        online_app_users=online_app_users,
        online_app_guests=online_app_guests,
        users_new_7d=users_new_7d,
        users_new_today=users_new_today,
        users_older=max(0, users_total - users_new_7d),
        users_active_30d=users_active_30d,
        online_calls=hub.connected_count(),
        site_today=site_today,
        app_guests_today=app_guests_today,
        promo_visits_today=int(
            db.execute(
                select(func.count(PromoHit.id)).where(
                    PromoHit.kind == "visit",
                    PromoHit.created_at >= today_start,
                )
            ).scalar_one()
            or 0
        ),
        promo_downloads_today=int(
            db.execute(
                select(func.count(PromoHit.id)).where(
                    PromoHit.kind == "download",
                    PromoHit.created_at >= today_start,
                )
            ).scalar_one()
            or 0
        ),
        apk_downloads_total=apk_total,
        apk_downloads_unique=apk_unique,
        apk_downloads_today=apk_today,
    )


@router.get("/host", response_model=HostMetricsOut)
def host_metrics(
    _: User = Depends(require_roles(UserRole.admin)),
):
    return HostMetricsOut(**host_snapshot())


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


@router.get("/backups", response_model=BackupListOut)
def list_backups(
    user: User = Depends(require_roles(UserRole.admin)),
):
    ensure_daily_backup()
    files = list_backup_files()
    info = disk_info()
    return BackupListOut(
        items=[BackupFileOut(**backup_meta(p)) for p in files],
        disk_free_mb=info["disk_free_mb"],
        disk_total_mb=info["disk_total_mb"],
        data_dir_mb=info["data_dir_mb"],
    )


@router.post("/backups", response_model=BackupListOut)
def make_backup(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    created = create_backup()
    files = list_backup_files()
    info = disk_info()
    log_action(db, actor=user, action="backup.create", entity_type="backup", entity_id=None, details=created.name)
    db.commit()
    return BackupListOut(
        items=[BackupFileOut(**backup_meta(p)) for p in files],
        disk_free_mb=info["disk_free_mb"],
        disk_total_mb=info["disk_total_mb"],
        data_dir_mb=info["data_dir_mb"],
    )


@router.get("/backups/{name}")
def download_backup_file(
    name: str,
    user: User = Depends(require_roles(UserRole.admin)),
):
    match = next((p for p in list_backup_files() if p.name == name), None)
    if match is None:
        raise HTTPException(status_code=404, detail="Копия не найдена")
    return FileResponse(
        match,
        filename=match.name,
        media_type="application/octet-stream",
    )


@router.get("/contacts", response_model=SiteContactPageOut)
def list_contacts(
    status: str | None = None,
    q: str | None = None,
    limit: int = Query(default=25, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator, UserRole.editor)),
):
    stmt = select(SiteContact)
    if status in ("new", "read", "done"):
        stmt = stmt.where(SiteContact.status == status)
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                SiteContact.name.ilike(like),
                SiteContact.settlement.ilike(like),
                SiteContact.phone.ilike(like),
                SiteContact.message.ilike(like),
            )
        )
    count_stmt = select(func.count()).select_from(stmt.subquery())
    total = int(db.execute(count_stmt).scalar_one())
    rows = db.execute(stmt.order_by(SiteContact.created_at.desc()).offset(offset).limit(limit)).scalars().all()
    return SiteContactPageOut(
        items=[SiteContactOut.model_validate(r) for r in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.patch("/contacts/{contact_id}", response_model=SiteContactOut)
def patch_contact(
    contact_id: int,
    payload: SiteContactPatch,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator, UserRole.editor)),
):
    row = db.get(SiteContact, contact_id)
    if not row:
        raise HTTPException(status_code=404, detail="Обращение не найдено")
    row.status = payload.status
    log_action(
        db,
        actor=user,
        action=f"contact.{payload.status}",
        entity_type="contact",
        entity_id=row.id,
        details=row.name,
    )
    db.commit()
    db.refresh(row)
    return SiteContactOut.model_validate(row)


@router.get("/alerts", response_model=AdminAlertsOut)
def alerts(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator, UserRole.editor)),
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
        open_contacts=int(
            db.execute(select(func.count(SiteContact.id)).where(SiteContact.status == "new")).scalar_one()
        ),
        unread_client_errors=int(
            db.execute(
                select(func.count(ClientErrorLog.id)).where(
                    or_(ClientErrorLog.is_read.is_(False), ClientErrorLog.is_read.is_(None))
                )
            ).scalar_one()
        ),
    )


@router.get("/users", response_model=list[UserOut])
def list_users(
    q: str | None = None,
    suspicious: bool = False,
    kind: str | None = Query(default=None, pattern="^(feed|real)$"),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    stmt = select(User).options(selectinload(User.settlement)).order_by(User.created_at.desc())
    if kind == "feed":
        stmt = stmt.where(User.badge == "feed")
    elif kind == "real":
        stmt = stmt.where(or_(User.badge.is_(None), User.badge != "feed"))
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
        raise HTTPException(status_code=400, detail="Нет такого посёлка, села или города")
    badge = (payload.badge or "").strip() or None
    if badge and badge not in ("new", "trusted", "caution", "verified", "feed"):
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
    kind: str | None = Query(default=None, pattern="^(feed|real)$"),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    rows = list_users(q=q, suspicious=suspicious, kind=kind, db=db, user=user)
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
        if badge and badge not in ("new", "trusted", "caution", "verified", "feed"):
            raise HTTPException(status_code=400, detail="Неизвестная метка пользователя")
        target.badge = badge
        data.pop("badge")
    if "settlement_id" in data and data["settlement_id"] is not None:
        settlement = db.execute(select(Settlement).where(Settlement.id == data["settlement_id"])).scalar_one_or_none()
        if not settlement:
            raise HTTPException(status_code=400, detail="Нет такого посёлка, села или города")
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


BROADCAST_KINDS = {
    "news": "Новость",
    "promo": "Акция",
    "question": "Вопрос к жителям",
    "info": "Рядом56",
}

BROADCAST_AUDIENCES = {
    "all": "Всем",
    "users": "С аккаунтом",
    "guests": "Гостям без входа",
}


@router.get("/broadcast", response_model=BroadcastPreviewOut)
def broadcast_preview(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.admin, UserRole.editor)),
):
    people, user_tokens, guest_tokens = broadcast_audience(db)
    return BroadcastPreviewOut(
        people=len(people),
        user_devices=len(user_tokens),
        guest_devices=len(guest_tokens),
        devices=len(user_tokens) + len(guest_tokens),
    )


@router.post("/broadcast", response_model=BroadcastOut)
def broadcast_push(
    payload: BroadcastIn,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.admin, UserRole.editor)),
):
    kind = (payload.kind or "info").strip().lower()
    if kind not in BROADCAST_KINDS:
        raise HTTPException(status_code=400, detail="Неизвестный тип сообщения")
    audience = (payload.audience or "all").strip().lower()
    if audience not in BROADCAST_AUDIENCES:
        raise HTTPException(status_code=400, detail="Неизвестная аудитория")
    title = (payload.title or "").strip() or BROADCAST_KINDS[kind]
    body = (payload.body or "").strip()
    if len(body) < 3:
        raise HTTPException(status_code=400, detail="Напишите текст сообщения")
    last = db.execute(
        select(AuditLog)
        .where(AuditLog.action == "broadcast.push")
        .order_by(AuditLog.created_at.desc())
        .limit(1)
    ).scalar_one_or_none()
    if last and last.created_at:
        stamp = last.created_at
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=timezone.utc)
        age = (datetime.now(timezone.utc) - stamp).total_seconds()
        if age < 90:
            wait = max(1, int(90 - age))
            raise HTTPException(
                status_code=429,
                detail=f"Подождите {wait} сек. — чтобы не отправить два раза подряд",
            )
    _people, user_tokens, guest_tokens = broadcast_audience(db)
    user_count = len(user_tokens)
    guest_count = len(guest_tokens)
    if audience == "users" and user_count < 1 and len(_people) < 1:
        raise HTTPException(status_code=400, detail="Нет активных аккаунтов для рассылки")
    if audience == "guests" and guest_count < 1:
        raise HTTPException(status_code=400, detail="Нет гостей с пушем — пока никто без входа не открыл приложение")
    created, sent = notify_broadcast(
        db,
        type=f"broadcast_{kind}",
        title=title,
        body=body,
        extra={"kind": kind},
        audience=audience,
    )
    target_devices = user_count + guest_count
    if audience == "users":
        target_devices = user_count
    elif audience == "guests":
        target_devices = guest_count
    log_action(
        db,
        actor=admin,
        action="broadcast.push",
        entity_type="broadcast",
        details=(
            f"audience={audience}; kind={kind}; title={title[:40]}; people={created}; "
            f"devices={target_devices}; sent={sent}"
        ),
    )
    db.commit()
    audience_label = BROADCAST_AUDIENCES[audience]
    if sent and created:
        message = (
            f"{audience_label}: записано {_people_word(created)}, "
            f"пуш ушёл на {sent} {_devices_word(sent)}."
        )
    elif sent:
        message = f"{audience_label}: пуш ушёл на {sent} {_devices_word(sent)}."
    elif created:
        message = (
            f"{audience_label}: записано в колокольчик {_people_word(created)}, "
            "но на телефоны не ушло — нет токена пуша"
        )
    else:
        message = f"{audience_label}: некому отправлять"
    return BroadcastOut(
        ok=True,
        people=created,
        devices=target_devices,
        guest_devices=guest_count if audience in ("all", "guests") else 0,
        sent=sent,
        message=message,
    )


def _people_word(n: int) -> str:
    absn = abs(n)
    mod100 = absn % 100
    mod10 = absn % 10
    if 11 <= mod100 <= 14 or mod10 == 0 or mod10 >= 5:
        word = "человек"
    elif mod10 == 1:
        word = "человек"
    else:
        word = "человека"
    return f"{n} {word}"


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
    if status_filter and status_filter != "all":
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
    if status_filter and status_filter != "all":
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
    if status_filter and status_filter != "all":
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
    pairs = (
        select(
            ListingMessage.listing_id,
            ListingMessage.buyer_id,
            func.max(ListingMessage.id).label("last_id"),
            func.count(ListingMessage.id).label("msg_count"),
        )
        .where(ListingMessage.buyer_id.is_not(None))
        .group_by(ListingMessage.listing_id, ListingMessage.buyer_id)
        .subquery()
    )
    agg_rows = db.execute(select(pairs)).all()
    last_ids = [row.last_id for row in agg_rows if row.last_id]
    lasts = {
        m.id: m
        for m in (
            db.execute(select(ListingMessage).where(ListingMessage.id.in_(last_ids))).scalars().all() if last_ids else []
        )
    }
    rn = func.row_number().over(
        partition_by=(ListingMessage.listing_id, ListingMessage.buyer_id),
        order_by=ListingMessage.id.desc(),
    )
    ranked = (
        select(
            ListingMessage.listing_id,
            ListingMessage.buyer_id,
            ListingMessage.body,
            ListingMessage.kind,
            rn.label("rn"),
        ).where(ListingMessage.buyer_id.is_not(None))
    ).subquery()
    recent = db.execute(select(ranked).where(ranked.c.rn <= 12)).all()
    flags_map: dict[tuple[int, int], list[str]] = {}
    for row in recent:
        if (row.kind or "text") == "call":
            continue
        key = (row.listing_id, row.buyer_id)
        acc = flags_map.setdefault(key, [])
        for reason in _chat_flag_reasons(db, row.body):
            if reason not in acc:
                acc.append(reason)
    listing_ids = {row.listing_id for row in agg_rows}
    listings = {
        item.id: item
        for item in (
            db.execute(select(Listing).where(Listing.id.in_(listing_ids))).scalars().all() if listing_ids else []
        )
    }
    user_ids: set[int] = set()
    for item in listings.values():
        user_ids.add(item.author_id)
    for row in agg_rows:
        if row.buyer_id:
            user_ids.add(row.buyer_id)
    users = {
        u.id: u for u in (db.execute(select(User).where(User.id.in_(user_ids))).scalars().all() if user_ids else [])
    }
    out: list[AdminConversationOut] = []
    needle = (q or "").strip().lower()
    for row in agg_rows:
        item = listings.get(row.listing_id)
        last = lasts.get(row.last_id)
        if not item or not last or row.buyer_id is None:
            continue
        flag_reasons = flags_map.get((row.listing_id, row.buyer_id), [])[:8]
        seller = users.get(item.author_id)
        buyer = users.get(row.buyer_id)
        conv = AdminConversationOut(
            listing_id=row.listing_id,
            buyer_id=row.buyer_id,
            listing_title=item.title,
            listing_status=item.status.value if hasattr(item.status, "value") else str(item.status),
            seller_id=item.author_id,
            seller_name=seller.full_name if seller else None,
            buyer_name=buyer.full_name if buyer else None,
            last_message=("Фото" if (last.kind or "text") == "photo" else last.body[:200]),
            last_message_at=last.created_at,
            message_count=int(row.msg_count or 0),
            flagged=bool(flag_reasons),
            flag_reasons=flag_reasons,
        )
        if flagged_only and not conv.flagged:
            continue
        if needle:
            hay = " ".join(
                [
                    conv.listing_title,
                    conv.seller_name or "",
                    conv.buyer_name or "",
                    conv.last_message or "",
                    " ".join(conv.flag_reasons),
                ]
            ).lower()
            if needle not in hay:
                continue
        out.append(conv)
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
        reasons = [] if (m.kind or "text") == "call" else _chat_flag_reasons(db, m.body)
        result.append(
            AdminChatMessageOut(
                id=m.id,
                listing_id=m.listing_id,
                buyer_id=m.buyer_id,
                sender_id=m.sender_id,
                sender_name=names.get(m.sender_id),
                body="Фото" if (m.kind or "text") == "photo" else m.body,
                created_at=m.created_at,
                flagged=bool(reasons),
                flag_reasons=reasons,
                kind=m.kind or "text",
                is_read=bool(m.is_read),
                image_url=f"/uploads/{m.image_path.replace(chr(92), '/')}" if getattr(m, "image_path", None) else None,
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


@router.get("/audit-log", response_model=AuditLogPageOut)
def audit_log(
    q: str | None = None,
    entity_type: str | None = None,
    limit: int = Query(default=30, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator, UserRole.editor)),
):
    filters = []
    need_actor = bool(q and q.strip())
    if q and q.strip():
        like = f"%{q.strip()}%"
        filters.append(
            or_(
                AuditLog.action.ilike(like),
                AuditLog.details.ilike(like),
                AuditLog.entity_type.ilike(like),
                User.full_name.ilike(like),
                User.email.ilike(like),
            )
        )
    if entity_type and entity_type.strip():
        kind = entity_type.strip()
        if kind == "report":
            filters.append(AuditLog.entity_type.in_(("report", "directory_report", "user_report")))
        elif kind == "chat":
            filters.append(AuditLog.entity_type.in_(("chat", "listing_chat")))
        else:
            filters.append(AuditLog.entity_type == kind)

    stmt = select(AuditLog).options(selectinload(AuditLog.actor))
    count_stmt = select(func.count()).select_from(AuditLog)
    if need_actor:
        stmt = stmt.join(AuditLog.actor)
        count_stmt = count_stmt.join(AuditLog.actor)
    if filters:
        stmt = stmt.where(*filters)
        count_stmt = count_stmt.where(*filters)
    total = int(db.execute(count_stmt).scalar_one())
    stmt = stmt.order_by(AuditLog.created_at.desc()).offset(offset).limit(limit)
    rows = db.execute(stmt).scalars().unique().all()
    return AuditLogPageOut(
        items=[
            AuditLogOut(
                id=r.id,
                actor_id=r.actor_id,
                actor_name=r.actor.full_name if r.actor else None,
                actor_role=r.actor.role.value if r.actor else None,
                action=r.action,
                entity_type=r.entity_type,
                entity_id=r.entity_id,
                details=r.details,
                created_at=r.created_at,
            )
            for r in rows
        ],
        total=total,
        limit=limit,
        offset=offset,
    )


def _client_error_outs(db: Session, rows: list[ClientErrorLog]) -> list[ClientErrorOut]:
    names: dict[int, str] = {}
    uids = {r.user_id for r in rows if r.user_id}
    if uids:
        for u in db.execute(select(User.id, User.full_name).where(User.id.in_(uids))).all():
            names[int(u[0])] = u[1]
    return [
        ClientErrorOut(
            id=r.id,
            created_at=r.created_at,
            user_id=r.user_id,
            user_name=names.get(r.user_id) if r.user_id else None,
            message=r.message,
            stack=r.stack,
            screen=r.screen,
            app_version=r.app_version,
            device_brand=r.device_brand,
            device_model=r.device_model,
            device_os=r.device_os,
            client_ip=r.client_ip,
            is_read=bool(r.is_read),
        )
        for r in rows
    ]


@router.get("/client-errors", response_model=ClientErrorPageOut)
def list_client_errors(
    q: str | None = None,
    limit: int = Query(default=25, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    stmt = select(ClientErrorLog)
    count_stmt = select(func.count()).select_from(ClientErrorLog)
    if q and q.strip():
        like = f"%{q.strip()}%"
        cond = or_(
            ClientErrorLog.message.ilike(like),
            ClientErrorLog.stack.ilike(like),
            ClientErrorLog.device_brand.ilike(like),
            ClientErrorLog.device_model.ilike(like),
            ClientErrorLog.device_os.ilike(like),
            ClientErrorLog.app_version.ilike(like),
            ClientErrorLog.screen.ilike(like),
            ClientErrorLog.client_ip.ilike(like),
        )
        stmt = stmt.where(cond)
        count_stmt = count_stmt.where(cond)
    total = int(db.execute(count_stmt).scalar_one())
    unread_count = int(
        db.execute(
            select(func.count()).select_from(ClientErrorLog).where(
                or_(ClientErrorLog.is_read.is_(False), ClientErrorLog.is_read.is_(None))
            )
        ).scalar_one()
    )
    rows = (
        db.execute(
            stmt.order_by(ClientErrorLog.is_read.asc(), ClientErrorLog.created_at.desc())
            .offset(offset)
            .limit(limit)
        )
        .scalars()
        .all()
    )
    return ClientErrorPageOut(
        items=_client_error_outs(db, rows),
        total=total,
        limit=limit,
        offset=offset,
        unread_count=unread_count,
    )


@router.post("/client-errors/mark-read")
def mark_client_errors_read(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    db.execute(
        update(ClientErrorLog)
        .where(or_(ClientErrorLog.is_read.is_(False), ClientErrorLog.is_read.is_(None)))
        .values(is_read=True)
    )
    db.commit()
    return {"ok": True}


@router.patch("/client-errors/{error_id}", response_model=ClientErrorOut)
def patch_client_error(
    error_id: int,
    payload: ClientErrorPatch,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    row = db.get(ClientErrorLog, error_id)
    if not row:
        raise HTTPException(status_code=404, detail="Сбой не найден")
    row.is_read = payload.is_read
    db.commit()
    db.refresh(row)
    return _client_error_outs(db, [row])[0]


@router.delete("/client-errors")
def delete_read_client_errors(
    read: bool = Query(default=True),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    if not read:
        raise HTTPException(status_code=400, detail="Можно удалить только прочитанные")
    result = db.execute(delete(ClientErrorLog).where(ClientErrorLog.is_read.is_(True)))
    db.commit()
    return {"ok": True, "deleted": int(result.rowcount or 0)}


@router.delete("/client-errors/{error_id}")
def delete_client_error(
    error_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    row = db.get(ClientErrorLog, error_id)
    if not row:
        raise HTTPException(status_code=404, detail="Сбой не найден")
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.get("/vk-news/runs", response_model=VkNewsRunPageOut)
def vk_news_runs(
    limit: int = Query(default=30, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    total = int(db.execute(select(func.count(VkNewsRun.id))).scalar_one())
    rows = db.execute(
        select(VkNewsRun).order_by(VkNewsRun.started_at.desc()).offset(offset).limit(limit)
    ).scalars().all()
    return VkNewsRunPageOut(
        items=[VkNewsRunOut.model_validate(r) for r in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.post("/vk-news/sync", response_model=VkNewsRunOut)
def vk_news_sync_now(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    from app.services.vk_news import sync_all

    runs = sync_all(limit=20, triggered_by=f"admin:{user.email}")
    run = runs[-1]
    details = "; ".join(
        f"{item.source} status={item.status} created={item.created} skipped={item.skipped}" for item in runs
    )
    log_action(
        db,
        actor=user,
        action="vk_news.sync",
        entity_type="vk_news",
        entity_id=run.id,
        details=details[:500],
    )
    db.commit()
    return VkNewsRunOut.model_validate(run)

