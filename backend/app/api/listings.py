from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user, get_optional_user, require_roles
from app.core.database import get_db
from app.models import Listing, ListingCategory, ListingStatus, User, UserRole
from app.schemas import ListingCreate, ListingModerationIn, ListingOut, ListingUpdate

router = APIRouter(prefix="/listings", tags=["listings"])


def to_out(item: Listing) -> ListingOut:
    return ListingOut(
        id=item.id,
        author_id=item.author_id,
        author_name=item.author.full_name if item.author else None,
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        category=item.category,
        title=item.title,
        description=item.description,
        price=item.price,
        contact_phone=item.contact_phone or (item.author.phone if item.author else None),
        status=item.status,
        moderation_note=item.moderation_note,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


@router.get("/admin/all", response_model=list[ListingOut])
def admin_list_listings(
    status_filter: ListingStatus | None = Query(default=None, alias="status"),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    stmt = select(Listing).options(selectinload(Listing.author), selectinload(Listing.settlement))
    if status_filter:
        stmt = stmt.where(Listing.status == status_filter)
    stmt = stmt.order_by(Listing.created_at.desc())
    return [to_out(r) for r in db.execute(stmt).scalars().all()]


@router.get("", response_model=list[ListingOut])
def list_listings(
    category: ListingCategory | None = None,
    settlement_id: int | None = None,
    q: str | None = None,
    sort: str = Query(default="newest", pattern="^(newest|oldest|price_asc|price_desc)$"),
    mine: bool = False,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    stmt = select(Listing).options(selectinload(Listing.author), selectinload(Listing.settlement))
    if mine:
        if not user:
            raise HTTPException(status_code=401, detail="Требуется авторизация")
        stmt = stmt.where(Listing.author_id == user.id)
    else:
        stmt = stmt.where(Listing.status == ListingStatus.approved)
    if category:
        stmt = stmt.where(Listing.category == category)
    if settlement_id:
        stmt = stmt.where(Listing.settlement_id == settlement_id)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(Listing.title.ilike(like) | Listing.description.ilike(like))
    if sort == "oldest":
        stmt = stmt.order_by(Listing.created_at.asc())
    elif sort == "price_asc":
        stmt = stmt.order_by(Listing.price.asc(), Listing.created_at.desc())
    elif sort == "price_desc":
        stmt = stmt.order_by(Listing.price.desc(), Listing.created_at.desc())
    else:
        stmt = stmt.order_by(Listing.created_at.desc())
    return [to_out(r) for r in db.execute(stmt).scalars().all()]


@router.get("/{listing_id}", response_model=ListingOut)
def get_listing(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    item = db.execute(
        select(Listing)
        .options(selectinload(Listing.author), selectinload(Listing.settlement))
        .where(Listing.id == listing_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.status != ListingStatus.approved:
        if not user or (user.id != item.author_id and user.role not in (UserRole.admin, UserRole.moderator)):
            raise HTTPException(status_code=404, detail="Объявление не найдено")
    return to_out(item)


@router.post("", response_model=ListingOut)
def create_listing(
    payload: ListingCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = Listing(
        author_id=user.id,
        settlement_id=payload.settlement_id,
        category=payload.category,
        title=payload.title.strip(),
        description=payload.description.strip(),
        price=payload.price,
        contact_phone=payload.contact_phone,
        status=ListingStatus.pending,
    )
    db.add(item)
    db.commit()
    item = db.execute(
        select(Listing)
        .options(selectinload(Listing.author), selectinload(Listing.settlement))
        .where(Listing.id == item.id)
    ).scalar_one()
    return to_out(item)


@router.patch("/{listing_id}", response_model=ListingOut)
def update_listing(
    listing_id: int,
    payload: ListingUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = db.execute(
        select(Listing)
        .options(selectinload(Listing.author), selectinload(Listing.settlement))
        .where(Listing.id == listing_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    if item.author_id == user.id and user.role == UserRole.user:
        item.status = ListingStatus.pending
    db.commit()
    db.refresh(item)
    return to_out(item)


@router.post("/{listing_id}/moderate", response_model=ListingOut)
def moderate_listing(
    listing_id: int,
    payload: ListingModerationIn,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    if payload.status not in (ListingStatus.approved, ListingStatus.rejected, ListingStatus.archived):
        raise HTTPException(status_code=400, detail="Недопустимый статус модерации")
    item = db.execute(
        select(Listing)
        .options(selectinload(Listing.author), selectinload(Listing.settlement))
        .where(Listing.id == listing_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    item.status = payload.status
    item.moderation_note = payload.moderation_note
    db.commit()
    db.refresh(item)
    return to_out(item)
