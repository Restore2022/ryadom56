from pathlib import Path
import json
import uuid
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from sqlalchemy import case, exists, func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user, get_optional_user, require_roles
from app.core.database import get_db
from app.core.geo import haversine_km, resolve_origin
from app.models import (
    Favorite,
    Listing,
    ListingCategory,
    ListingImage,
    ListingMessage,
    ListingReport,
    ListingStatus,
    Settlement,
    User,
    UserReport,
    UserRole,
)
from app.schemas import (
    AuthorReportOut,
    ConversationOut,
    ListingAdminStatusIn,
    ListingCloseIn,
    ListingCreate,
    ListingExtendIn,
    ListingImageOut,
    ListingImagesReorderIn,
    ListingMessageIn,
    ListingMessageOut,
    ListingModerationIn,
    ListingOut,
    ListingPageOut,
    ListingPinIn,
    ListingReportIn,
    ListingSnapshot,
    ListingUpdate,
)
from app.services.audit import log_action
from app.services.blacklist import looks_like_chat_spam, match_blacklist
from app.services.call_hub import hub
from app.services.notify import notify_user, push_user
from app.services.rate_limit import limiter
from app.services.trust import maybe_autoban_from_listing_reports

router = APIRouter(prefix="/listings", tags=["listings"])

UPLOAD_ROOT = Path("data/uploads")
MAX_IMAGES = 5
MAX_IMAGE_BYTES = 6 * 1024 * 1024
ALLOWED_TYPES = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}
IMAGE_MAGIC = {
    b"\xff\xd8\xff": ".jpg",
    b"\x89PNG\r\n\x1a\n": ".png",
    b"RIFF": ".webp",  # checked further below
}

CLOSE_REASON_LABELS = {
    "sold": "Продали / отдали",
    "not_relevant": "Неактуально",
    "busy": "Пока занят / нет времени",
    "expired": "Истёк срок публикации",
    "other": "Другое",
}

MAX_ACTIVE_LISTINGS = 5


def to_listing_message_out(
    m: ListingMessage,
    *,
    user_id: int,
    sender_name: str | None,
    peer_id: int | None,
) -> ListingMessageOut:
    return ListingMessageOut(
        id=m.id,
        listing_id=m.listing_id,
        sender_id=m.sender_id,
        sender_name=sender_name,
        peer_id=peer_id,
        body=m.body,
        is_read=bool(m.is_read),
        created_at=m.created_at,
        is_mine=m.sender_id == user_id,
        kind=(m.kind or "text"),
        call_id=m.call_id,
    )


def emit_listing_chat(db: Session, msg: ListingMessage, user_ids: tuple[int, ...] | list[int]) -> None:
    """Живое сообщение в тот же сокет, что и звонок."""
    sender = db.get(User, msg.sender_id)
    listing = db.get(Listing, msg.listing_id)
    name = sender.full_name if sender else None
    seen: set[int] = set()
    for uid in user_ids:
        if not uid or uid in seen:
            continue
        seen.add(uid)
        peer = None
        if listing is not None:
            peer = msg.buyer_id if uid == listing.author_id else listing.author_id
        hub.emit(
            uid,
            {
                "type": "chat",
                "listing_id": msg.listing_id,
                "buyer_id": msg.buyer_id,
                "message": to_listing_message_out(
                    msg, user_id=uid, sender_name=name, peer_id=peer
                ).model_dump(mode="json"),
            },
        )


def emit_chat_read(listing_id: int, buyer_id: int, reader_id: int, other_id: int | None) -> None:
    if not other_id or other_id == reader_id:
        return
    hub.emit(
        other_id,
        {
            "type": "chat_read",
            "listing_id": listing_id,
            "buyer_id": buyer_id,
            "reader_id": reader_id,
        },
    )


def image_url(path: str) -> str:
    return f"/uploads/{path.replace(chr(92), '/')}"


def count_active_listings(db: Session, user_id: int, exclude_id: int | None = None) -> int:
    stmt = select(func.count()).select_from(Listing).where(
        Listing.author_id == user_id,
        Listing.status.in_([ListingStatus.pending, ListingStatus.approved]),
    )
    if exclude_id is not None:
        stmt = stmt.where(Listing.id != exclude_id)
    return int(db.execute(stmt).scalar_one())


def ensure_active_slot(db: Session, user_id: int, exclude_id: int | None = None) -> None:
    if count_active_listings(db, user_id, exclude_id=exclude_id) >= MAX_ACTIVE_LISTINGS:
        raise HTTPException(
            status_code=400,
            detail=f"Лимит активных объявлений: {MAX_ACTIVE_LISTINGS}. Снимите или дождитесь решения по текущим.",
        )


def snapshot_listing(item: Listing) -> str:
    return json.dumps(
        {
            "title": item.title,
            "description": item.description,
            "category": item.category.value if hasattr(item.category, "value") else str(item.category),
            "price": item.price,
            "contact_phone": item.contact_phone,
            "is_urgent": bool(getattr(item, "is_urgent", False)),
        },
        ensure_ascii=False,
    )


def parse_snapshot(raw: str | None) -> ListingSnapshot | None:
    if not raw:
        return None
    try:
        data = json.loads(raw)
        return ListingSnapshot(**data)
    except (TypeError, ValueError, json.JSONDecodeError):
        return None


def apply_blacklist_flag(db: Session, item: Listing) -> list[str]:
    hits = match_blacklist(
        db,
        title=item.title or "",
        description=item.description or "",
        phone=item.contact_phone or (item.author.phone if item.author else None),
    )
    item.auto_flagged = bool(hits)
    if hits:
        note = "Автофлаг: " + "; ".join(hits)
        if item.moderation_note:
            if "Автофлаг:" not in item.moderation_note:
                item.moderation_note = f"{note} | {item.moderation_note}"
        else:
            item.moderation_note = note
    return hits


def to_out(
    item: Listing,
    favorited_ids: set[int] | None = None,
    viewer: User | None = None,
    reveal_phone: bool = False,
    distance_km: float | None = None,
) -> ListingOut:
    images = [
        ListingImageOut(id=img.id, url=image_url(img.path), sort_order=img.sort_order)
        for img in (item.images or [])
    ]
    raw_phone = item.contact_phone or (item.author.phone if item.author else None)
    is_staff = bool(viewer and viewer.role in (UserRole.admin, UserRole.moderator))
    is_author = bool(viewer and viewer.id == item.author_id)
    show_phone = bool(raw_phone) and (reveal_phone or is_staff or is_author)
    return ListingOut(
        id=item.id,
        author_id=item.author_id,
        author_name=item.author.full_name if item.author else None,
        author_badge=getattr(item.author, "badge", None) if item.author else None,
        author_rating=getattr(item.author, "rating_score", None) if item.author else None,
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        category=item.category,
        title=item.title,
        description=item.description,
        price=item.price,
        contact_phone=raw_phone if show_phone else None,
        phone_hidden=bool(raw_phone) and not show_phone,
        status=item.status,
        moderation_note=item.moderation_note,
        close_reason=item.close_reason,
        close_note=item.close_note,
        is_urgent=bool(getattr(item, "is_urgent", False)),
        is_pinned=bool(getattr(item, "is_pinned", False)),
        auto_flagged=bool(getattr(item, "auto_flagged", False)),
        previous_snapshot=parse_snapshot(getattr(item, "previous_snapshot", None)),
        images=images,
        is_favorited=bool(favorited_ids and item.id in favorited_ids),
        created_at=item.created_at,
        updated_at=item.updated_at,
        distance_km=distance_km,
        lifetime_days=int(getattr(item, "lifetime_days", None) or 30),
        expires_at=getattr(item, "expires_at", None),
    )


def load_listing(db: Session, listing_id: int) -> Listing | None:
    return db.execute(
        select(Listing)
        .options(
            selectinload(Listing.author),
            selectinload(Listing.settlement),
            selectinload(Listing.images),
        )
        .where(Listing.id == listing_id)
    ).scalar_one_or_none()


def favorite_ids_for(db: Session, user: User | None) -> set[int]:
    if not user:
        return set()
    rows = db.execute(select(Favorite.listing_id).where(Favorite.user_id == user.id)).scalars().all()
    return set(rows)


def normalize_lifetime(days: int | None) -> int:
    return 60 if days == 60 else 30


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def set_expiry_from(item: Listing, start: datetime, days: int | None = None) -> None:
    life = normalize_lifetime(days if days is not None else getattr(item, "lifetime_days", 30))
    item.lifetime_days = life
    item.expires_at = start + timedelta(days=life)


def archive_expired_listings(db: Session) -> None:
    now = utcnow()
    rows = db.execute(
        select(Listing).where(
            Listing.status == ListingStatus.approved,
            Listing.expires_at.is_not(None),
            Listing.expires_at <= now,
        )
    ).scalars().all()
    if not rows:
        return
    for item in rows:
        item.status = ListingStatus.archived
        item.close_reason = "expired"
        item.close_note = CLOSE_REASON_LABELS["expired"]
        item.is_pinned = False
    db.commit()


def author_replied_to_buyer(db: Session, listing: Listing, viewer: User | None) -> bool:
    if not viewer or viewer.id == listing.author_id:
        return False
    found = db.execute(
        select(ListingMessage.id)
        .where(
            ListingMessage.listing_id == listing.id,
            ListingMessage.buyer_id == viewer.id,
            ListingMessage.sender_id == listing.author_id,
        )
        .limit(1)
    ).scalar_one_or_none()
    return found is not None


@router.get("/admin/all", response_model=ListingPageOut)
def admin_list_listings(
    status_filter: ListingStatus | None = Query(default=None, alias="status"),
    q: str | None = None,
    closed_by_user: bool = False,
    auto_flagged: bool | None = None,
    settlement_id: int | None = None,
    author_id: int | None = None,
    category: ListingCategory | None = None,
    sort: str = Query(default="newest", pattern="^(newest|sla)$"),
    over24: bool = False,
    limit: int = Query(default=400, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    stmt = select(Listing).options(
        selectinload(Listing.author),
        selectinload(Listing.settlement),
        selectinload(Listing.images),
    )
    if status_filter:
        stmt = stmt.where(Listing.status == status_filter)
    if closed_by_user:
        stmt = stmt.where(Listing.status == ListingStatus.archived, Listing.close_reason.is_not(None))
    if auto_flagged is not None:
        stmt = stmt.where(Listing.auto_flagged.is_(auto_flagged))
    if settlement_id is not None:
        stmt = stmt.where(Listing.settlement_id == settlement_id)
    if author_id is not None:
        stmt = stmt.where(Listing.author_id == author_id)
    if category is not None:
        stmt = stmt.where(Listing.category == category)
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.join(Listing.author).where(
            or_(
                Listing.title.ilike(like),
                Listing.description.ilike(like),
                User.full_name.ilike(like),
                User.email.ilike(like),
                User.phone.ilike(like),
                Listing.contact_phone.ilike(like),
            )
        )
    if over24:
        stmt = stmt.where(Listing.created_at < datetime.now(timezone.utc) - timedelta(hours=24))
    if sort == "sla" or status_filter == ListingStatus.pending:
        stmt = stmt.order_by(Listing.auto_flagged.desc(), Listing.created_at.asc())
    else:
        stmt = stmt.order_by(Listing.created_at.desc())
    total = int(
        db.execute(select(func.count()).select_from(stmt.with_only_columns(Listing.id).order_by(None).subquery())).scalar_one()
    )
    rows = db.execute(stmt.offset(offset).limit(limit)).scalars().unique().all()
    return ListingPageOut(
        items=[to_out(r, viewer=user) for r in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/mine/stats")
def my_listing_stats(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    active = count_active_listings(db, user.id)
    by_status = dict(
        db.execute(
            select(Listing.status, func.count())
            .where(Listing.author_id == user.id)
            .group_by(Listing.status)
        ).all()
    )
    return {
        "active": active,
        "max_active": MAX_ACTIVE_LISTINGS,
        "draft": int(by_status.get(ListingStatus.draft, 0)),
        "pending": int(by_status.get(ListingStatus.pending, 0)),
        "approved": int(by_status.get(ListingStatus.approved, 0)),
        "rejected": int(by_status.get(ListingStatus.rejected, 0)),
        "archived": int(by_status.get(ListingStatus.archived, 0)),
    }


@router.get("/favorites", response_model=list[ListingOut])
def list_favorites(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    stmt = (
        select(Listing)
        .join(Favorite, Favorite.listing_id == Listing.id)
        .where(Favorite.user_id == user.id)
        .options(
            selectinload(Listing.author),
            selectinload(Listing.settlement),
            selectinload(Listing.images),
        )
        .order_by(Favorite.created_at.desc())
    )
    fav_ids = favorite_ids_for(db, user)
    return [to_out(r, fav_ids, viewer=user) for r in db.execute(stmt).scalars().unique().all()]


@router.get("/conversations", response_model=list[ConversationOut])
def list_conversations(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Личные чаты 1-на-1: тред = объявление + покупатель."""
    as_buyer = (
        select(ListingMessage.listing_id, ListingMessage.buyer_id)
        .where(ListingMessage.buyer_id == user.id)
        .distinct()
    )
    as_seller = (
        select(ListingMessage.listing_id, ListingMessage.buyer_id)
        .join(Listing, Listing.id == ListingMessage.listing_id)
        .where(Listing.author_id == user.id, ListingMessage.buyer_id.is_not(None))
        .distinct()
    )
    pairs: set[tuple[int, int]] = set()
    for lid, bid in db.execute(as_buyer).all():
        if lid is not None and bid is not None:
            pairs.add((int(lid), int(bid)))
    for lid, bid in db.execute(as_seller).all():
        if lid is not None and bid is not None:
            pairs.add((int(lid), int(bid)))
    if not pairs:
        return []

    listing_ids = {lid for lid, _ in pairs}
    listings = {
        row.id: row
        for row in db.execute(
            select(Listing).options(selectinload(Listing.author)).where(Listing.id.in_(listing_ids))
        ).scalars().all()
    }
    peer_ids = {bid for _, bid in pairs} | {listings[lid].author_id for lid in listing_ids if lid in listings}
    peers = {
        u.id: u
        for u in db.execute(select(User).where(User.id.in_(peer_ids))).scalars().all()
    }

    result: list[ConversationOut] = []
    for lid, buyer_id in pairs:
        item = listings.get(lid)
        if not item:
            continue
        msgs = db.execute(
            select(ListingMessage)
            .where(ListingMessage.listing_id == lid, ListingMessage.buyer_id == buyer_id)
            .order_by(ListingMessage.created_at.desc())
        ).scalars().all()
        if not msgs:
            continue
        last = msgs[0]
        unread = sum(1 for m in msgs if m.sender_id != user.id and not m.is_read)
        is_seller = item.author_id == user.id
        peer_id = buyer_id if is_seller else item.author_id
        peer = peers.get(peer_id)
        result.append(
            ConversationOut(
                listing_id=item.id,
                peer_id=peer_id,
                listing_title=item.title,
                listing_status=item.status.value if hasattr(item.status, "value") else str(item.status),
                peer_name=peer.full_name if peer else None,
                last_message=last.body,
                last_message_at=last.created_at,
                unread_count=unread,
                is_seller=is_seller,
                last_kind=(last.kind or "text"),
            )
        )
    result.sort(
        key=lambda c: c.last_message_at.timestamp() if c.last_message_at else 0,
        reverse=True,
    )
    return result


@router.get("/reports/against-me", response_model=list[AuthorReportOut])
def reports_against_me(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    rows = db.execute(
        select(ListingReport, Listing)
        .join(Listing, Listing.id == ListingReport.listing_id)
        .where(Listing.author_id == user.id)
        .order_by(ListingReport.created_at.desc())
        .limit(100)
    ).all()
    return [
        AuthorReportOut(
            id=rep.id,
            listing_id=listing.id,
            listing_title=listing.title,
            reason=rep.reason,
            note=rep.note,
            status=rep.status,
            moderator_reply=rep.moderator_reply,
            created_at=rep.created_at,
            reviewed_at=rep.reviewed_at,
        )
        for rep, listing in rows
    ]


@router.get("", response_model=ListingPageOut)
def list_listings(
    category: ListingCategory | None = None,
    settlement_id: int | None = None,
    q: str | None = None,
    sort: str = Query(default="newest", pattern="^(newest|oldest|price_asc|price_desc|near)$"),
    mine: bool = False,
    author_id: int | None = None,
    has_photos: bool | None = None,
    price_min: float | None = Query(default=None, ge=0),
    price_max: float | None = Query(default=None, ge=0),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lon: float | None = Query(default=None, ge=-180, le=180),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    archive_expired_listings(db)
    if price_min is not None and price_max is not None and price_min > price_max:
        raise HTTPException(status_code=400, detail="Цена «от» больше цены «до»")
    stmt = select(Listing).options(
        selectinload(Listing.author),
        selectinload(Listing.settlement),
        selectinload(Listing.images),
    )
    if mine:
        if not user:
            raise HTTPException(status_code=401, detail="Требуется авторизация")
        stmt = stmt.where(Listing.author_id == user.id)
    else:
        stmt = stmt.where(Listing.status == ListingStatus.approved)
        if author_id is not None:
            stmt = stmt.where(Listing.author_id == author_id)
    origin = resolve_origin(db, lat, lon, settlement_id) if sort == "near" else None
    if sort == "near" and origin is None:
        raise HTTPException(status_code=400, detail="Для «рядом» нужны геолокация или выбранное село")
    near_filter_settlement = False if sort == "near" else True
    if category:
        stmt = stmt.where(Listing.category == category)
    if settlement_id and near_filter_settlement:
        stmt = stmt.where(Listing.settlement_id == settlement_id)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(Listing.title.ilike(like) | Listing.description.ilike(like))
    if has_photos is True:
        stmt = stmt.where(exists().where(ListingImage.listing_id == Listing.id))
    elif has_photos is False:
        stmt = stmt.where(~exists().where(ListingImage.listing_id == Listing.id))
    if price_min is not None:
        stmt = stmt.where(Listing.price.is_not(None), Listing.price >= price_min)
    if price_max is not None:
        stmt = stmt.where(Listing.price.is_not(None), Listing.price <= price_max)
    price_nulls = case((Listing.price.is_(None), 1), else_=0)
    if sort == "near" and origin is not None:
        olat, olon = origin
        dist = (Settlement.lat - olat) * (Settlement.lat - olat) + (Settlement.lon - olon) * (Settlement.lon - olon)
        stmt = stmt.join(Settlement, Settlement.id == Listing.settlement_id).order_by(
            Listing.is_pinned.desc(),
            case((Settlement.lat.is_(None), 1), else_=0).asc(),
            dist.asc(),
            Listing.created_at.desc(),
        )
    elif sort == "oldest":
        stmt = stmt.order_by(Listing.is_pinned.desc(), Listing.created_at.asc())
    elif sort == "price_asc":
        stmt = stmt.order_by(Listing.is_pinned.desc(), price_nulls.asc(), Listing.price.asc(), Listing.created_at.desc())
    elif sort == "price_desc":
        stmt = stmt.order_by(Listing.is_pinned.desc(), price_nulls.asc(), Listing.price.desc(), Listing.created_at.desc())
    else:
        stmt = stmt.order_by(Listing.is_pinned.desc(), Listing.created_at.desc())

    count_stmt = select(func.count()).select_from(Listing)
    if mine:
        count_stmt = count_stmt.where(Listing.author_id == user.id)
    else:
        count_stmt = count_stmt.where(Listing.status == ListingStatus.approved)
        if author_id is not None:
            count_stmt = count_stmt.where(Listing.author_id == author_id)
    if category:
        count_stmt = count_stmt.where(Listing.category == category)
    if settlement_id and near_filter_settlement:
        count_stmt = count_stmt.where(Listing.settlement_id == settlement_id)
    if q:
        like = f"%{q.strip()}%"
        count_stmt = count_stmt.where(Listing.title.ilike(like) | Listing.description.ilike(like))
    if has_photos is True:
        count_stmt = count_stmt.where(exists().where(ListingImage.listing_id == Listing.id))
    elif has_photos is False:
        count_stmt = count_stmt.where(~exists().where(ListingImage.listing_id == Listing.id))
    if price_min is not None:
        count_stmt = count_stmt.where(Listing.price.is_not(None), Listing.price >= price_min)
    if price_max is not None:
        count_stmt = count_stmt.where(Listing.price.is_not(None), Listing.price <= price_max)
    total = int(db.execute(count_stmt).scalar_one())

    stmt = stmt.offset(offset).limit(limit)
    fav_ids = favorite_ids_for(db, user)
    items = []
    for r in db.execute(stmt).scalars().unique().all():
        dist_km = None
        if origin is not None and r.settlement is not None and r.settlement.lat is not None and r.settlement.lon is not None:
            dist_km = round(haversine_km(origin[0], origin[1], r.settlement.lat, r.settlement.lon), 1)
        items.append(to_out(r, fav_ids, viewer=user, distance_km=dist_km))
    return ListingPageOut(items=items, total=total, limit=limit, offset=offset)


@router.get("/{listing_id}", response_model=ListingOut)
def get_listing(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    archive_expired_listings(db)
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.status != ListingStatus.approved:
        if not user or (user.id != item.author_id and user.role not in (UserRole.admin, UserRole.moderator)):
            raise HTTPException(status_code=404, detail="Объявление не найдено")
    reveal = author_replied_to_buyer(db, item, user)
    return to_out(item, favorite_ids_for(db, user), viewer=user, reveal_phone=reveal)


@router.post("", response_model=ListingOut)
def create_listing(
    payload: ListingCreate,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    ip = (request.client.host if request.client else "unknown") or "unknown"
    if not limiter.allow(f"listing-create:{user.id}:{ip}", limit=20, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много объявлений за час. Попробуйте позже")
    data = payload.model_dump()
    as_draft = bool(data.pop("as_draft", False))
    lifetime_days = normalize_lifetime(data.pop("lifetime_days", 30))
    if data.get("price") is not None and data["price"] < 0:
        raise HTTPException(status_code=400, detail="Цена не может быть отрицательной")
    if not as_draft:
        ensure_active_slot(db, user.id)
    item = Listing(
        author_id=user.id,
        settlement_id=data["settlement_id"],
        category=data["category"],
        title=data["title"].strip(),
        description=data["description"].strip(),
        price=data.get("price"),
        contact_phone=data.get("contact_phone"),
        is_urgent=bool(data.get("is_urgent", False)),
        lifetime_days=lifetime_days,
        status=ListingStatus.draft if as_draft else ListingStatus.pending,
    )
    db.add(item)
    db.flush()
    if not as_draft:
        apply_blacklist_flag(db, item)
    db.commit()
    item = load_listing(db, item.id)
    return to_out(item, favorite_ids_for(db, user))


@router.patch("/{listing_id}", response_model=ListingOut)
def update_listing(
    listing_id: int,
    payload: ListingUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    is_staff = user.role in (UserRole.admin, UserRole.moderator)
    if item.author_id != user.id and not is_staff:
        raise HTTPException(status_code=403, detail="Нет доступа")
    data = payload.model_dump(exclude_unset=True)
    as_draft = data.pop("as_draft", None)
    if "lifetime_days" in data:
        data["lifetime_days"] = normalize_lifetime(data.get("lifetime_days"))
    if "title" in data and isinstance(data["title"], str):
        data["title"] = data["title"].strip()
    if "description" in data and isinstance(data["description"], str):
        data["description"] = data["description"].strip()
    if "contact_phone" in data:
        data["contact_phone"] = (data["contact_phone"] or "").strip() or None
    if "settlement_id" in data and data["settlement_id"] is not None:
        settlement = db.execute(select(Settlement.id).where(Settlement.id == data["settlement_id"])).scalar_one_or_none()
        if settlement is None:
            raise HTTPException(status_code=400, detail="Населённый пункт не найден")
    was_approved = item.status == ListingStatus.approved
    if was_approved and item.author_id == user.id and not is_staff and as_draft is not True:
        item.previous_snapshot = snapshot_listing(item)
    changed = sorted(data.keys())
    for key, value in data.items():
        setattr(item, key, value)
    if is_staff:
        log_action(
            db,
            actor=user,
            action="listing.update",
            entity_type="listing",
            entity_id=item.id,
            details=f"{item.title}; fields={','.join(changed) or '—'}",
        )
    elif item.author_id == user.id:
        if as_draft is True:
            item.status = ListingStatus.draft
        else:
            if item.status not in (ListingStatus.pending, ListingStatus.approved):
                ensure_active_slot(db, user.id, exclude_id=item.id)
            item.status = ListingStatus.pending
        item.close_reason = None
        item.close_note = None
        if as_draft is not True:
            item.moderation_note = None
            apply_blacklist_flag(db, item)
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user), viewer=user)


@router.post("/{listing_id}/close", response_model=ListingOut)
def close_listing(
    listing_id: int,
    payload: ListingCloseIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    item.status = ListingStatus.archived
    item.close_reason = payload.reason
    item.close_note = (payload.note or "").strip() or CLOSE_REASON_LABELS.get(payload.reason)
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user), viewer=user)


@router.post("/{listing_id}/extend", response_model=ListingOut)
def extend_listing(
    listing_id: int,
    payload: ListingExtendIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    archive_expired_listings(db)
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    days = normalize_lifetime(payload.days)
    now = utcnow()
    if item.status == ListingStatus.approved:
        base = item.expires_at if item.expires_at and item.expires_at > now else now
        set_expiry_from(item, base, days)
    elif item.status == ListingStatus.archived and item.close_reason == "expired":
        ensure_active_slot(db, user.id, exclude_id=item.id)
        item.status = ListingStatus.approved
        item.close_reason = None
        item.close_note = None
        set_expiry_from(item, now, days)
    else:
        raise HTTPException(
            status_code=400,
            detail="Продлить можно опубликованное объявление или снятое по сроку. Остальные — через «Снова».",
        )
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user), viewer=user)


@router.post("/{listing_id}/republish", response_model=ListingOut)
def republish_listing(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id:
        raise HTTPException(status_code=403, detail="Нет доступа")
    if item.status not in (ListingStatus.archived, ListingStatus.rejected, ListingStatus.draft):
        raise HTTPException(status_code=400, detail="Повторно опубликовать можно черновик, снятое или отклонённое")
    ensure_active_slot(db, user.id, exclude_id=item.id)
    item.status = ListingStatus.pending
    item.close_reason = None
    item.close_note = None
    item.moderation_note = None
    apply_blacklist_flag(db, item)
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{listing_id}/favorite", response_model=ListingOut)
def add_favorite(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item or item.status != ListingStatus.approved:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    exists = db.execute(
        select(Favorite).where(Favorite.user_id == user.id, Favorite.listing_id == listing_id)
    ).scalar_one_or_none()
    if not exists:
        db.add(Favorite(user_id=user.id, listing_id=listing_id))
        db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user))


@router.delete("/{listing_id}/favorite", response_model=ListingOut)
def remove_favorite(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    fav = db.execute(
        select(Favorite).where(Favorite.user_id == user.id, Favorite.listing_id == listing_id)
    ).scalar_one_or_none()
    if fav:
        db.delete(fav)
        db.commit()
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    return to_out(item, favorite_ids_for(db, user))


@router.delete("/{listing_id}")
def delete_listing(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    is_staff = user.role in (UserRole.admin, UserRole.moderator)
    if item.author_id != user.id and not is_staff:
        raise HTTPException(status_code=403, detail="Нет доступа")
    if item.author_id == user.id and not is_staff:
        if item.status not in (ListingStatus.draft, ListingStatus.rejected, ListingStatus.archived):
            raise HTTPException(
                status_code=400,
                detail="Можно удалить черновик, отклонённое или снятое. Опубликованное сначала снимите",
            )
    for img in list(item.images or []):
        path = UPLOAD_ROOT / img.path
        if path.exists():
            try:
                path.unlink()
            except OSError:
                pass
        db.delete(img)
    for fav in db.execute(select(Favorite).where(Favorite.listing_id == listing_id)).scalars().all():
        db.delete(fav)
    for report in db.execute(select(ListingReport).where(ListingReport.listing_id == listing_id)).scalars().all():
        db.delete(report)
    for urep in db.execute(select(UserReport).where(UserReport.listing_id == listing_id)).scalars().all():
        urep.listing_id = None
    log_action(
        db,
        actor=user,
        action="listing.delete",
        entity_type="listing",
        entity_id=item.id,
        details=item.title,
    )
    db.delete(item)
    db.commit()
    return {"ok": True}


@router.post("/{listing_id}/report")
def report_listing(
    listing_id: int,
    payload: ListingReportIn,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    ip = (request.client.host if request.client else "unknown") or "unknown"
    if not limiter.allow(f"report:{user.id}:{ip}", limit=15, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много жалоб. Попробуйте позже")
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id == user.id:
        raise HTTPException(status_code=400, detail="Нельзя пожаловаться на своё объявление")
    recent = db.execute(
        select(ListingReport).where(
            ListingReport.listing_id == listing_id,
            ListingReport.reporter_id == user.id,
            ListingReport.status == "open",
        )
    ).scalar_one_or_none()
    if recent:
        raise HTTPException(status_code=400, detail="Жалоба уже отправлена")
    db.add(
        ListingReport(
            listing_id=listing_id,
            reporter_id=user.id,
            reason=payload.reason,
            note=(payload.note or "").strip() or None,
            status="open",
        )
    )
    db.flush()
    notify_user(
        db,
        user_id=item.author_id,
        type="listing_reported",
        title="На ваше объявление пожаловались",
        body=f'"{item.title}" проверят модераторы',
        listing_id=item.id,
    )
    author = db.execute(select(User).where(User.id == item.author_id)).scalar_one()
    maybe_autoban_from_listing_reports(db, author)
    db.commit()
    return {"ok": True}


def _resolve_thread_buyer_id(item: Listing, user: User, peer_id: int | None) -> int:
    """buyer_id треда: покупатель всегда не автор объявления."""
    if user.id == item.author_id:
        if peer_id is None:
            raise HTTPException(status_code=400, detail="Укажите собеседника (peer_id)")
        if peer_id == item.author_id:
            raise HTTPException(status_code=400, detail="Нельзя писать самому себе")
        return peer_id
    return user.id


@router.get("/{listing_id}/messages", response_model=list[ListingMessageOut])
def list_messages(
    listing_id: int,
    peer_id: int | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if user.id != item.author_id and user.role not in (UserRole.admin, UserRole.moderator):
        if item.status != ListingStatus.approved and user.id != item.author_id:
            raise HTTPException(status_code=403, detail="Нет доступа")
    buyer_id = _resolve_thread_buyer_id(item, user, peer_id)
    # продавец видит тред только если он автор
    if user.id != item.author_id and buyer_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    if user.id == item.author_id and buyer_id == item.author_id:
        raise HTTPException(status_code=400, detail="Некорректный собеседник")

    msgs = db.execute(
        select(ListingMessage)
        .where(ListingMessage.listing_id == listing_id, ListingMessage.buyer_id == buyer_id)
        .order_by(ListingMessage.created_at.asc())
    ).scalars().all()
    marked = False
    for m in msgs:
        if m.sender_id != user.id and not m.is_read:
            m.is_read = True
            marked = True
    if marked:
        db.commit()
        other_id = item.author_id if user.id == buyer_id else buyer_id
        emit_chat_read(listing_id, buyer_id, user.id, other_id)
    names: dict[int, str | None] = {}
    for m in msgs:
        if m.sender_id not in names:
            u = db.execute(select(User).where(User.id == m.sender_id)).scalar_one_or_none()
            names[m.sender_id] = u.full_name if u else None
    peer_for_client = buyer_id if user.id == item.author_id else item.author_id
    return [
        to_listing_message_out(
            m,
            user_id=user.id,
            sender_name=names.get(m.sender_id),
            peer_id=peer_for_client,
        )
        for m in msgs
    ]


@router.post("/{listing_id}/messages", response_model=ListingMessageOut)
def post_message(
    listing_id: int,
    payload: ListingMessageIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item or item.status != ListingStatus.approved:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    body = payload.body.strip()
    if not body:
        raise HTTPException(status_code=400, detail="Пустое сообщение")
    hits = match_blacklist(db, title="", description=body)
    if hits:
        raise HTTPException(status_code=400, detail="Сообщение отклонено: запрещённые слова или контакты")
    if looks_like_chat_spam(body):
        raise HTTPException(
            status_code=400,
            detail="Сообщение похоже на спам. Уберите ссылки и рекламу — пишите по делу объявления",
        )
    if not limiter.allow(f"chat-day:{user.id}", limit=50, window_sec=86400):
        raise HTTPException(
            status_code=429,
            detail="Лимит сообщений на сегодня (50). Напишите завтра — без капчи, просто пауза от спама.",
        )
    buyer_id = _resolve_thread_buyer_id(item, user, payload.peer_id)
    if user.id == item.author_id:
        # продавец отвечает только в существующий или явный тред с покупателем
        exists_buyer = db.execute(select(User.id).where(User.id == buyer_id)).scalar_one_or_none()
        if not exists_buyer:
            raise HTTPException(status_code=404, detail="Собеседник не найден")
    msg = ListingMessage(
        listing_id=listing_id,
        sender_id=user.id,
        buyer_id=buyer_id,
        body=body,
        kind="text",
    )
    db.add(msg)
    db.flush()
    target = item.author_id if user.id == buyer_id else buyer_id
    if target and target != user.id:
        # Пуш на телефон, без записи в колокольчик — непрочитанные идут на вкладку «Чаты».
        push_user(
            db,
            user_id=target,
            title=user.full_name or "Сообщение",
            body=body[:120],
            data={
                "type": "listing_message",
                "listing_id": str(item.id),
                "buyer_id": str(buyer_id),
                "message_id": str(msg.id),
            },
        )
    db.commit()
    db.refresh(msg)
    emit_listing_chat(db, msg, (user.id, target) if target else (user.id,))
    peer_for_client = buyer_id if user.id == item.author_id else item.author_id
    return to_listing_message_out(
        msg,
        user_id=user.id,
        sender_name=user.full_name,
        peer_id=peer_for_client,
    )


@router.post("/{listing_id}/images", response_model=ListingOut)
async def upload_listing_images(
    listing_id: int,
    files: list[UploadFile] = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")

    current = len(item.images or [])
    if current >= MAX_IMAGES:
        raise HTTPException(status_code=400, detail=f"Максимум {MAX_IMAGES} фото")
    if not files:
        raise HTTPException(status_code=400, detail="Нет файлов")

    folder = UPLOAD_ROOT / "listings" / str(listing_id)
    folder.mkdir(parents=True, exist_ok=True)
    next_order = current

    for upload in files:
        if current + 1 > MAX_IMAGES:
            break
        content_type = (upload.content_type or "").lower()
        ext = ALLOWED_TYPES.get(content_type)
        data = await upload.read()
        if not data:
            continue
        if len(data) > MAX_IMAGE_BYTES:
            raise HTTPException(status_code=400, detail="Фото больше 6 МБ")
        # magic bytes — не доверяем только Content-Type
        if data[:3] == b"\xff\xd8\xff":
            ext = ".jpg"
        elif data[:8] == b"\x89PNG\r\n\x1a\n":
            ext = ".png"
        elif len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
            ext = ".webp"
        elif not ext:
            raise HTTPException(status_code=400, detail="Допустимы JPG, PNG, WEBP")
        filename = f"{uuid.uuid4().hex}{ext}"
        rel = f"listings/{listing_id}/{filename}"
        (UPLOAD_ROOT / rel).write_bytes(data)
        db.add(ListingImage(listing_id=listing_id, path=rel, sort_order=next_order))
        next_order += 1
        current += 1

    if item.author_id == user.id and user.role not in (UserRole.admin, UserRole.moderator) and item.status == ListingStatus.approved:
        item.status = ListingStatus.pending

    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user), viewer=user)


@router.delete("/{listing_id}/images/{image_id}", response_model=ListingOut)
def delete_listing_image(
    listing_id: int,
    image_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    image = next((img for img in item.images if img.id == image_id), None)
    if not image:
        raise HTTPException(status_code=404, detail="Фото не найдено")
    file_path = UPLOAD_ROOT / image.path
    if file_path.exists():
        file_path.unlink()
    db.delete(image)
    if item.author_id == user.id and user.role not in (UserRole.admin, UserRole.moderator) and item.status == ListingStatus.approved:
        item.status = ListingStatus.pending
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user), viewer=user)


@router.patch("/{listing_id}/images/reorder", response_model=ListingOut)
def reorder_listing_images(
    listing_id: int,
    payload: ListingImagesReorderIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    by_id = {img.id: img for img in (item.images or [])}
    if len(payload.image_ids) != len(by_id) or set(payload.image_ids) != set(by_id):
        raise HTTPException(status_code=400, detail="Список фото не совпадает с объявлением")
    for order, image_id in enumerate(payload.image_ids):
        by_id[image_id].sort_order = order
    if item.author_id == user.id and user.role not in (UserRole.admin, UserRole.moderator) and item.status == ListingStatus.approved:
        item.status = ListingStatus.pending
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user), viewer=user)


@router.post("/{listing_id}/pin", response_model=ListingOut)
def pin_listing(
    listing_id: int,
    payload: ListingPinIn,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if payload.pinned:
        if item.status != ListingStatus.approved:
            raise HTTPException(status_code=400, detail="Закрепить можно только опубликованное")
        pinned = db.execute(select(Listing).where(Listing.is_pinned.is_(True))).scalars().all()
        for row in pinned:
            row.is_pinned = False
        item.is_pinned = True
    else:
        item.is_pinned = False
    log_action(
        db,
        actor=user,
        action="listing.pin" if payload.pinned else "listing.unpin",
        entity_type="listing",
        entity_id=item.id,
        details=item.title,
    )
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item)


@router.post("/{listing_id}/moderate", response_model=ListingOut)
def moderate_listing(
    listing_id: int,
    payload: ListingModerationIn,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    if payload.status not in (ListingStatus.approved, ListingStatus.rejected, ListingStatus.archived):
        raise HTTPException(status_code=400, detail="Недопустимый статус модерации")
    if payload.status == ListingStatus.rejected and not (payload.moderation_note or "").strip():
        raise HTTPException(status_code=400, detail="Укажите причину отклонения")
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    old = item.status.value
    if payload.status in (ListingStatus.approved, ListingStatus.rejected) and item.status != ListingStatus.pending:
        labels = {
            ListingStatus.approved: "уже опубликовано",
            ListingStatus.rejected: "уже отклонено",
            ListingStatus.archived: "уже снято",
            ListingStatus.draft: "черновик",
            ListingStatus.pending: "на проверке",
        }
        raise HTTPException(
            status_code=400,
            detail=f"Объявление уже обработано ({labels.get(item.status, item.status.value)})",
        )
    item.status = payload.status
    item.moderation_note = payload.moderation_note
    if payload.status == ListingStatus.approved:
        item.auto_flagged = False
        item.previous_snapshot = None
        set_expiry_from(item, utcnow(), getattr(item, "lifetime_days", 30))
    if payload.status in (ListingStatus.rejected, ListingStatus.archived):
        item.is_pinned = False
    log_action(
        db,
        actor=user,
        action=f"moderate:{payload.status.value}",
        entity_type="listing",
        entity_id=item.id,
        details=f"{old} → {payload.status.value}; note={payload.moderation_note or ''}",
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
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item)


@router.post("/{listing_id}/admin-status", response_model=ListingOut)
def admin_set_listing_status(
    listing_id: int,
    payload: ListingAdminStatusIn,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    if payload.status not in (
        ListingStatus.draft,
        ListingStatus.pending,
        ListingStatus.approved,
        ListingStatus.rejected,
        ListingStatus.archived,
    ):
        raise HTTPException(status_code=400, detail="Недопустимый статус")
    if payload.status == ListingStatus.rejected and not (payload.moderation_note or "").strip():
        raise HTTPException(status_code=400, detail="Укажите причину отклонения")
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    old = item.status
    if payload.status in (ListingStatus.approved, ListingStatus.pending) and old not in (
        ListingStatus.approved,
        ListingStatus.pending,
    ):
        ensure_active_slot(db, item.author_id, exclude_id=item.id)
    item.status = payload.status
    if payload.moderation_note is not None:
        item.moderation_note = payload.moderation_note.strip() or None
    if payload.status == ListingStatus.approved:
        item.auto_flagged = False
        item.previous_snapshot = None
        item.close_reason = None
        item.close_note = None
        set_expiry_from(item, utcnow(), getattr(item, "lifetime_days", 30))
    elif payload.status == ListingStatus.archived:
        item.is_pinned = False
        item.close_reason = (payload.close_reason or "").strip() or "other"
        item.close_note = (payload.close_note or "").strip() or "Снято модератором"
    else:
        item.is_pinned = False
        item.close_reason = None
        item.close_note = None
    log_action(
        db,
        actor=user,
        action=f"listing.status:{payload.status.value}",
        entity_type="listing",
        entity_id=item.id,
        details=f"{old.value} → {payload.status.value}; note={payload.moderation_note or ''}",
    )
    if payload.status == ListingStatus.approved and old != ListingStatus.approved:
        notify_user(
            db,
            user_id=item.author_id,
            type="listing_approved",
            title="Объявление одобрено",
            body=f"«{item.title}» опубликовано и видно в ленте.",
            listing_id=item.id,
        )
    elif payload.status == ListingStatus.rejected and old != ListingStatus.rejected:
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
    elif payload.status == ListingStatus.archived and old != ListingStatus.archived:
        notify_user(
            db,
            user_id=item.author_id,
            type="listing_archived",
            title="Объявление снято",
            body=f"«{item.title}» снято модератором.",
            listing_id=item.id,
        )
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, viewer=user)
