from datetime import datetime
from zoneinfo import ZoneInfo
import re
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user, get_optional_user, require_roles
from app.core.database import get_db
from app.core.geo import haversine_km, resolve_origin
from app.models import (
    DirectoryCategory,
    DirectoryFavorite,
    DirectoryItem,
    DirectoryReport,
    Settlement,
    User,
    UserRole,
)
from app.schemas import DirectoryCreate, DirectoryOut, DirectoryPageOut, DirectoryReportIn, DirectoryUpdate
from app.services.notify import notify_user
from app.services.rate_limit import limiter
from app.services.urls import safe_http_url

LOCAL_TZ = ZoneInfo("Asia/Yekaterinburg")

router = APIRouter(prefix="/directory", tags=["directory"])

_RANGE_RE = re.compile(
    r"(?P<h1>\d{1,2})(?::(?P<m1>\d{2}))?\s*[-–—]\s*(?P<h2>\d{1,2})(?::(?P<m2>\d{2}))?"
)


def favorite_ids_for(db: Session, user: User | None) -> set[int]:
    if not user:
        return set()
    rows = db.execute(select(DirectoryFavorite.directory_id).where(DirectoryFavorite.user_id == user.id)).scalars().all()
    return set(rows)


def is_open_now(hours: str | None, now: datetime | None = None) -> bool | None:
    if not hours or not hours.strip():
        return None
    text = hours.lower().replace("ё", "е")
    if "круглосуточ" in text or "24/7" in text or "24 часа" in text:
        return True
    if "выходн" in text and "без выход" not in text:
        # не парсим сложные исключения — только явные диапазоны времени
        pass
    now = now or datetime.now(LOCAL_TZ)
    if now.tzinfo is not None:
        now = now.astimezone(LOCAL_TZ).replace(tzinfo=None)
    match = _RANGE_RE.search(text)
    if not match:
        return None
    try:
        h1 = int(match.group("h1"))
        m1 = int(match.group("m1") or 0)
        h2 = int(match.group("h2"))
        m2 = int(match.group("m2") or 0)
        if not (0 <= h1 <= 23 and 0 <= h2 <= 23 and 0 <= m1 <= 59 and 0 <= m2 <= 59):
            return None
        start = now.replace(hour=h1, minute=m1, second=0, microsecond=0)
        end = now.replace(hour=h2, minute=m2, second=0, microsecond=0)
    except ValueError:
        return None
    if end <= start:
        # через полночь
        return now >= start or now <= end
    return start <= now <= end


def maps_url(item: DirectoryItem) -> str | None:
    if item.lat is not None and item.lon is not None:
        return f"https://yandex.ru/maps/?pt={item.lon},{item.lat}&z=16&l=map"
    if item.address:
        q = quote(item.address)
        return f"https://yandex.ru/maps/?text={q}"
    return None


def to_out(item: DirectoryItem, favorited_ids: set[int] | None = None, distance_km: float | None = None) -> DirectoryOut:
    return DirectoryOut(
        id=item.id,
        title=item.title,
        category=item.category,
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        description=item.description,
        address=item.address,
        phone=item.phone,
        website=safe_http_url(item.website),
        hours=item.hours,
        is_open_now=is_open_now(item.hours),
        maps_url=maps_url(item),
        lat=item.lat,
        lon=item.lon,
        is_published=item.is_published,
        is_favorited=bool(favorited_ids and item.id in favorited_ids),
        view_count=item.view_count or 0,
        created_at=item.created_at,
        updated_at=item.updated_at,
        distance_km=distance_km,
    )


@router.get("/favorites", response_model=list[DirectoryOut])
def list_directory_favorites(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    fav_ids = favorite_ids_for(db, user)
    if not fav_ids:
        return []
    stmt = (
        select(DirectoryItem)
        .options(selectinload(DirectoryItem.settlement))
        .where(DirectoryItem.id.in_(fav_ids), DirectoryItem.is_published.is_(True))
        .order_by(DirectoryItem.title)
    )
    return [to_out(r, fav_ids) for r in db.execute(stmt).scalars().all()]


@router.get("", response_model=DirectoryPageOut)
def list_directory(
    category: DirectoryCategory | None = None,
    settlement_id: int | None = None,
    q: str | None = None,
    published: bool | None = Query(default=None),
    sort: str = Query(default="title", pattern="^(title|near)$"),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lon: float | None = Query(default=None, ge=-180, le=180),
    limit: int = Query(default=30, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    filters = []
    is_staff = user and user.role in (UserRole.admin, UserRole.editor)
    if not is_staff:
        filters.append(DirectoryItem.is_published.is_(True))
    elif published is True:
        filters.append(DirectoryItem.is_published.is_(True))
    elif published is False:
        filters.append(DirectoryItem.is_published.is_(False))
    if category:
        filters.append(DirectoryItem.category == category)
    origin = resolve_origin(db, lat, lon, settlement_id) if sort == "near" else None
    if sort == "near" and origin is None:
        raise HTTPException(status_code=400, detail="Для «рядом» нужны геолокация или выбранное село")
    if settlement_id and sort != "near":
        filters.append(DirectoryItem.settlement_id == settlement_id)
    if q:
        like = f"%{q.strip()}%"
        filters.append(
            DirectoryItem.title.ilike(like)
            | DirectoryItem.description.ilike(like)
            | DirectoryItem.address.ilike(like)
            | DirectoryItem.phone.ilike(like)
        )
    total = db.execute(select(func.count(DirectoryItem.id)).where(*filters)).scalar_one()
    stmt = (
        select(DirectoryItem)
        .options(selectinload(DirectoryItem.settlement))
        .where(*filters)
    )
    if sort == "near" and origin is not None:
        olat, olon = origin
        plat = func.coalesce(DirectoryItem.lat, Settlement.lat)
        plon = func.coalesce(DirectoryItem.lon, Settlement.lon)
        dist = (plat - olat) * (plat - olat) + (plon - olon) * (plon - olon)
        stmt = stmt.outerjoin(Settlement, Settlement.id == DirectoryItem.settlement_id).order_by(
            case((plat.is_(None), 1), else_=0).asc(),
            dist.asc(),
            DirectoryItem.title,
        )
    else:
        stmt = stmt.order_by(DirectoryItem.title)
    stmt = stmt.offset(offset).limit(limit)
    fav_ids = favorite_ids_for(db, user)
    items = []
    for r in db.execute(stmt).scalars().unique().all():
        dist_km = None
        if origin is not None:
            ilat = r.lat if r.lat is not None else (r.settlement.lat if r.settlement else None)
            ilon = r.lon if r.lon is not None else (r.settlement.lon if r.settlement else None)
            if ilat is not None and ilon is not None:
                dist_km = round(haversine_km(origin[0], origin[1], ilat, ilon), 1)
        items.append(to_out(r, fav_ids, distance_km=dist_km))
    return DirectoryPageOut(items=items, total=total, limit=limit, offset=offset)


@router.get("/{item_id}", response_model=DirectoryOut)
def get_directory_item(
    item_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    item = db.execute(
        select(DirectoryItem).options(selectinload(DirectoryItem.settlement)).where(DirectoryItem.id == item_id)
    ).scalar_one_or_none()
    if not item or not item.is_published:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{item_id}/view", response_model=DirectoryOut)
def track_directory_view(
    item_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    item = db.execute(
        select(DirectoryItem).options(selectinload(DirectoryItem.settlement)).where(DirectoryItem.id == item_id)
    ).scalar_one_or_none()
    if not item or (not item.is_published and not (user and user.role in (UserRole.admin, UserRole.editor))):
        raise HTTPException(status_code=404, detail="Запись не найдена")
    item.view_count = (item.view_count or 0) + 1
    db.commit()
    item = db.execute(
        select(DirectoryItem).options(selectinload(DirectoryItem.settlement)).where(DirectoryItem.id == item_id)
    ).scalar_one()
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{item_id}/report")
def report_directory_item(
    item_id: int,
    payload: DirectoryReportIn,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    ip = (request.client.host if request.client else "unknown") or "unknown"
    if not limiter.allow(f"dir-report:{user.id}:{ip}", limit=15, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много жалоб. Попробуйте позже")
    item = db.execute(select(DirectoryItem).where(DirectoryItem.id == item_id)).scalar_one_or_none()
    if not item or not item.is_published:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    recent = db.execute(
        select(DirectoryReport).where(
            DirectoryReport.directory_id == item_id,
            DirectoryReport.reporter_id == user.id,
            DirectoryReport.status == "open",
        )
    ).scalar_one_or_none()
    if recent:
        raise HTTPException(status_code=400, detail="Жалоба уже отправлена")
    db.add(
        DirectoryReport(
            directory_id=item_id,
            reporter_id=user.id,
            reason=payload.reason,
            note=(payload.note or "").strip() or None,
            status="open",
        )
    )
    db.flush()
    for staff in db.execute(
        select(User).where(
            User.role.in_([UserRole.admin, UserRole.editor, UserRole.moderator]),
            User.is_active.is_(True),
        )
    ).scalars().all():
        notify_user(
            db,
            user_id=staff.id,
            type="directory_reported",
            title="Жалоба на контакт справочника",
            body=f'«{item.title}»: неверные данные',
            listing_id=None,
        )
    db.commit()
    return {"ok": True}


@router.post("/{item_id}/favorite", response_model=DirectoryOut)
def add_directory_favorite(
    item_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = db.execute(
        select(DirectoryItem).options(selectinload(DirectoryItem.settlement)).where(DirectoryItem.id == item_id)
    ).scalar_one_or_none()
    if not item or not item.is_published:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    exists = db.execute(
        select(DirectoryFavorite).where(
            DirectoryFavorite.user_id == user.id,
            DirectoryFavorite.directory_id == item_id,
        )
    ).scalar_one_or_none()
    if not exists:
        db.add(DirectoryFavorite(user_id=user.id, directory_id=item_id))
        db.commit()
    return to_out(item, favorite_ids_for(db, user))


@router.delete("/{item_id}/favorite", response_model=DirectoryOut)
def remove_directory_favorite(
    item_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = db.execute(
        select(DirectoryItem).options(selectinload(DirectoryItem.settlement)).where(DirectoryItem.id == item_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    fav = db.execute(
        select(DirectoryFavorite).where(
            DirectoryFavorite.user_id == user.id,
            DirectoryFavorite.directory_id == item_id,
        )
    ).scalar_one_or_none()
    if fav:
        db.delete(fav)
        db.commit()
    return to_out(item, favorite_ids_for(db, user))


@router.post("", response_model=DirectoryOut)
def create_directory_item(
    payload: DirectoryCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    data = payload.model_dump()
    data["website"] = safe_http_url(data.get("website"))
    item = DirectoryItem(**data)
    db.add(item)
    db.commit()
    item = db.execute(
        select(DirectoryItem).options(selectinload(DirectoryItem.settlement)).where(DirectoryItem.id == item.id)
    ).scalar_one()
    return to_out(item)


@router.patch("/{item_id}", response_model=DirectoryOut)
def update_directory_item(
    item_id: int,
    payload: DirectoryUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(
        select(DirectoryItem).options(selectinload(DirectoryItem.settlement)).where(DirectoryItem.id == item_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    data = payload.model_dump(exclude_unset=True)
    if "website" in data:
        data["website"] = safe_http_url(data.get("website"))
    for key, value in data.items():
        setattr(item, key, value)
    db.commit()
    item = db.execute(
        select(DirectoryItem).options(selectinload(DirectoryItem.settlement)).where(DirectoryItem.id == item_id)
    ).scalar_one()
    return to_out(item)


@router.delete("/{item_id}")
def delete_directory_item(
    item_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(select(DirectoryItem).where(DirectoryItem.id == item_id)).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    db.delete(item)
    db.commit()
    return {"ok": True}
