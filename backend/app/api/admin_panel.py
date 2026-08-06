from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import require_roles
from app.core.database import get_db
from app.models import DirectoryItem, Listing, ListingStatus, Settlement, User, UserRole
from app.schemas import StatsOut, UserOut, UserRoleUpdate

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/stats", response_model=StatsOut)
def stats(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator, UserRole.editor)),
):
    return StatsOut(
        users=db.execute(select(func.count(User.id))).scalar_one(),
        listings_pending=db.execute(
            select(func.count(Listing.id)).where(Listing.status == ListingStatus.pending)
        ).scalar_one(),
        listings_approved=db.execute(
            select(func.count(Listing.id)).where(Listing.status == ListingStatus.approved)
        ).scalar_one(),
        directory_items=db.execute(select(func.count(DirectoryItem.id))).scalar_one(),
        settlements=db.execute(select(func.count(Settlement.id))).scalar_one(),
    )


@router.get("/users", response_model=list[UserOut])
def list_users(
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    return db.execute(
        select(User).options(selectinload(User.settlement)).order_by(User.created_at.desc())
    ).scalars().all()


@router.patch("/users/{user_id}", response_model=UserOut)
def update_user_role(
    user_id: int,
    payload: UserRoleUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.admin)),
):
    target = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user_id)
    ).scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if target.id == admin.id and payload.role != UserRole.admin:
        raise HTTPException(status_code=400, detail="Нельзя снять с себя роль админа")
    target.role = payload.role
    if payload.is_active is not None:
        target.is_active = payload.is_active
    db.commit()
    db.refresh(target)
    return target
