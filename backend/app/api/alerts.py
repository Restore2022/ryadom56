from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.api.deps import get_optional_user, require_roles
from app.core.database import get_db
from app.models import DistrictAlert, User, UserRole
from app.schemas import AlertCreate, AlertOut, AlertUpdate
from app.services.audit import log_action

router = APIRouter(prefix="/alerts", tags=["alerts"])


def to_out(item: DistrictAlert) -> AlertOut:
    return AlertOut(
        id=item.id,
        message=item.message,
        kind=item.kind,
        is_active=item.is_active,
        starts_at=item.starts_at,
        ends_at=item.ends_at,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


@router.get("/active", response_model=AlertOut | None)
def get_active_alert(
    db: Session = Depends(get_db),
    _: User | None = Depends(get_optional_user),
):
    now = datetime.now(timezone.utc)
    stmt = (
        select(DistrictAlert)
        .where(
            DistrictAlert.is_active.is_(True),
            or_(DistrictAlert.starts_at.is_(None), DistrictAlert.starts_at <= now),
            or_(DistrictAlert.ends_at.is_(None), DistrictAlert.ends_at >= now),
        )
        .order_by(DistrictAlert.updated_at.desc())
        .limit(1)
    )
    item = db.execute(stmt).scalar_one_or_none()
    return to_out(item) if item else None


@router.get("", response_model=list[AlertOut])
def list_alerts(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    rows = db.execute(select(DistrictAlert).order_by(DistrictAlert.updated_at.desc())).scalars().all()
    return [to_out(r) for r in rows]


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
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    log_action(db, actor=user, action="alert.update", entity_type="alert", entity_id=item.id, details=item.message[:80])
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
