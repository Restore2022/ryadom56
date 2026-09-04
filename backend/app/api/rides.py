from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.auth import avatar_url_for
from app.api.deps import get_current_user, get_optional_user, require_roles
from app.core.database import get_db
from app.models import Ride, RideMessage, RideReport, Settlement, User, UserRole
from app.schemas import (
    RideCloseIn,
    RideConversationOut,
    RideCreate,
    RideMessageIn,
    RideMessageOut,
    RideOut,
    RidePageOut,
    RideReportIn,
    RideUpdate,
)
from app.services.audit import log_action
from app.services.blacklist import looks_like_chat_spam, match_blacklist
from app.services.call_hub import hub
from app.services.notify import fcm_tokens_for_user, guest_push_tokens, notify_user, push_tokens, push_user
from app.services.rate_limit import limiter

router = APIRouter(prefix="/rides", tags=["rides"])

MAX_OPEN_RIDES = 3
MAX_NOTIFY = 80
REPORTS_TO_HIDE = 3
KIND_DRIVE = "drive"
KIND_NEED = "need"
STATUS_OPEN = "open"
STATUS_CLOSED = "closed"
STATUS_HIDDEN = "hidden"
CLOSE_LABELS = {
    "full": "Мест больше нет",
    "cancelled": "Поездка не состоится",
    "gone": "Уже уехали",
    "other": "Снято",
}


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def place_name(row: Settlement | None) -> str:
    if row is None:
        return "—"
    return (row.name or row.display_name or "—").strip() or "—"


def ride_title(item: Ride) -> str:
    return f"{place_name(item.from_place)} → {place_name(item.to_place)}"


def load_ride(db: Session, ride_id: int) -> Ride | None:
    return db.execute(
        select(Ride)
        .options(
            selectinload(Ride.author),
            selectinload(Ride.from_place),
            selectinload(Ride.to_place),
        )
        .where(Ride.id == ride_id)
    ).scalar_one_or_none()


def author_replied(db: Session, ride: Ride, viewer: User | None) -> bool:
    if not viewer or viewer.id == ride.author_id:
        return False
    found = db.execute(
        select(RideMessage.id)
        .where(
            RideMessage.ride_id == ride.id,
            RideMessage.passenger_id == viewer.id,
            RideMessage.sender_id == ride.author_id,
        )
        .limit(1)
    ).scalar_one_or_none()
    return found is not None


def to_out(item: Ride, viewer: User | None = None, *, reveal_phone: bool = False) -> RideOut:
    raw_phone = item.contact_phone or (item.author.phone if item.author else None)
    is_staff = bool(viewer and viewer.role in (UserRole.admin, UserRole.moderator))
    is_author = bool(viewer and viewer.id == item.author_id)
    show_phone = bool(raw_phone) and (reveal_phone or is_staff or is_author)
    return RideOut(
        id=item.id,
        kind=item.kind,
        from_settlement_id=item.from_settlement_id,
        to_settlement_id=item.to_settlement_id,
        from_name=place_name(item.from_place),
        to_name=place_name(item.to_place),
        title=ride_title(item),
        depart_at=item.depart_at,
        seats=item.seats,
        note=item.note,
        status=item.status,
        close_reason=item.close_reason,
        author_id=item.author_id,
        author_name=item.author.full_name if item.author else None,
        author_avatar_url=avatar_url_for(item.author.avatar_path) if item.author else None,
        contact_phone=raw_phone if show_phone else None,
        phone_hidden=bool(raw_phone) and not show_phone,
        is_mine=is_author,
        created_at=item.created_at,
    )


def to_message_out(m: RideMessage, *, user_id: int, sender_name: str | None, peer_id: int | None) -> RideMessageOut:
    return RideMessageOut(
        id=m.id,
        ride_id=m.ride_id,
        sender_id=m.sender_id,
        sender_name=sender_name,
        peer_id=peer_id,
        body=m.body,
        is_read=bool(m.is_read),
        created_at=m.created_at,
        is_mine=m.sender_id == user_id,
    )


def expire_old_rides(db: Session) -> None:
    cutoff = utcnow() - timedelta(hours=3)
    rows = db.execute(
        select(Ride).where(Ride.status == STATUS_OPEN, Ride.depart_at < cutoff)
    ).scalars().all()
    if not rows:
        return
    for row in rows:
        row.status = STATUS_CLOSED
        if not row.close_reason:
            row.close_reason = "gone"
    db.commit()


def count_open_rides(db: Session, user_id: int, exclude_id: int | None = None) -> int:
    stmt = select(func.count()).select_from(Ride).where(
        Ride.author_id == user_id,
        Ride.status == STATUS_OPEN,
        Ride.depart_at >= utcnow() - timedelta(hours=3),
    )
    if exclude_id is not None:
        stmt = stmt.where(Ride.id != exclude_id)
    return int(db.execute(stmt).scalar_one())


def require_settlement(db: Session, settlement_id: int) -> Settlement:
    row = db.get(Settlement, settlement_id)
    if row is None or not row.is_active:
        raise HTTPException(status_code=400, detail="Населённый пункт не найден")
    return row


def parse_depart(value: datetime) -> datetime:
    dt = value
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    now = utcnow()
    if dt < now - timedelta(minutes=20):
        raise HTTPException(status_code=400, detail="Время уже прошло. Укажите, когда выезжаете")
    if dt > now + timedelta(days=14):
        raise HTTPException(status_code=400, detail="Попутку можно поставить не дальше чем на две недели")
    return dt


def _resolve_passenger_id(ride: Ride, user: User, peer_id: int | None) -> int:
    if user.id == ride.author_id:
        if peer_id is None:
            raise HTTPException(status_code=400, detail="Укажите собеседника")
        if peer_id == ride.author_id:
            raise HTTPException(status_code=400, detail="Нельзя писать самому себе")
        return peer_id
    return user.id


def emit_ride_chat(db: Session, msg: RideMessage, ride: Ride, user_ids: tuple[int, ...] | list[int]) -> None:
    sender = db.get(User, msg.sender_id)
    name = sender.full_name if sender else None
    seen: set[int] = set()
    for uid in user_ids:
        if not uid or uid in seen:
            continue
        seen.add(uid)
        peer = msg.passenger_id if uid == ride.author_id else ride.author_id
        hub.emit(
            uid,
            {
                "type": "ride_chat",
                "ride_id": msg.ride_id,
                "passenger_id": msg.passenger_id,
                "message": to_message_out(
                    msg, user_id=uid, sender_name=name, peer_id=peer
                ).model_dump(mode="json"),
            },
        )


def emit_ride_read(ride_id: int, passenger_id: int, reader_id: int, other_id: int | None) -> None:
    if not other_id or other_id == reader_id:
        return
    hub.emit(
        other_id,
        {
            "type": "ride_chat_read",
            "ride_id": ride_id,
            "passenger_id": passenger_id,
            "reader_id": reader_id,
        },
    )


def notify_ride_created(db: Session, item: Ride) -> None:
    from_name = place_name(item.from_place)
    to_name = place_name(item.to_place)
    title = f"{from_name} → {to_name}"
    if item.kind == KIND_DRIVE:
        push_title = f"Едут {title}"
        seats_txt = "место" if item.seats == 1 else ("места" if item.seats in (2, 3, 4) else "мест")
        body = f"{item.seats} {seats_txt}. Напишите, если по пути."
    else:
        push_title = f"Ищут попутку {title}"
        who = "человек" if item.seats == 1 else "человека"
        body = f"{item.seats} {who}. Если едете — откликнитесь."
    ids = (
        db.execute(
            select(User.id)
            .where(
                User.is_active.is_(True),
                User.id != item.author_id,
                or_(User.badge.is_(None), User.badge != "feed"),
                User.settlement_id.in_([item.from_settlement_id, item.to_settlement_id]),
            )
            .limit(MAX_NOTIFY)
        )
        .scalars()
        .all()
    )
    extra = {"ride_id": str(item.id)}
    for uid in ids:
        notify_user(
            db,
            user_id=int(uid),
            type="ride_new",
            title=push_title,
            body=body,
            ride_id=item.id,
            extra=extra,
        )
    guest = guest_push_tokens(
        db,
        settlement_ids=[item.from_settlement_id, item.to_settlement_id],
        exclude=set(fcm_tokens_for_user(db, item.author_id)),
    )
    if guest:
        push_tokens(
            guest[:120],
            title=push_title,
            body=body,
            data={"type": "ride_new", "ride_id": str(item.id), "click_action": "FLUTTER_NOTIFICATION_CLICK"},
        )


@router.get("/conversations", response_model=list[RideConversationOut])
def list_ride_conversations(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    as_passenger = (
        select(RideMessage.ride_id, RideMessage.passenger_id)
        .where(RideMessage.passenger_id == user.id)
        .distinct()
    )
    as_author = (
        select(RideMessage.ride_id, RideMessage.passenger_id)
        .join(Ride, Ride.id == RideMessage.ride_id)
        .where(Ride.author_id == user.id)
        .distinct()
    )
    pairs: set[tuple[int, int]] = set()
    for rid, pid in db.execute(as_passenger).all():
        if rid is not None and pid is not None:
            pairs.add((int(rid), int(pid)))
    for rid, pid in db.execute(as_author).all():
        if rid is not None and pid is not None:
            pairs.add((int(rid), int(pid)))
    if not pairs:
        return []

    ride_ids = {rid for rid, _ in pairs}
    rides = {
        row.id: row
        for row in db.execute(
            select(Ride)
            .options(selectinload(Ride.author), selectinload(Ride.from_place), selectinload(Ride.to_place))
            .where(Ride.id.in_(ride_ids))
        ).scalars().all()
    }
    peer_ids = {pid for _, pid in pairs} | {rides[rid].author_id for rid in ride_ids if rid in rides}
    peers = {
        u.id: u
        for u in db.execute(select(User).where(User.id.in_(peer_ids))).scalars().all()
    }

    result: list[RideConversationOut] = []
    for rid, passenger_id in pairs:
        item = rides.get(rid)
        if not item:
            continue
        msgs = db.execute(
            select(RideMessage)
            .where(RideMessage.ride_id == rid, RideMessage.passenger_id == passenger_id)
            .order_by(RideMessage.created_at.desc())
        ).scalars().all()
        if not msgs:
            continue
        last = msgs[0]
        unread = sum(1 for m in msgs if m.sender_id != user.id and not m.is_read)
        is_driver = item.author_id == user.id
        peer_id = passenger_id if is_driver else item.author_id
        peer = peers.get(peer_id)
        result.append(
            RideConversationOut(
                ride_id=item.id,
                peer_id=peer_id,
                title=ride_title(item),
                ride_status=item.status,
                peer_name=peer.full_name if peer else None,
                last_message=(last.body or "")[:120],
                last_message_at=last.created_at,
                unread_count=unread,
                is_driver=is_driver,
            )
        )
    result.sort(
        key=lambda c: c.last_message_at.timestamp() if c.last_message_at else 0,
        reverse=True,
    )
    return result


@router.get("/admin", response_model=RidePageOut)
def admin_list_rides(
    status: str | None = Query(default=None, pattern="^(open|closed|hidden)$"),
    q: str | None = None,
    kind: str | None = Query(default=None, pattern="^(drive|need)$"),
    settlement_id: int | None = None,
    limit: int = Query(default=25, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    stmt = select(Ride).options(
        selectinload(Ride.author),
        selectinload(Ride.from_place),
        selectinload(Ride.to_place),
    )
    if status:
        stmt = stmt.where(Ride.status == status)
    if kind:
        stmt = stmt.where(Ride.kind == kind)
    if settlement_id:
        stmt = stmt.where(or_(Ride.from_settlement_id == settlement_id, Ride.to_settlement_id == settlement_id))
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.join(Ride.author).where(
            or_(
                Ride.note.ilike(like),
                User.full_name.ilike(like),
                User.phone.ilike(like),
                Ride.contact_phone.ilike(like),
            )
        )
    stmt = stmt.order_by(Ride.created_at.desc())
    total = int(db.execute(select(func.count()).select_from(stmt.subquery())).scalar_one())
    rows = db.execute(stmt.offset(offset).limit(limit)).scalars().unique().all()
    return RidePageOut(items=[to_out(r, viewer=user, reveal_phone=True) for r in rows], total=total, limit=limit, offset=offset)


@router.get("", response_model=RidePageOut)
def list_rides(
    settlement_id: int | None = None,
    from_id: int | None = None,
    to_id: int | None = None,
    kind: str | None = Query(default=None, pattern="^(drive|need)$"),
    mine: bool = False,
    q: str | None = None,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    expire_old_rides(db)
    stmt = select(Ride).options(
        selectinload(Ride.author),
        selectinload(Ride.from_place),
        selectinload(Ride.to_place),
    )
    if mine:
        if not user:
            raise HTTPException(status_code=401, detail="Войдите, чтобы видеть свои попутки")
        stmt = stmt.where(Ride.author_id == user.id, Ride.status != STATUS_HIDDEN)
    else:
        stmt = stmt.where(Ride.status == STATUS_OPEN, Ride.depart_at >= utcnow() - timedelta(hours=2))
        if kind:
            stmt = stmt.where(Ride.kind == kind)
        if from_id:
            stmt = stmt.where(Ride.from_settlement_id == from_id)
        if to_id:
            stmt = stmt.where(Ride.to_settlement_id == to_id)
        if settlement_id and not from_id and not to_id:
            stmt = stmt.where(
                or_(Ride.from_settlement_id == settlement_id, Ride.to_settlement_id == settlement_id)
            )
        if q and q.strip():
            like = f"%{q.strip()}%"
            stmt = stmt.where(or_(Ride.note.ilike(like), Ride.kind.ilike(like)))
    stmt = stmt.order_by(Ride.depart_at.asc() if not mine else Ride.depart_at.desc())

    count_stmt = select(func.count()).select_from(Ride)
    if mine:
        count_stmt = count_stmt.where(Ride.author_id == user.id, Ride.status != STATUS_HIDDEN)
    else:
        count_stmt = count_stmt.where(Ride.status == STATUS_OPEN, Ride.depart_at >= utcnow() - timedelta(hours=2))
        if kind:
            count_stmt = count_stmt.where(Ride.kind == kind)
        if from_id:
            count_stmt = count_stmt.where(Ride.from_settlement_id == from_id)
        if to_id:
            count_stmt = count_stmt.where(Ride.to_settlement_id == to_id)
        if settlement_id and not from_id and not to_id:
            count_stmt = count_stmt.where(
                or_(Ride.from_settlement_id == settlement_id, Ride.to_settlement_id == settlement_id)
            )
        if q and q.strip():
            like = f"%{q.strip()}%"
            count_stmt = count_stmt.where(or_(Ride.note.ilike(like), Ride.kind.ilike(like)))
    total = int(db.execute(count_stmt).scalar_one())
    rows = db.execute(stmt.offset(offset).limit(limit)).scalars().unique().all()
    return RidePageOut(items=[to_out(r, viewer=user) for r in rows], total=total, limit=limit, offset=offset)


@router.post("", response_model=RideOut)
def create_ride(
    payload: RideCreate,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    ip = (request.client.host if request.client else "unknown") or "unknown"
    if not limiter.allow(f"ride-create:{user.id}:{ip}", limit=12, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много попуток за час. Попробуйте позже")
    if payload.from_settlement_id == payload.to_settlement_id:
        raise HTTPException(status_code=400, detail="Откуда и куда — разные сёла")
    require_settlement(db, payload.from_settlement_id)
    require_settlement(db, payload.to_settlement_id)
    if count_open_rides(db, user.id) >= MAX_OPEN_RIDES:
        raise HTTPException(
            status_code=400,
            detail=f"Сразу можно держать {MAX_OPEN_RIDES} попутки. Снимите старую или дождитесь поездки.",
        )
    note = (payload.note or "").strip() or None
    phone = (payload.contact_phone or "").strip() or None
    hits = match_blacklist(db, title=note or "", description=note or "", phone=phone or user.phone)
    if hits:
        raise HTTPException(status_code=400, detail="Текст не прошёл проверку. Уберите ссылки и лишние контакты")
    item = Ride(
        author_id=user.id,
        kind=payload.kind,
        from_settlement_id=payload.from_settlement_id,
        to_settlement_id=payload.to_settlement_id,
        depart_at=parse_depart(payload.depart_at),
        seats=payload.seats,
        note=note,
        contact_phone=phone,
        status=STATUS_OPEN,
    )
    db.add(item)
    db.flush()
    db.commit()
    item = load_ride(db, item.id)
    assert item is not None
    notify_ride_created(db, item)
    db.commit()
    return to_out(item, viewer=user, reveal_phone=True)


@router.get("/{ride_id}", response_model=RideOut)
def get_ride(
    ride_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    expire_old_rides(db)
    item = load_ride(db, ride_id)
    if not item:
        raise HTTPException(status_code=404, detail="Попутка не найдена")
    is_staff = bool(user and user.role in (UserRole.admin, UserRole.moderator))
    is_author = bool(user and user.id == item.author_id)
    if item.status == STATUS_HIDDEN and not is_staff and not is_author:
        raise HTTPException(status_code=404, detail="Попутка не найдена")
    reveal = author_replied(db, item, user)
    return to_out(item, viewer=user, reveal_phone=reveal)


@router.patch("/{ride_id}", response_model=RideOut)
def update_ride(
    ride_id: int,
    payload: RideUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_ride(db, ride_id)
    if not item:
        raise HTTPException(status_code=404, detail="Попутка не найдена")
    is_staff = user.role in (UserRole.admin, UserRole.moderator)
    if item.author_id != user.id and not is_staff:
        raise HTTPException(status_code=403, detail="Нет доступа")
    if item.status != STATUS_OPEN and not is_staff:
        raise HTTPException(status_code=400, detail="Эту попутку уже нельзя менять")
    data = payload.model_dump(exclude_unset=True)
    if "depart_at" in data and data["depart_at"] is not None:
        item.depart_at = parse_depart(data["depart_at"])
    if "seats" in data and data["seats"] is not None:
        item.seats = data["seats"]
    if "note" in data:
        note = (data["note"] or "").strip() or None
        hits = match_blacklist(db, title=note or "", description=note or "")
        if hits:
            raise HTTPException(status_code=400, detail="Текст не прошёл проверку")
        item.note = note
    if "contact_phone" in data:
        item.contact_phone = (data["contact_phone"] or "").strip() or None
    db.commit()
    item = load_ride(db, ride_id)
    assert item is not None
    return to_out(item, viewer=user, reveal_phone=True)


@router.post("/{ride_id}/close", response_model=RideOut)
def close_ride(
    ride_id: int,
    payload: RideCloseIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_ride(db, ride_id)
    if not item:
        raise HTTPException(status_code=404, detail="Попутка не найдена")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    item.status = STATUS_CLOSED
    item.close_reason = payload.reason
    db.commit()
    item = load_ride(db, ride_id)
    assert item is not None
    return to_out(item, viewer=user, reveal_phone=True)


@router.post("/{ride_id}/hide", response_model=RideOut)
def hide_ride(
    ride_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    item = load_ride(db, ride_id)
    if not item:
        raise HTTPException(status_code=404, detail="Попутка не найдена")
    item.status = STATUS_HIDDEN
    log_action(db, actor=user, action="ride.hide", entity_type="ride", entity_id=item.id, details=ride_title(item))
    db.commit()
    item = load_ride(db, ride_id)
    assert item is not None
    return to_out(item, viewer=user, reveal_phone=True)


@router.delete("/{ride_id}")
def delete_ride(
    ride_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    item = load_ride(db, ride_id)
    if not item:
        raise HTTPException(status_code=404, detail="Попутка не найдена")
    title = ride_title(item)
    db.execute(delete(RideMessage).where(RideMessage.ride_id == ride_id))
    db.execute(delete(RideReport).where(RideReport.ride_id == ride_id))
    db.delete(item)
    log_action(db, actor=user, action="ride.delete", entity_type="ride", entity_id=ride_id, details=title)
    db.commit()
    return {"ok": True}


@router.post("/{ride_id}/report")
def report_ride(
    ride_id: int,
    payload: RideReportIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_ride(db, ride_id)
    if not item or item.status == STATUS_HIDDEN:
        raise HTTPException(status_code=404, detail="Попутка не найдена")
    if item.author_id == user.id:
        raise HTTPException(status_code=400, detail="На свою попутку пожаловаться нельзя")
    existing = db.execute(
        select(RideReport.id).where(RideReport.ride_id == ride_id, RideReport.reporter_id == user.id)
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail="Вы уже жаловались на эту попутку")
    db.add(
        RideReport(
            ride_id=ride_id,
            reporter_id=user.id,
            reason=payload.reason,
            note=(payload.note or "").strip() or None,
        )
    )
    db.flush()
    open_n = int(
        db.execute(
            select(func.count()).select_from(RideReport).where(
                RideReport.ride_id == ride_id, RideReport.status == "open"
            )
        ).scalar_one()
    )
    if open_n >= REPORTS_TO_HIDE:
        item.status = STATUS_HIDDEN
    db.commit()
    return {"ok": True, "message": "Жалоба отправлена"}


@router.get("/{ride_id}/messages", response_model=list[RideMessageOut])
def list_messages(
    ride_id: int,
    peer_id: int | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_ride(db, ride_id)
    if not item:
        raise HTTPException(status_code=404, detail="Попутка не найдена")
    passenger_id = _resolve_passenger_id(item, user, peer_id)
    if user.id != item.author_id and passenger_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    if user.id == item.author_id and passenger_id == item.author_id:
        raise HTTPException(status_code=400, detail="Некорректный собеседник")
    msgs = db.execute(
        select(RideMessage)
        .where(RideMessage.ride_id == ride_id, RideMessage.passenger_id == passenger_id)
        .order_by(RideMessage.created_at.asc())
    ).scalars().all()
    marked = False
    for m in msgs:
        if m.sender_id != user.id and not m.is_read:
            m.is_read = True
            marked = True
    if marked:
        db.commit()
        other_id = item.author_id if user.id == passenger_id else passenger_id
        emit_ride_read(ride_id, passenger_id, user.id, other_id)
    names: dict[int, str | None] = {}
    for m in msgs:
        if m.sender_id not in names:
            u = db.get(User, m.sender_id)
            names[m.sender_id] = u.full_name if u else None
    peer_for_client = passenger_id if user.id == item.author_id else item.author_id
    return [
        to_message_out(m, user_id=user.id, sender_name=names.get(m.sender_id), peer_id=peer_for_client)
        for m in msgs
    ]


@router.post("/{ride_id}/messages", response_model=RideMessageOut)
def post_message(
    ride_id: int,
    payload: RideMessageIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_ride(db, ride_id)
    if not item or item.status == STATUS_HIDDEN:
        raise HTTPException(status_code=404, detail="Попутка не найдена")
    if item.status != STATUS_OPEN and user.id != item.author_id:
        raise HTTPException(status_code=400, detail="Эта попутка уже неактуальна")
    body = payload.body.strip()
    if not body:
        raise HTTPException(status_code=400, detail="Пустое сообщение")
    hits = match_blacklist(db, title="", description=body)
    if hits:
        raise HTTPException(status_code=400, detail="Сообщение отклонено: запрещённые слова или контакты")
    if looks_like_chat_spam(body):
        raise HTTPException(
            status_code=400,
            detail="Сообщение похоже на спам. Уберите ссылки — напишите по поездке",
        )
    if not limiter.allow(f"chat-day:{user.id}", limit=50, window_sec=86400):
        raise HTTPException(
            status_code=429,
            detail="Лимит сообщений на сегодня (50). Напишите завтра.",
        )
    if user.id == item.author_id:
        passenger_id = _resolve_passenger_id(item, user, payload.peer_id)
        exists_peer = db.get(User, passenger_id)
        if not exists_peer:
            raise HTTPException(status_code=404, detail="Собеседник не найден")
    else:
        passenger_id = user.id
    msg = RideMessage(
        ride_id=ride_id,
        sender_id=user.id,
        passenger_id=passenger_id,
        body=body,
    )
    db.add(msg)
    db.flush()
    target = item.author_id if user.id == passenger_id else passenger_id
    if target and target != user.id:
        push_user(
            db,
            user_id=target,
            title=user.full_name or "Сообщение",
            body=body[:120],
            data={
                "type": "ride_message",
                "ride_id": str(item.id),
                "passenger_id": str(passenger_id),
                "message_id": str(msg.id),
            },
        )
    db.commit()
    db.refresh(msg)
    emit_ride_chat(db, msg, item, (user.id, target) if target else (user.id,))
    peer_for_client = passenger_id if user.id == item.author_id else item.author_id
    sender_name = user.full_name
    return to_message_out(msg, user_id=user.id, sender_name=sender_name, peer_id=peer_for_client)
