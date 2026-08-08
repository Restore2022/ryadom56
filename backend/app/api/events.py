from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_optional_user, require_roles
from app.core.database import get_db
from app.models import Event, User, UserRole
from app.schemas import EventCreate, EventOut, EventUpdate
from app.services.audit import log_action

router = APIRouter(prefix="/events", tags=["events"])


def to_out(item: Event) -> EventOut:
    return EventOut(
        id=item.id,
        title=item.title,
        description=item.description,
        starts_at=item.starts_at,
        ends_at=item.ends_at,
        place_text=item.place_text,
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        address=item.address,
        lat=item.lat,
        lon=item.lon,
        is_published=item.is_published,
        created_by_id=item.created_by_id,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _can_see_unpublished(user: User | None) -> bool:
    return bool(user and user.role in (UserRole.admin, UserRole.editor))


@router.get("", response_model=list[EventOut])
def list_events(
    settlement_id: int | None = None,
    upcoming: bool | None = Query(default=None),
    q: str | None = None,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    stmt = select(Event).options(selectinload(Event.settlement))
    if not _can_see_unpublished(user):
        stmt = stmt.where(Event.is_published.is_(True))
    if settlement_id is not None:
        stmt = stmt.where(Event.settlement_id == settlement_id)
    if upcoming is True:
        stmt = stmt.where(Event.starts_at >= datetime.now(timezone.utc))
    elif upcoming is False:
        stmt = stmt.where(Event.starts_at < datetime.now(timezone.utc))
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                Event.title.ilike(like),
                Event.description.ilike(like),
                Event.place_text.ilike(like),
                Event.address.ilike(like),
            )
        )
    stmt = stmt.order_by(Event.starts_at.asc() if upcoming is not False else Event.starts_at.desc())
    return [to_out(r) for r in db.execute(stmt).scalars().all()]


@router.get("/{event_id}", response_model=EventOut)
def get_event(
    event_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    item = db.execute(
        select(Event).options(selectinload(Event.settlement)).where(Event.id == event_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Событие не найдено")
    if not item.is_published and not _can_see_unpublished(user):
        raise HTTPException(status_code=404, detail="Событие не найдено")
    return to_out(item)


@router.post("", response_model=EventOut)
def create_event(
    payload: EventCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    data = payload.model_dump()
    if data.get("ends_at") and data["ends_at"] < data["starts_at"]:
        raise HTTPException(status_code=400, detail="Дата окончания раньше начала")
    item = Event(**data, created_by_id=user.id)
    db.add(item)
    db.flush()
    log_action(db, actor=user, action="event.create", entity_type="event", entity_id=item.id, details=item.title)
    db.commit()
    item = db.execute(
        select(Event).options(selectinload(Event.settlement)).where(Event.id == item.id)
    ).scalar_one()
    return to_out(item)


@router.patch("/{event_id}", response_model=EventOut)
def update_event(
    event_id: int,
    payload: EventUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(
        select(Event).options(selectinload(Event.settlement)).where(Event.id == event_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Событие не найдено")
    data = payload.model_dump(exclude_unset=True)
    starts = data.get("starts_at", item.starts_at)
    ends = data.get("ends_at", item.ends_at)
    if ends is not None and starts is not None and ends < starts:
        raise HTTPException(status_code=400, detail="Дата окончания раньше начала")
    for key, value in data.items():
        setattr(item, key, value)
    log_action(db, actor=user, action="event.update", entity_type="event", entity_id=item.id, details=item.title)
    db.commit()
    item = db.execute(
        select(Event).options(selectinload(Event.settlement)).where(Event.id == event_id)
    ).scalar_one()
    return to_out(item)


@router.delete("/{event_id}")
def delete_event(
    event_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(select(Event).where(Event.id == event_id)).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Событие не найдено")
    log_action(db, actor=user, action="event.delete", entity_type="event", entity_id=item.id, details=item.title)
    db.delete(item)
    db.commit()
    return {"ok": True}
