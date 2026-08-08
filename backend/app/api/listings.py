from pathlib import Path
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy import exists, func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user, get_optional_user, require_roles
from app.core.database import get_db
from app.models import (
    Favorite,
    Listing,
    ListingCategory,
    ListingImage,
    ListingReport,
    ListingStatus,
    User,
    UserRole,
)
from app.schemas import (
    ListingCloseIn,
    ListingCreate,
    ListingImageOut,
    ListingImagesReorderIn,
    ListingModerationIn,
    ListingOut,
    ListingPageOut,
    ListingReportIn,
    ListingUpdate,
)
from app.services.audit import log_action
from app.services.notify import notify_user

router = APIRouter(prefix="/listings", tags=["listings"])

UPLOAD_ROOT = Path("data/uploads")
MAX_IMAGES = 5
MAX_IMAGE_BYTES = 6 * 1024 * 1024
ALLOWED_TYPES = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}

CLOSE_REASON_LABELS = {
    "sold": "Продали / отдали",
    "not_relevant": "Неактуально",
    "busy": "Пока занят / нет времени",
    "other": "Другое",
}

MAX_ACTIVE_LISTINGS = 5


def image_url(path: str) -> str:
    return f"/uploads/{path.replace(chr(92), '/')}"


def count_active_listings(db: Session, user_id: int, exclude_id: int | None = None) -> int:
    stmt = select(func.count()).select_from(Listing).where(
        Listing.author_id == user_id,
        Listing.status.in_([ListingStatus.pending, ListingStatus.approved]),
    )
    if exclude_id is not None:
        stmt = stmt.where(Listing.id != exclude_id)
    return int(db.execute(stmt).scalar_one())


def ensure_active_slot(db: Session, user_id: int, exclude_id: int | None = None) -> None:
    if count_active_listings(db, user_id, exclude_id=exclude_id) >= MAX_ACTIVE_LISTINGS:
        raise HTTPException(
            status_code=400,
            detail=f"Лимит активных объявлений: {MAX_ACTIVE_LISTINGS}. Снимите или дождитесь решения по текущим.",
        )


def to_out(item: Listing, favorited_ids: set[int] | None = None) -> ListingOut:
    images = [
        ListingImageOut(id=img.id, url=image_url(img.path), sort_order=img.sort_order)
        for img in (item.images or [])
    ]
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
        close_reason=item.close_reason,
        close_note=item.close_note,
        is_urgent=bool(getattr(item, "is_urgent", False)),
        images=images,
        is_favorited=bool(favorited_ids and item.id in favorited_ids),
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def load_listing(db: Session, listing_id: int) -> Listing | None:
    return db.execute(
        select(Listing)
        .options(
            selectinload(Listing.author),
            selectinload(Listing.settlement),
            selectinload(Listing.images),
        )
        .where(Listing.id == listing_id)
    ).scalar_one_or_none()


def favorite_ids_for(db: Session, user: User | None) -> set[int]:
    if not user:
        return set()
    rows = db.execute(select(Favorite.listing_id).where(Favorite.user_id == user.id)).scalars().all()
    return set(rows)


@router.get("/admin/all", response_model=list[ListingOut])
def admin_list_listings(
    status_filter: ListingStatus | None = Query(default=None, alias="status"),
    q: str | None = None,
    closed_by_user: bool = False,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    stmt = select(Listing).options(
        selectinload(Listing.author),
        selectinload(Listing.settlement),
        selectinload(Listing.images),
    )
    if status_filter:
        stmt = stmt.where(Listing.status == status_filter)
    if closed_by_user:
        stmt = stmt.where(Listing.status == ListingStatus.archived, Listing.close_reason.is_not(None))
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.join(Listing.author).where(
            or_(
                Listing.title.ilike(like),
                Listing.description.ilike(like),
                User.full_name.ilike(like),
                User.email.ilike(like),
                User.phone.ilike(like),
                Listing.contact_phone.ilike(like),
            )
        )
    stmt = stmt.order_by(Listing.created_at.desc())
    return [to_out(r) for r in db.execute(stmt).scalars().unique().all()]


@router.get("/favorites", response_model=list[ListingOut])
def list_favorites(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    stmt = (
        select(Listing)
        .join(Favorite, Favorite.listing_id == Listing.id)
        .where(Favorite.user_id == user.id)
        .options(
            selectinload(Listing.author),
            selectinload(Listing.settlement),
            selectinload(Listing.images),
        )
        .order_by(Favorite.created_at.desc())
    )
    fav_ids = favorite_ids_for(db, user)
    return [to_out(r, fav_ids) for r in db.execute(stmt).scalars().unique().all()]


@router.get("", response_model=ListingPageOut)
def list_listings(
    category: ListingCategory | None = None,
    settlement_id: int | None = None,
    q: str | None = None,
    sort: str = Query(default="newest", pattern="^(newest|oldest|price_asc|price_desc)$"),
    mine: bool = False,
    author_id: int | None = None,
    has_photos: bool | None = None,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    stmt = select(Listing).options(
        selectinload(Listing.author),
        selectinload(Listing.settlement),
        selectinload(Listing.images),
    )
    if mine:
        if not user:
            raise HTTPException(status_code=401, detail="Требуется авторизация")
        stmt = stmt.where(Listing.author_id == user.id)
    else:
        stmt = stmt.where(Listing.status == ListingStatus.approved)
        if author_id is not None:
            stmt = stmt.where(Listing.author_id == author_id)
    if category:
        stmt = stmt.where(Listing.category == category)
    if settlement_id:
        stmt = stmt.where(Listing.settlement_id == settlement_id)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(Listing.title.ilike(like) | Listing.description.ilike(like))
    if has_photos is True:
        stmt = stmt.where(exists().where(ListingImage.listing_id == Listing.id))
    elif has_photos is False:
        stmt = stmt.where(~exists().where(ListingImage.listing_id == Listing.id))
    if sort == "oldest":
        stmt = stmt.order_by(Listing.created_at.asc())
    elif sort == "price_asc":
        stmt = stmt.order_by(Listing.price.asc(), Listing.created_at.desc())
    elif sort == "price_desc":
        stmt = stmt.order_by(Listing.price.desc(), Listing.created_at.desc())
    else:
        stmt = stmt.order_by(Listing.created_at.desc())

    count_stmt = select(func.count()).select_from(Listing)
    if mine:
        count_stmt = count_stmt.where(Listing.author_id == user.id)
    else:
        count_stmt = count_stmt.where(Listing.status == ListingStatus.approved)
        if author_id is not None:
            count_stmt = count_stmt.where(Listing.author_id == author_id)
    if category:
        count_stmt = count_stmt.where(Listing.category == category)
    if settlement_id:
        count_stmt = count_stmt.where(Listing.settlement_id == settlement_id)
    if q:
        like = f"%{q.strip()}%"
        count_stmt = count_stmt.where(Listing.title.ilike(like) | Listing.description.ilike(like))
    if has_photos is True:
        count_stmt = count_stmt.where(exists().where(ListingImage.listing_id == Listing.id))
    elif has_photos is False:
        count_stmt = count_stmt.where(~exists().where(ListingImage.listing_id == Listing.id))
    total = int(db.execute(count_stmt).scalar_one())

    stmt = stmt.offset(offset).limit(limit)
    fav_ids = favorite_ids_for(db, user)
    items = [to_out(r, fav_ids) for r in db.execute(stmt).scalars().unique().all()]
    return ListingPageOut(items=items, total=total, limit=limit, offset=offset)


@router.get("/{listing_id}", response_model=ListingOut)
def get_listing(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.status != ListingStatus.approved:
        if not user or (user.id != item.author_id and user.role not in (UserRole.admin, UserRole.moderator)):
            raise HTTPException(status_code=404, detail="Объявление не найдено")
    return to_out(item, favorite_ids_for(db, user))


@router.post("", response_model=ListingOut)
def create_listing(
    payload: ListingCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    data = payload.model_dump()
    as_draft = bool(data.pop("as_draft", False))
    if not as_draft:
        ensure_active_slot(db, user.id)
    item = Listing(
        author_id=user.id,
        settlement_id=data["settlement_id"],
        category=data["category"],
        title=data["title"].strip(),
        description=data["description"].strip(),
        price=data.get("price"),
        contact_phone=data.get("contact_phone"),
        is_urgent=bool(data.get("is_urgent", False)),
        status=ListingStatus.draft if as_draft else ListingStatus.pending,
    )
    db.add(item)
    db.commit()
    item = load_listing(db, item.id)
    return to_out(item, favorite_ids_for(db, user))


@router.patch("/{listing_id}", response_model=ListingOut)
def update_listing(
    listing_id: int,
    payload: ListingUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    data = payload.model_dump(exclude_unset=True)
    as_draft = data.pop("as_draft", None)
    for key, value in data.items():
        setattr(item, key, value)
    if item.author_id == user.id:
        if as_draft is True:
            item.status = ListingStatus.draft
        else:
            if item.status not in (ListingStatus.pending, ListingStatus.approved):
                ensure_active_slot(db, user.id, exclude_id=item.id)
            item.status = ListingStatus.pending
        item.close_reason = None
        item.close_note = None
        if as_draft is not True:
            item.moderation_note = None
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{listing_id}/close", response_model=ListingOut)
def close_listing(
    listing_id: int,
    payload: ListingCloseIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    item.status = ListingStatus.archived
    item.close_reason = payload.reason
    item.close_note = (payload.note or "").strip() or CLOSE_REASON_LABELS.get(payload.reason)
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{listing_id}/republish", response_model=ListingOut)
def republish_listing(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id:
        raise HTTPException(status_code=403, detail="Нет доступа")
    if item.status not in (ListingStatus.archived, ListingStatus.rejected, ListingStatus.draft):
        raise HTTPException(status_code=400, detail="Повторно опубликовать можно черновик, снятое или отклонённое")
    ensure_active_slot(db, user.id, exclude_id=item.id)
    item.status = ListingStatus.pending
    item.close_reason = None
    item.close_note = None
    item.moderation_note = None
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{listing_id}/favorite", response_model=ListingOut)
def add_favorite(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item or item.status != ListingStatus.approved:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    exists = db.execute(
        select(Favorite).where(Favorite.user_id == user.id, Favorite.listing_id == listing_id)
    ).scalar_one_or_none()
    if not exists:
        db.add(Favorite(user_id=user.id, listing_id=listing_id))
        db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user))


@router.delete("/{listing_id}/favorite", response_model=ListingOut)
def remove_favorite(
    listing_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    fav = db.execute(
        select(Favorite).where(Favorite.user_id == user.id, Favorite.listing_id == listing_id)
    ).scalar_one_or_none()
    if fav:
        db.delete(fav)
        db.commit()
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{listing_id}/report")
def report_listing(
    listing_id: int,
    payload: ListingReportIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id == user.id:
        raise HTTPException(status_code=400, detail="Нельзя пожаловаться на своё объявление")
    recent = db.execute(
        select(ListingReport).where(
            ListingReport.listing_id == listing_id,
            ListingReport.reporter_id == user.id,
            ListingReport.status == "open",
        )
    ).scalar_one_or_none()
    if recent:
        raise HTTPException(status_code=400, detail="Жалоба уже отправлена")
    db.add(
        ListingReport(
            listing_id=listing_id,
            reporter_id=user.id,
            reason=payload.reason,
            note=(payload.note or "").strip() or None,
            status="open",
        )
    )
    db.commit()
    return {"ok": True}


@router.post("/{listing_id}/images", response_model=ListingOut)
async def upload_listing_images(
    listing_id: int,
    files: list[UploadFile] = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")

    current = len(item.images or [])
    if current >= MAX_IMAGES:
        raise HTTPException(status_code=400, detail=f"Максимум {MAX_IMAGES} фото")
    if not files:
        raise HTTPException(status_code=400, detail="Нет файлов")

    folder = UPLOAD_ROOT / "listings" / str(listing_id)
    folder.mkdir(parents=True, exist_ok=True)
    next_order = current

    for upload in files:
        if current + 1 > MAX_IMAGES:
            break
        content_type = (upload.content_type or "").lower()
        ext = ALLOWED_TYPES.get(content_type)
        if not ext:
            raise HTTPException(status_code=400, detail="Допустимы JPG, PNG, WEBP")
        data = await upload.read()
        if not data:
            continue
        if len(data) > MAX_IMAGE_BYTES:
            raise HTTPException(status_code=400, detail="Фото больше 6 МБ")
        filename = f"{uuid.uuid4().hex}{ext}"
        rel = f"listings/{listing_id}/{filename}"
        (UPLOAD_ROOT / rel).write_bytes(data)
        db.add(ListingImage(listing_id=listing_id, path=rel, sort_order=next_order))
        next_order += 1
        current += 1

    if item.author_id == user.id and item.status == ListingStatus.approved:
        item.status = ListingStatus.pending

    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user))


@router.delete("/{listing_id}/images/{image_id}", response_model=ListingOut)
def delete_listing_image(
    listing_id: int,
    image_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    image = next((img for img in item.images if img.id == image_id), None)
    if not image:
        raise HTTPException(status_code=404, detail="Фото не найдено")
    file_path = UPLOAD_ROOT / image.path
    if file_path.exists():
        file_path.unlink()
    db.delete(image)
    if item.author_id == user.id and item.status == ListingStatus.approved:
        item.status = ListingStatus.pending
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user))


@router.patch("/{listing_id}/images/reorder", response_model=ListingOut)
def reorder_listing_images(
    listing_id: int,
    payload: ListingImagesReorderIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if item.author_id != user.id and user.role not in (UserRole.admin, UserRole.moderator):
        raise HTTPException(status_code=403, detail="Нет доступа")
    by_id = {img.id: img for img in (item.images or [])}
    if len(payload.image_ids) != len(by_id) or set(payload.image_ids) != set(by_id):
        raise HTTPException(status_code=400, detail="Список фото не совпадает с объявлением")
    for order, image_id in enumerate(payload.image_ids):
        by_id[image_id].sort_order = order
    if item.author_id == user.id and item.status == ListingStatus.approved:
        item.status = ListingStatus.pending
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item, favorite_ids_for(db, user))


@router.post("/{listing_id}/moderate", response_model=ListingOut)
def moderate_listing(
    listing_id: int,
    payload: ListingModerationIn,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.moderator, UserRole.admin)),
):
    if payload.status not in (ListingStatus.approved, ListingStatus.rejected, ListingStatus.archived):
        raise HTTPException(status_code=400, detail="Недопустимый статус модерации")
    if payload.status == ListingStatus.rejected and not (payload.moderation_note or "").strip():
        raise HTTPException(status_code=400, detail="Укажите причину отклонения")
    item = load_listing(db, listing_id)
    if not item:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    old = item.status.value
    item.status = payload.status
    item.moderation_note = payload.moderation_note
    log_action(
        db,
        actor=user,
        action=f"moderate:{payload.status.value}",
        entity_type="listing",
        entity_id=item.id,
        details=f"{old} → {payload.status.value}; note={payload.moderation_note or ''}",
    )
    if payload.status == ListingStatus.approved:
        notify_user(
            db,
            user_id=item.author_id,
            type="listing_approved",
            title="Объявление одобрено",
            body=f"«{item.title}» опубликовано и видно в ленте.",
            listing_id=item.id,
        )
    elif payload.status == ListingStatus.rejected:
        note = (payload.moderation_note or "").strip()
        body = f"«{item.title}» отклонено."
        if note:
            body = f"{body} Причина: {note}"
        notify_user(
            db,
            user_id=item.author_id,
            type="listing_rejected",
            title="Объявление отклонено",
            body=body,
            listing_id=item.id,
        )
    db.commit()
    item = load_listing(db, listing_id)
    return to_out(item)
