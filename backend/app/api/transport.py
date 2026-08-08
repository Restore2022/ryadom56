from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user, get_optional_user, require_roles
from app.core.database import get_db
from app.models import TransportFavorite, TransportRoute, User, UserRole
from app.schemas import TransportCreate, TransportOut, TransportUpdate
from app.services.audit import log_action

router = APIRouter(prefix="/transport", tags=["transport"])


def _stops(text: str | None) -> list[str]:
    if not text:
        return []
    return [line.strip() for line in text.replace(";", "\n").splitlines() if line.strip()]


def favorite_ids_for(db: Session, user: User | None) -> set[int]:
    if not user:
        return set()
    rows = db.execute(select(TransportFavorite.route_id).where(TransportFavorite.user_id == user.id)).scalars().all()
    return set(rows)


def to_out(item: TransportRoute, favorited_ids: set[int] | None = None) -> TransportOut:
    return TransportOut(
        id=item.id,
        title=item.title,
        route_number=item.route_number,
        description=item.description,
        schedule_text=item.schedule_text,
        schedule_weekdays=item.schedule_weekdays,
        schedule_weekends=item.schedule_weekends,
        stops_text=item.stops_text,
        stops=_stops(item.stops_text),
        days_mode=item.days_mode or "all",
        notes=item.notes,
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        is_published=item.is_published,
        is_favorited=bool(favorited_ids and item.id in favorited_ids),
        view_count=item.view_count or 0,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _can_see_unpublished(user: User | None) -> bool:
    return bool(user and user.role in (UserRole.admin, UserRole.editor))


def _is_weekend(d: datetime | None = None) -> bool:
    day = (d or datetime.now()).weekday()
    return day >= 5


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
        .options(selectinload(TransportRoute.settlement))
        .where(TransportRoute.id.in_(fav_ids), TransportRoute.is_published.is_(True))
        .order_by(TransportRoute.title)
    )
    return [to_out(r, fav_ids) for r in db.execute(stmt).scalars().all()]


@router.get("", response_model=list[TransportOut])
def list_routes(
    settlement_id: int | None = None,
    q: str | None = None,
    day: str | None = Query(default=None, description="today|weekdays|weekends|all"),
    favorites_only: bool = False,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    stmt = select(TransportRoute).options(selectinload(TransportRoute.settlement))
    if not _can_see_unpublished(user):
        stmt = stmt.where(TransportRoute.is_published.is_(True))
    if settlement_id is not None:
        stmt = stmt.where(TransportRoute.settlement_id == settlement_id)
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                TransportRoute.title.ilike(like),
                TransportRoute.route_number.ilike(like),
                TransportRoute.description.ilike(like),
                TransportRoute.schedule_text.ilike(like),
                TransportRoute.stops_text.ilike(like),
                TransportRoute.notes.ilike(like),
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
            return []
        stmt = stmt.where(TransportRoute.id.in_(fav_ids))

    stmt = stmt.order_by(TransportRoute.title)
    return [to_out(r, fav_ids) for r in db.execute(stmt).scalars().all()]


@router.get("/{route_id}", response_model=TransportOut)
def get_route(
    route_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    item = db.execute(
        select(TransportRoute)
        .options(selectinload(TransportRoute.settlement))
        .where(TransportRoute.id == route_id)
    ).scalar_one_or_none()
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
    item = db.execute(
        select(TransportRoute)
        .options(selectinload(TransportRoute.settlement))
        .where(TransportRoute.id == route_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    if not item.is_published and not _can_see_unpublished(user):
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    item.view_count = (item.view_count or 0) + 1
    db.commit()
    item = db.execute(
        select(TransportRoute)
        .options(selectinload(TransportRoute.settlement))
        .where(TransportRoute.id == route_id)
    ).scalar_one()
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{route_id}/favorite", response_model=TransportOut)
def add_favorite(
    route_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = db.execute(
        select(TransportRoute)
        .options(selectinload(TransportRoute.settlement))
        .where(TransportRoute.id == route_id)
    ).scalar_one_or_none()
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
        db.commit()
    return to_out(item, favorite_ids_for(db, user))


@router.delete("/{route_id}/favorite", response_model=TransportOut)
def remove_favorite(
    route_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = db.execute(
        select(TransportRoute)
        .options(selectinload(TransportRoute.settlement))
        .where(TransportRoute.id == route_id)
    ).scalar_one_or_none()
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
        db.commit()
    return to_out(item, favorite_ids_for(db, user))


@router.post("", response_model=TransportOut)
def create_route(
    payload: TransportCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = TransportRoute(**payload.model_dump())
    db.add(item)
    db.flush()
    log_action(db, actor=user, action="transport.create", entity_type="transport", entity_id=item.id, details=item.title)
    db.commit()
    item = db.execute(
        select(TransportRoute).options(selectinload(TransportRoute.settlement)).where(TransportRoute.id == item.id)
    ).scalar_one()
    return to_out(item)


@router.patch("/{route_id}", response_model=TransportOut)
def update_route(
    route_id: int,
    payload: TransportUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(
        select(TransportRoute).options(selectinload(TransportRoute.settlement)).where(TransportRoute.id == route_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    log_action(db, actor=user, action="transport.update", entity_type="transport", entity_id=item.id, details=item.title)
    db.commit()
    item = db.execute(
        select(TransportRoute).options(selectinload(TransportRoute.settlement)).where(TransportRoute.id == route_id)
    ).scalar_one()
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
    db.execute(select(TransportFavorite).where(TransportFavorite.route_id == route_id))
    for fav in db.execute(select(TransportFavorite).where(TransportFavorite.route_id == route_id)).scalars().all():
        db.delete(fav)
    db.delete(item)
    db.commit()
    return {"ok": True}
