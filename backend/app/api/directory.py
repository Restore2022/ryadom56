from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user, get_optional_user, require_roles
from app.core.database import get_db
from app.models import DirectoryCategory, DirectoryFavorite, DirectoryItem, User, UserRole
from app.schemas import DirectoryCreate, DirectoryOut, DirectoryUpdate

router = APIRouter(prefix="/directory", tags=["directory"])


def favorite_ids_for(db: Session, user: User | None) -> set[int]:
    if not user:
        return set()
    rows = db.execute(select(DirectoryFavorite.directory_id).where(DirectoryFavorite.user_id == user.id)).scalars().all()
    return set(rows)


def to_out(item: DirectoryItem, favorited_ids: set[int] | None = None) -> DirectoryOut:
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
        is_favorited=bool(favorited_ids and item.id in favorited_ids),
        created_at=item.created_at,
        updated_at=item.updated_at,
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
    fav_ids = favorite_ids_for(db, user)
    return [to_out(r, fav_ids) for r in db.execute(stmt).scalars().all()]


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
