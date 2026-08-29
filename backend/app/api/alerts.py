from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import and_, not_, or_, select
from sqlalchemy.orm import Session

from app.api.deps import get_optional_user, require_roles
from app.core.database import get_db
from app.models import DistrictAlert, User, UserRole
from app.schemas import AlertCreate, AlertOut, AlertUpdate
from app.services.audit import log_action
from app.services.notify import notify_broadcast

router = APIRouter(prefix="/alerts", tags=["alerts"])


def to_out(item: DistrictAlert) -> AlertOut:
    return AlertOut(
        id=item.id,
        message=item.message,
        kind=item.kind,
        priority=item.priority or 0,
        is_active=item.is_active,
        starts_at=item.starts_at,
        ends_at=item.ends_at,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _alert_title(kind: str | None) -> str:
    if kind == "danger":
        return "Срочное сообщение района"
    if kind == "warn":
        return "Важное сообщение района"
    return "Сообщение района"


def _push_alert(db, item: DistrictAlert) -> None:
    if not item.is_active:
        return
    notify_broadcast(
        db,
        type="district_alert",
        title=_alert_title(item.kind),
        body=(item.message or "")[:400],
        extra={"alert_id": item.id, "kind": item.kind or "info"},
    )


def _live_cond(now: datetime):
    return and_(
        DistrictAlert.is_active.is_(True),
        or_(DistrictAlert.starts_at.is_(None), DistrictAlert.starts_at <= now),
        or_(DistrictAlert.ends_at.is_(None), DistrictAlert.ends_at >= now),
    )


def _active_stmt(now: datetime):
    return select(DistrictAlert).where(_live_cond(now))


@router.get("/active", response_model=AlertOut | None)
def get_active_alert(
    db: Session = Depends(get_db),
    _: User | None = Depends(get_optional_user),
):
    """Один самый приоритетный баннер (обратная совместимость)."""
    now = datetime.now(timezone.utc)
    stmt = _active_stmt(now).order_by(DistrictAlert.priority.desc(), DistrictAlert.updated_at.desc()).limit(1)
    item = db.execute(stmt).scalar_one_or_none()
    return to_out(item) if item else None


@router.get("/active/list", response_model=list[AlertOut])
def list_active_alerts(
    limit: int = Query(default=5, ge=1, le=20),
    db: Session = Depends(get_db),
    _: User | None = Depends(get_optional_user),
):
    now = datetime.now(timezone.utc)
    stmt = _active_stmt(now).order_by(DistrictAlert.priority.desc(), DistrictAlert.updated_at.desc()).limit(limit)
    return [to_out(r) for r in db.execute(stmt).scalars().all()]


@router.get("", response_model=list[AlertOut])
def list_alerts(
    history: bool = False,
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    now = datetime.now(timezone.utc)
    stmt = select(DistrictAlert).where(not_(_live_cond(now)) if history else _live_cond(now))
    stmt = stmt.order_by(DistrictAlert.priority.desc(), DistrictAlert.updated_at.desc())
    return [to_out(r) for r in db.execute(stmt).scalars().all()]


@router.get("/{alert_id}", response_model=AlertOut)
def get_alert(
    alert_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(select(DistrictAlert).where(DistrictAlert.id == alert_id)).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    return to_out(item)


@router.post("", response_model=AlertOut)
def create_alert(
    payload: AlertCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = DistrictAlert(**payload.model_dump(), created_by_id=user.id)
    db.add(item)
    db.flush()
    log_action(db, actor=user, action="alert.create", entity_type="alert", entity_id=item.id, details=item.message[:80])
    _push_alert(db, item)
    db.commit()
    db.refresh(item)
    return to_out(item)


@router.patch("/{alert_id}", response_model=AlertOut)
def update_alert(
    alert_id: int,
    payload: AlertUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(select(DistrictAlert).where(DistrictAlert.id == alert_id)).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    was_active = bool(item.is_active)
    changes = payload.model_dump(exclude_unset=True)
    for key, value in changes.items():
        setattr(item, key, value)
    log_action(db, actor=user, action="alert.update", entity_type="alert", entity_id=item.id, details=item.message[:80])
    became_active = bool(item.is_active) and not was_active
    if item.is_active and (became_active or "message" in changes):
        _push_alert(db, item)
    db.commit()
    db.refresh(item)
    return to_out(item)


@router.delete("/{alert_id}")
def delete_alert(
    alert_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(select(DistrictAlert).where(DistrictAlert.id == alert_id)).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    log_action(db, actor=user, action="alert.delete", entity_type="alert", entity_id=item.id, details=item.message[:80])
    db.delete(item)
    db.commit()
    return {"ok": True}
