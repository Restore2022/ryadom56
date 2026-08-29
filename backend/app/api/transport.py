from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import json
import re

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user, get_optional_user, require_roles
from app.core.database import get_db
from app.models import (
    TransportFavorite,
    TransportRoute,
    TransportRouteStop,
    TransportStop,
    User,
    UserRole,
)
from app.schemas import (
    TransportCreate,
    TransportOut,
    TransportPageOut,
    TransportStopCreate,
    TransportStopOut,
    TransportStopPointOut,
    TransportStopUpdate,
    TransportTripIn,
    TransportTripOut,
    TransportUpdate,
)
from app.services.audit import log_action
from app.services.notify import notify_user

router = APIRouter(prefix="/transport", tags=["transport"])
LOCAL_TZ = ZoneInfo("Asia/Yekaterinburg")


def _now_local(now: datetime | None = None) -> datetime:
    if now is None:
        return datetime.now(LOCAL_TZ)
    if now.tzinfo is None:
        return now.replace(tzinfo=LOCAL_TZ)
    return now.astimezone(LOCAL_TZ)

_TIME_RE = re.compile(r"\b([01]?\d|2[0-3])[:.]([0-5]\d)\b")
_TIME_ONE = re.compile(r"^([01]?\d|2[0-3])[:.]([0-5]\d)$")

_ROUTE_LOAD = (
    selectinload(TransportRoute.settlement),
    selectinload(TransportRoute.stop_links).selectinload(TransportRouteStop.stop),
)


def _stops_from_text(text: str | None) -> list[str]:
    if not text:
        return []
    return [line.strip() for line in text.replace(";", "\n").splitlines() if line.strip()]


def favorite_ids_for(db: Session, user: User | None) -> set[int]:
    if not user:
        return set()
    rows = db.execute(select(TransportFavorite.route_id).where(TransportFavorite.user_id == user.id)).scalars().all()
    return set(rows)


def normalize_time(raw: str) -> str:
    value = (raw or "").strip().replace(".", ":")
    match = _TIME_ONE.fullmatch(value)
    if not match:
        raise HTTPException(status_code=400, detail=f"Неверное время: {raw}")
    return f"{int(match.group(1)):02d}:{match.group(2)}"


DAY_ORDER = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
DAY_SET = set(DAY_ORDER)
WEEKDAYS = ["mon", "tue", "wed", "thu", "fri"]
WEEKENDS = ["sat", "sun"]
DAY_SHORT = {
    "mon": "Пн",
    "tue": "Вт",
    "wed": "Ср",
    "thu": "Чт",
    "fri": "Пт",
    "sat": "Сб",
    "sun": "Вс",
}
DAY_ALIASES = {
    "пн": "mon",
    "вт": "tue",
    "ср": "wed",
    "чт": "thu",
    "пт": "fri",
    "сб": "sat",
    "вс": "sun",
    "0": "mon",
    "1": "tue",
    "2": "wed",
    "3": "thu",
    "4": "fri",
    "5": "sat",
    "6": "sun",
}


def parse_times_from_text(text: str | None) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for match in _TIME_RE.finditer(text or ""):
        stamp = f"{int(match.group(1)):02d}:{match.group(2)}"
        if stamp in seen:
            continue
        seen.add(stamp)
        found.append(stamp)
    return found


def normalize_days(days: list[str] | None) -> list[str]:
    out: list[str] = []
    for raw in days or DAY_ORDER:
        key = DAY_ALIASES.get(str(raw).strip().lower(), str(raw).strip().lower())
        if key not in DAY_SET:
            raise HTTPException(status_code=400, detail=f"Неверный день: {raw}")
        if key not in out:
            out.append(key)
    out.sort(key=DAY_ORDER.index)
    if not out:
        raise HTTPException(status_code=400, detail="Выберите дни следования")
    return out


def days_label(days: list[str]) -> str:
    keys = normalize_days(days)
    if keys == DAY_ORDER:
        return "все дни"
    if keys == WEEKDAYS:
        return "будни"
    if keys == WEEKENDS:
        return "выходные"
    return ", ".join(DAY_SHORT[d] for d in keys)


def trip_stamp(depart: str, arrive: str | None) -> str:
    return f"{depart} → {arrive}" if arrive else depart


def trip_line(trip: dict) -> str:
    return f"{days_label(trip['days'])} {trip_stamp(trip['depart'], trip.get('arrive'))}"


def _hm(stamp: str) -> tuple[int, int] | None:
    match = _TIME_ONE.fullmatch((stamp or "").replace(".", ":"))
    if not match:
        return None
    return int(match.group(1)), int(match.group(2))


def _load_times_json(item: TransportRoute) -> list:
    if not item.times_json:
        return []
    try:
        data = json.loads(item.times_json)
    except json.JSONDecodeError:
        return []
    return data if isinstance(data, list) else []


def parse_trips(item: TransportRoute) -> list[dict]:
    data = _load_times_json(item)
    trips: list[dict] = []
    for row in data:
        if isinstance(row, str):
            found = parse_times_from_text(row)
            if not found:
                continue
            trips.append(
                {
                    "depart": found[0],
                    "arrive": found[1] if len(found) > 1 else None,
                    "days": list(DAY_ORDER),
                }
            )
            continue
        if not isinstance(row, dict):
            continue
        depart = normalize_time(str(row.get("depart") or row.get("time") or ""))
        arrive_raw = row.get("arrive")
        arrive = normalize_time(str(arrive_raw)) if arrive_raw else None
        days = normalize_days(row.get("days") or DAY_ORDER)
        trips.append({"depart": depart, "arrive": arrive, "days": days})
    if trips:
        trips.sort(key=lambda t: t["depart"])
        return trips
    stamps = parse_times_from_text(item.schedule_text)
    return [{"depart": stamp, "arrive": None, "days": list(DAY_ORDER)} for stamp in stamps]


def route_times(item: TransportRoute) -> list[str]:
    return [trip_stamp(t["depart"], t.get("arrive")) for t in parse_trips(item)]


def trips_out(item: TransportRoute) -> list[TransportTripOut]:
    return [
        TransportTripOut(
            depart=t["depart"],
            arrive=t.get("arrive"),
            days=t["days"],
            days_label=days_label(t["days"]),
        )
        for t in parse_trips(item)
    ]


def summarize_days_mode(trips: list[dict]) -> str:
    if not trips:
        return "all"
    sets = [set(t["days"]) for t in trips]
    if all(s == set(DAY_ORDER) for s in sets):
        return "all"
    if all(s <= set(WEEKDAYS) and s for s in sets):
        return "weekdays"
    if all(s <= set(WEEKENDS) and s for s in sets):
        return "weekends"
    return "all"


def apply_trips(item: TransportRoute, trips_in: list[TransportTripIn] | list[dict]) -> None:
    trips: list[dict] = []
    seen: set[tuple] = set()
    for raw in trips_in:
        row = raw.model_dump() if isinstance(raw, TransportTripIn) else dict(raw)
        depart = normalize_time(str(row.get("depart") or ""))
        arrive_raw = row.get("arrive")
        arrive = normalize_time(str(arrive_raw)) if arrive_raw else None
        days = normalize_days(row.get("days") or DAY_ORDER)
        key = (depart, arrive, tuple(days))
        if key in seen:
            continue
        seen.add(key)
        trips.append({"depart": depart, "arrive": arrive, "days": days})
    if not trips:
        raise HTTPException(status_code=400, detail="Добавьте хотя бы один рейс")
    trips.sort(key=lambda t: t["depart"])
    item.times_json = json.dumps(trips, ensure_ascii=False)
    item.schedule_text = "\n".join(trip_line(t) for t in trips)
    item.schedule_weekdays = None
    item.schedule_weekends = None
    item.days_mode = summarize_days_mode(trips)


def apply_times(item: TransportRoute, times: list[str]) -> None:
    apply_trips(item, [{"depart": stamp, "arrive": None, "days": list(DAY_ORDER)} for stamp in times])


def route_stop_points(item: TransportRoute) -> list[TransportStopPointOut]:
    points: list[TransportStopPointOut] = []
    for link in item.stop_links or []:
        if link.stop:
            points.append(TransportStopPointOut(id=link.stop.id, name=link.stop.name))
    return points


def route_stop_names(item: TransportRoute) -> list[str]:
    names = [p.name for p in route_stop_points(item)]
    if names:
        return names
    return _stops_from_text(item.stops_text)


def next_departure(item: TransportRoute, now: datetime | None = None) -> str | None:
    """Ближайший рейс с учётом дней следования (сегодня или позже на неделе)."""
    now = _now_local(now)
    trips = parse_trips(item)
    if not trips:
        return None
    today = now.weekday()
    for offset in range(8):
        weekday = (today + offset) % 7
        day_key = DAY_ORDER[weekday]
        stamps: list[tuple[int, int, str | None]] = []
        for trip in trips:
            if day_key not in trip["days"]:
                continue
            hm = _hm(trip["depart"])
            if not hm:
                continue
            stamps.append((hm[0], hm[1], trip.get("arrive")))
        stamps.sort()
        for hour, minute, arrive in stamps:
            cand = now.replace(hour=hour, minute=minute, second=0, microsecond=0) + timedelta(days=offset)
            if cand >= now - timedelta(minutes=1):
                label = trip_stamp(f"{hour:02d}:{minute:02d}", arrive)
                if offset == 0:
                    return label
                if offset == 1:
                    return f"завтра {label}"
                return f"{DAY_SHORT[day_key]} {label}"
    return None


def to_out(item: TransportRoute, favorited_ids: set[int] | None = None) -> TransportOut:
    names = route_stop_names(item)
    trips = parse_trips(item)
    times = [trip_stamp(t["depart"], t.get("arrive")) for t in trips]
    return TransportOut(
        id=item.id,
        title=item.title,
        route_number=item.route_number,
        description=item.description,
        schedule_text=item.schedule_text or "\n".join(trip_line(t) for t in trips),
        schedule_weekdays=item.schedule_weekdays,
        schedule_weekends=item.schedule_weekends,
        stops_text=item.stops_text or ("\n".join(names) if names else None),
        stops=names,
        stop_points=route_stop_points(item),
        times=times,
        trips=trips_out(item),
        days_mode=item.days_mode or "all",
        notes=item.notes,
        fare_text=item.fare_text,
        phone=item.phone,
        next_departure=next_departure(item),
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        is_published=item.is_published,
        is_favorited=bool(favorited_ids and item.id in favorited_ids),
        view_count=item.view_count or 0,
        favorite_count=item.favorite_count or 0,
        outdated_reports=item.outdated_reports or 0,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _can_see_unpublished(user: User | None) -> bool:
    return bool(user and user.role in (UserRole.admin, UserRole.editor))


def _is_weekend(d: datetime | None = None) -> bool:
    day = _now_local(d).weekday()
    return day >= 5


def _load_route(db: Session, route_id: int) -> TransportRoute | None:
    return db.execute(
        select(TransportRoute).options(*_ROUTE_LOAD).where(TransportRoute.id == route_id)
    ).scalar_one_or_none()


def _get_stop(db: Session, stop_id: int) -> TransportStop:
    stop = db.get(TransportStop, stop_id)
    if not stop:
        raise HTTPException(status_code=400, detail="Остановка не найдена")
    return stop


def apply_stops(db: Session, item: TransportRoute, stop_ids: list[int]) -> None:
    if len(stop_ids) < 2:
        raise HTTPException(status_code=400, detail="Нужны минимум две остановки: откуда и куда")
    stops = [_get_stop(db, sid) for sid in stop_ids]
    item.stop_links.clear()
    db.flush()
    for index, stop in enumerate(stops):
        item.stop_links.append(TransportRouteStop(stop_id=stop.id, sort_order=index))
    item.stops_text = "\n".join(s.name for s in stops)
    item.title = f"{stops[0].name} → {stops[-1].name}"
    item.route_number = None


def find_stop_by_name(db: Session, name: str) -> TransportStop | None:
    key = name.strip().lower()
    if not key:
        return None
    return db.execute(select(TransportStop).where(func.lower(TransportStop.name) == key)).scalar_one_or_none()


@router.get("/stops", response_model=list[TransportStopOut])
def list_stops(
    q: str | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    stmt = select(TransportStop).order_by(TransportStop.name)
    if q and q.strip():
        stmt = stmt.where(TransportStop.name.ilike(f"%{q.strip()}%"))
    return db.execute(stmt).scalars().all()


@router.post("/stops", response_model=TransportStopOut)
def create_stop(
    payload: TransportStopCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    name = payload.name.strip()
    existing = find_stop_by_name(db, name)
    if existing:
        return existing
    item = TransportStop(name=name, settlement_id=payload.settlement_id)
    db.add(item)
    db.flush()
    log_action(db, actor=user, action="transport.stop_create", entity_type="transport_stop", entity_id=item.id, details=item.name)
    db.commit()
    db.refresh(item)
    return item


@router.patch("/stops/{stop_id}", response_model=TransportStopOut)
def update_stop(
    stop_id: int,
    payload: TransportStopUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.get(TransportStop, stop_id)
    if not item:
        raise HTTPException(status_code=404, detail="Остановка не найдена")
    data = payload.model_dump(exclude_unset=True)
    if "name" in data and data["name"]:
        name = data["name"].strip()
        other = find_stop_by_name(db, name)
        if other and other.id != item.id:
            raise HTTPException(status_code=400, detail="Такая остановка уже есть")
        item.name = name
    if "settlement_id" in data:
        item.settlement_id = data["settlement_id"]
    log_action(db, actor=user, action="transport.stop_update", entity_type="transport_stop", entity_id=item.id, details=item.name)
    db.commit()
    db.refresh(item)
    return item


@router.delete("/stops/{stop_id}")
def delete_stop(
    stop_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.get(TransportStop, stop_id)
    if not item:
        raise HTTPException(status_code=404, detail="Остановка не найдена")
    used = int(
        db.execute(select(func.count()).select_from(TransportRouteStop).where(TransportRouteStop.stop_id == stop_id)).scalar_one()
    )
    if used:
        raise HTTPException(status_code=409, detail="Остановка используется в маршрутах")
    log_action(db, actor=user, action="transport.stop_delete", entity_type="transport_stop", entity_id=item.id, details=item.name)
    db.delete(item)
    db.commit()
    return {"ok": True}


@router.get("/favorites", response_model=list[TransportOut])
def list_transport_favorites(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    fav_ids = favorite_ids_for(db, user)
    if not fav_ids:
        return []
    stmt = (
        select(TransportRoute)
        .options(*_ROUTE_LOAD)
        .where(TransportRoute.id.in_(fav_ids), TransportRoute.is_published.is_(True))
        .order_by(TransportRoute.title)
    )
    return [to_out(r, fav_ids) for r in db.execute(stmt).scalars().all()]


@router.get("", response_model=TransportPageOut)
def list_routes(
    settlement_id: int | None = None,
    q: str | None = None,
    day: str | None = Query(default=None, description="today|weekdays|weekends|all"),
    published: bool | None = Query(default=None),
    favorites_only: bool = False,
    limit: int = Query(default=30, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    stmt = select(TransportRoute).options(*_ROUTE_LOAD)
    staff = _can_see_unpublished(user)
    if not staff:
        stmt = stmt.where(TransportRoute.is_published.is_(True))
    elif published is True:
        stmt = stmt.where(TransportRoute.is_published.is_(True))
    elif published is False:
        stmt = stmt.where(TransportRoute.is_published.is_(False))
    if settlement_id is not None:
        stmt = stmt.where(TransportRoute.settlement_id == settlement_id)
    if q and q.strip():
        like = f"%{q.strip()}%"
        stop_ids = select(TransportStop.id).where(TransportStop.name.ilike(like))
        via_stops = select(TransportRouteStop.route_id).where(TransportRouteStop.stop_id.in_(stop_ids))
        stmt = stmt.where(
            or_(
                TransportRoute.title.ilike(like),
                TransportRoute.description.ilike(like),
                TransportRoute.schedule_text.ilike(like),
                TransportRoute.stops_text.ilike(like),
                TransportRoute.notes.ilike(like),
                TransportRoute.id.in_(via_stops),
            )
        )
    mode = (day or "all").lower()
    if mode == "today":
        mode = "weekends" if _is_weekend() else "weekdays"
    if mode == "weekdays":
        stmt = stmt.where(or_(TransportRoute.days_mode == "all", TransportRoute.days_mode == "weekdays"))
    elif mode == "weekends":
        stmt = stmt.where(or_(TransportRoute.days_mode == "all", TransportRoute.days_mode == "weekends"))

    fav_ids = favorite_ids_for(db, user)
    if favorites_only:
        if not user:
            raise HTTPException(status_code=401, detail="Войдите, чтобы видеть избранные маршруты")
        if not fav_ids:
            return TransportPageOut(items=[], total=0, limit=limit, offset=offset)
        stmt = stmt.where(TransportRoute.id.in_(fav_ids))

    count_stmt = select(func.count()).select_from(stmt.subquery())
    total = int(db.execute(count_stmt).scalar_one())
    stmt = stmt.order_by(TransportRoute.title).offset(offset).limit(limit)
    items = [to_out(r, fav_ids) for r in db.execute(stmt).scalars().all()]
    return TransportPageOut(items=items, total=total, limit=limit, offset=offset)


@router.get("/{route_id}", response_model=TransportOut)
def get_route(
    route_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    item = _load_route(db, route_id)
    if not item:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    if not item.is_published and not _can_see_unpublished(user):
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{route_id}/view", response_model=TransportOut)
def track_route_view(
    route_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    item = _load_route(db, route_id)
    if not item:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    if not item.is_published and not _can_see_unpublished(user):
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    item.view_count = (item.view_count or 0) + 1
    db.commit()
    item = _load_route(db, route_id)
    assert item is not None
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{route_id}/outdated")
def report_outdated(
    route_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = db.execute(select(TransportRoute).where(TransportRoute.id == route_id)).scalar_one_or_none()
    if not item or not item.is_published:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    item.outdated_reports = (item.outdated_reports or 0) + 1
    db.commit()
    for staff in db.execute(
        select(User).where(User.role.in_([UserRole.admin, UserRole.editor]), User.is_active.is_(True))
    ).scalars().all():
        notify_user(
            db,
            user_id=staff.id,
            type="transport_outdated",
            title="Расписание устарело?",
            body=f"{item.title}: сообщение от пользователя",
            listing_id=None,
        )
    db.commit()
    return {"ok": True, "outdated_reports": item.outdated_reports}


@router.post("/{route_id}/favorite", response_model=TransportOut)
def add_favorite(
    route_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = _load_route(db, route_id)
    if not item or not item.is_published:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    exists = db.execute(
        select(TransportFavorite).where(
            TransportFavorite.user_id == user.id,
            TransportFavorite.route_id == route_id,
        )
    ).scalar_one_or_none()
    if not exists:
        db.add(TransportFavorite(user_id=user.id, route_id=route_id))
        item.favorite_count = (item.favorite_count or 0) + 1
        db.commit()
        item = _load_route(db, route_id)
        assert item is not None
    return to_out(item, favorite_ids_for(db, user))


@router.delete("/{route_id}/favorite", response_model=TransportOut)
def remove_favorite(
    route_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = _load_route(db, route_id)
    if not item:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    row = db.execute(
        select(TransportFavorite).where(
            TransportFavorite.user_id == user.id,
            TransportFavorite.route_id == route_id,
        )
    ).scalar_one_or_none()
    if row:
        db.delete(row)
        item.favorite_count = max(0, (item.favorite_count or 0) - 1)
        db.commit()
        item = _load_route(db, route_id)
        assert item is not None
    return to_out(item, favorite_ids_for(db, user))


@router.post("", response_model=TransportOut)
def create_route(
    payload: TransportCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = TransportRoute(
        title="маршрут",
        schedule_text="00:00",
        route_number=None,
        days_mode="all",
        description=payload.description,
        notes=payload.notes,
        fare_text=payload.fare_text,
        phone=payload.phone,
        settlement_id=payload.settlement_id,
        is_published=payload.is_published,
    )
    db.add(item)
    db.flush()
    apply_stops(db, item, payload.stop_ids)
    if payload.trips:
        apply_trips(item, payload.trips)
    elif payload.times:
        apply_times(item, payload.times)
    else:
        raise HTTPException(status_code=400, detail="Добавьте хотя бы один рейс")
    log_action(db, actor=user, action="transport.create", entity_type="transport", entity_id=item.id, details=item.title)
    db.commit()
    item = _load_route(db, item.id)
    assert item is not None
    return to_out(item)


@router.patch("/{route_id}", response_model=TransportOut)
def update_route(
    route_id: int,
    payload: TransportUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = _load_route(db, route_id)
    if not item:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    data = payload.model_dump(exclude_unset=True)
    stop_ids = data.pop("stop_ids", None)
    trips = data.pop("trips", None)
    times = data.pop("times", None)
    for key, value in data.items():
        setattr(item, key, value)
    if stop_ids is not None:
        apply_stops(db, item, stop_ids)
    if trips is not None:
        apply_trips(item, [TransportTripIn.model_validate(row) for row in trips])
    elif times is not None:
        apply_times(item, times)
    log_action(db, actor=user, action="transport.update", entity_type="transport", entity_id=item.id, details=item.title)
    db.commit()
    item = _load_route(db, route_id)
    assert item is not None
    return to_out(item)


@router.delete("/{route_id}")
def delete_route(
    route_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(select(TransportRoute).where(TransportRoute.id == route_id)).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    log_action(db, actor=user, action="transport.delete", entity_type="transport", entity_id=item.id, details=item.title)
    for link in db.execute(select(TransportRouteStop).where(TransportRouteStop.route_id == route_id)).scalars().all():
        db.delete(link)
    for fav in db.execute(select(TransportFavorite).where(TransportFavorite.route_id == route_id)).scalars().all():
        db.delete(fav)
    db.delete(item)
    db.commit()
    return {"ok": True}
