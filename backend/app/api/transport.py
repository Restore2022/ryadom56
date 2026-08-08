from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_optional_user, require_roles
from app.core.database import get_db
from app.models import TransportRoute, User, UserRole
from app.schemas import TransportCreate, TransportOut, TransportUpdate
from app.services.audit import log_action

router = APIRouter(prefix="/transport", tags=["transport"])


def to_out(item: TransportRoute) -> TransportOut:
    return TransportOut(
        id=item.id,
        title=item.title,
        route_number=item.route_number,
        description=item.description,
        schedule_text=item.schedule_text,
        notes=item.notes,
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        is_published=item.is_published,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _can_see_unpublished(user: User | None) -> bool:
    return bool(user and user.role in (UserRole.admin, UserRole.editor))


@router.get("", response_model=list[TransportOut])
def list_routes(
    settlement_id: int | None = None,
    q: str | None = None,
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
            )
        )
    stmt = stmt.order_by(TransportRoute.title)
    return [to_out(r) for r in db.execute(stmt).scalars().all()]


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
    return to_out(item)


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
        select(TransportRoute)
        .options(selectinload(TransportRoute.settlement))
        .where(TransportRoute.id == item.id)
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
        select(TransportRoute)
        .options(selectinload(TransportRoute.settlement))
        .where(TransportRoute.id == route_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Маршрут не найден")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    log_action(db, actor=user, action="transport.update", entity_type="transport", entity_id=item.id, details=item.title)
    db.commit()
    item = db.execute(
        select(TransportRoute)
        .options(selectinload(TransportRoute.settlement))
        .where(TransportRoute.id == route_id)
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
    db.delete(item)
    db.commit()
    return {"ok": True}
