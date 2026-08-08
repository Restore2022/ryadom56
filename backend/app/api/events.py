from datetime import datetime, timezone
from pathlib import Path
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_optional_user, require_roles
from app.core.database import get_db
from app.models import Event, User, UserRole
from app.schemas import EventCreate, EventOut, EventUpdate
from app.services.audit import log_action

router = APIRouter(prefix="/events", tags=["events"])

UPLOAD_ROOT = Path("data/uploads/events")
MAX_IMAGE_BYTES = 6 * 1024 * 1024
ALLOWED = {"image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png", "image/webp": ".webp"}


def _cover_url(path: str | None) -> str | None:
    if not path:
        return None
    return f"/uploads/{path.replace(chr(92), '/')}"


def _status(item: Event, now: datetime) -> str:
    if item.is_published:
        return "published"
    if item.publish_at and item.publish_at > now:
        return "scheduled"
    return "draft"


def publish_due(db: Session) -> None:
    now = datetime.now(timezone.utc)
    rows = db.execute(
        select(Event).where(Event.is_published.is_(False), Event.publish_at.is_not(None), Event.publish_at <= now)
    ).scalars().all()
    if not rows:
        return
    for row in rows:
        row.is_published = True
    db.commit()


def to_out(item: Event) -> EventOut:
    now = datetime.now(timezone.utc)
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
        cover_url=_cover_url(item.cover_path),
        publish_at=item.publish_at,
        is_published=item.is_published,
        view_count=item.view_count or 0,
        status=_status(item, now),
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
    status: str | None = Query(default=None, description="draft|scheduled|published — только staff"),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    publish_due(db)
    now = datetime.now(timezone.utc)
    staff = _can_see_unpublished(user)
    stmt = select(Event).options(selectinload(Event.settlement))
    if not staff:
        stmt = stmt.where(Event.is_published.is_(True))
    elif status == "draft":
        stmt = stmt.where(Event.is_published.is_(False), Event.publish_at.is_(None))
    elif status == "scheduled":
        stmt = stmt.where(Event.is_published.is_(False), Event.publish_at.is_not(None), Event.publish_at > now)
    elif status == "published":
        stmt = stmt.where(Event.is_published.is_(True))

    if settlement_id is not None:
        stmt = stmt.where(Event.settlement_id == settlement_id)
    if upcoming is True:
        stmt = stmt.where(Event.starts_at >= now)
    elif upcoming is False:
        stmt = stmt.where(Event.starts_at < now)
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
    publish_due(db)
    item = db.execute(
        select(Event).options(selectinload(Event.settlement)).where(Event.id == event_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Событие не найдено")
    if not item.is_published and not _can_see_unpublished(user):
        raise HTTPException(status_code=404, detail="Событие не найдено")
    return to_out(item)


@router.post("/{event_id}/view", response_model=EventOut)
def track_event_view(
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
    item.view_count = (item.view_count or 0) + 1
    db.commit()
    db.refresh(item)
    item = db.execute(
        select(Event).options(selectinload(Event.settlement)).where(Event.id == event_id)
    ).scalar_one()
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
    # scheduled: publish_at in future → keep unpublished until due
    if data.get("publish_at") and data["publish_at"] > datetime.now(timezone.utc):
        data["is_published"] = False
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
    if "publish_at" in data and data["publish_at"] and data["publish_at"] > datetime.now(timezone.utc):
        data["is_published"] = False
    for key, value in data.items():
        setattr(item, key, value)
    log_action(db, actor=user, action="event.update", entity_type="event", entity_id=item.id, details=item.title)
    db.commit()
    item = db.execute(
        select(Event).options(selectinload(Event.settlement)).where(Event.id == event_id)
    ).scalar_one()
    return to_out(item)


@router.post("/{event_id}/cover", response_model=EventOut)
async def upload_event_cover(
    event_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(
        select(Event).options(selectinload(Event.settlement)).where(Event.id == event_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Событие не найдено")
    ctype = (file.content_type or "").lower()
    if ctype not in ALLOWED:
        raise HTTPException(status_code=400, detail="Нужен JPG, PNG или WebP")
    raw = await file.read()
    if len(raw) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=400, detail="Файл слишком большой (макс. 6 МБ)")
    UPLOAD_ROOT.mkdir(parents=True, exist_ok=True)
    name = f"{uuid.uuid4().hex}{ALLOWED[ctype]}"
    rel = f"events/{name}"
    (UPLOAD_ROOT / name).write_bytes(raw)
    if item.cover_path:
        old = Path("data/uploads") / item.cover_path
        if old.is_file():
            old.unlink(missing_ok=True)
    item.cover_path = rel
    log_action(db, actor=user, action="event.cover", entity_type="event", entity_id=item.id, details=rel)
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
    if item.cover_path:
        old = Path("data/uploads") / item.cover_path
        old.unlink(missing_ok=True)
    db.delete(item)
    db.commit()
    return {"ok": True}
