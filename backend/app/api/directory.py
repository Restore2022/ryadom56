from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_optional_user, require_roles
from app.core.database import get_db
from app.models import DirectoryCategory, DirectoryItem, User, UserRole
from app.schemas import DirectoryCreate, DirectoryOut, DirectoryUpdate

router = APIRouter(prefix="/directory", tags=["directory"])


def to_out(item: DirectoryItem) -> DirectoryOut:
    return DirectoryOut(
        id=item.id,
        title=item.title,
        category=item.category,
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        description=item.description,
        address=item.address,
        phone=item.phone,
        website=item.website,
        hours=item.hours,
        lat=item.lat,
        lon=item.lon,
        is_published=item.is_published,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


@router.get("", response_model=list[DirectoryOut])
def list_directory(
    category: DirectoryCategory | None = None,
    settlement_id: int | None = None,
    q: str | None = None,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    stmt = select(DirectoryItem).options(selectinload(DirectoryItem.settlement))
    is_staff = user and user.role in (UserRole.admin, UserRole.editor, UserRole.moderator)
    if not is_staff:
        stmt = stmt.where(DirectoryItem.is_published.is_(True))
    if category:
        stmt = stmt.where(DirectoryItem.category == category)
    if settlement_id:
        stmt = stmt.where(DirectoryItem.settlement_id == settlement_id)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            DirectoryItem.title.ilike(like)
            | DirectoryItem.description.ilike(like)
            | DirectoryItem.address.ilike(like)
            | DirectoryItem.phone.ilike(like)
        )
    stmt = stmt.order_by(DirectoryItem.title)
    return [to_out(r) for r in db.execute(stmt).scalars().all()]


@router.get("/{item_id}", response_model=DirectoryOut)
def get_directory_item(item_id: int, db: Session = Depends(get_db)):
    item = db.execute(
        select(DirectoryItem).options(selectinload(DirectoryItem.settlement)).where(DirectoryItem.id == item_id)
    ).scalar_one_or_none()
    if not item or not item.is_published:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    return to_out(item)


@router.post("", response_model=DirectoryOut)
def create_directory_item(
    payload: DirectoryCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = DirectoryItem(**payload.model_dump())
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
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    db.commit()
    db.refresh(item)
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
