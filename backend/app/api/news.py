from datetime import datetime, timezone
from pathlib import Path
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_optional_user, require_roles
from app.core.database import get_db
from app.models import DistrictNews, User, UserRole
from app.schemas import NewsCreate, NewsOut, NewsPageOut, NewsUpdate
from app.services.audit import log_action

router = APIRouter(prefix="/news", tags=["news"])

UPLOAD_ROOT = Path("data/uploads/news")
MAX_IMAGE_BYTES = 6 * 1024 * 1024
ALLOWED = {"image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png", "image/webp": ".webp"}


def _cover_url(path: str | None) -> str | None:
    if not path:
        return None
    return f"/uploads/{path.replace(chr(92), '/')}"


def to_out(item: DistrictNews) -> NewsOut:
    return NewsOut(
        id=item.id,
        title=item.title,
        body=item.body,
        cover_url=_cover_url(item.cover_path),
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        is_published=item.is_published,
        is_pinned=bool(item.is_pinned),
        published_at=item.published_at,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _staff(user: User | None) -> bool:
    return bool(user and user.role in (UserRole.admin, UserRole.editor))


@router.get("", response_model=NewsPageOut)
def list_news(
    settlement_id: int | None = None,
    limit: int = Query(default=20, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    stmt = select(DistrictNews).options(selectinload(DistrictNews.settlement))
    if not _staff(user):
        stmt = stmt.where(DistrictNews.is_published.is_(True))
    if settlement_id is not None:
        stmt = stmt.where(
            (DistrictNews.settlement_id == settlement_id) | (DistrictNews.settlement_id.is_(None))
        )
    count_stmt = select(func.count()).select_from(stmt.subquery())
    total = int(db.execute(count_stmt).scalar_one())
    stmt = stmt.order_by(DistrictNews.is_pinned.desc(), DistrictNews.published_at.desc(), DistrictNews.created_at.desc())
    stmt = stmt.offset(offset).limit(limit)
    items = [to_out(r) for r in db.execute(stmt).scalars().all()]
    return NewsPageOut(items=items, total=total, limit=limit, offset=offset)


@router.get("/{news_id}", response_model=NewsOut)
def get_news(
    news_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    item = db.execute(
        select(DistrictNews).options(selectinload(DistrictNews.settlement)).where(DistrictNews.id == news_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Новость не найдена")
    if not item.is_published and not _staff(user):
        raise HTTPException(status_code=404, detail="Новость не найдена")
    return to_out(item)


@router.post("", response_model=NewsOut)
def create_news(
    payload: NewsCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    data = payload.model_dump()
    if data.get("is_published") and not data.get("published_at"):
        data["published_at"] = datetime.now(timezone.utc)
    item = DistrictNews(**data, created_by_id=user.id)
    db.add(item)
    db.flush()
    log_action(db, actor=user, action="news.create", entity_type="news", entity_id=item.id, details=item.title)
    db.commit()
    item = db.execute(
        select(DistrictNews).options(selectinload(DistrictNews.settlement)).where(DistrictNews.id == item.id)
    ).scalar_one()
    return to_out(item)


@router.patch("/{news_id}", response_model=NewsOut)
def update_news(
    news_id: int,
    payload: NewsUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(
        select(DistrictNews).options(selectinload(DistrictNews.settlement)).where(DistrictNews.id == news_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Новость не найдена")
    data = payload.model_dump(exclude_unset=True)
    if data.get("is_published") is True and not item.published_at and "published_at" not in data:
        data["published_at"] = datetime.now(timezone.utc)
    for key, value in data.items():
        setattr(item, key, value)
    log_action(db, actor=user, action="news.update", entity_type="news", entity_id=item.id, details=item.title)
    db.commit()
    item = db.execute(
        select(DistrictNews).options(selectinload(DistrictNews.settlement)).where(DistrictNews.id == news_id)
    ).scalar_one()
    return to_out(item)


@router.post("/{news_id}/cover", response_model=NewsOut)
async def upload_news_cover(
    news_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(
        select(DistrictNews).options(selectinload(DistrictNews.settlement)).where(DistrictNews.id == news_id)
    ).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Новость не найдена")
    ctype = (file.content_type or "").lower()
    if ctype not in ALLOWED:
        raise HTTPException(status_code=400, detail="Допустимы JPEG, PNG, WebP")
    data = await file.read()
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=400, detail="Файл слишком большой (макс. 6 МБ)")
    UPLOAD_ROOT.mkdir(parents=True, exist_ok=True)
    name = f"{news_id}_{uuid.uuid4().hex}{ALLOWED[ctype]}"
    rel = f"news/{name}"
    (UPLOAD_ROOT / name).write_bytes(data)
    item.cover_path = rel
    log_action(db, actor=user, action="news.cover", entity_type="news", entity_id=item.id, details=name)
    db.commit()
    item = db.execute(
        select(DistrictNews).options(selectinload(DistrictNews.settlement)).where(DistrictNews.id == news_id)
    ).scalar_one()
    return to_out(item)


@router.delete("/{news_id}")
def delete_news(
    news_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.editor, UserRole.admin)),
):
    item = db.execute(select(DistrictNews).where(DistrictNews.id == news_id)).scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Новость не найдена")
    log_action(db, actor=user, action="news.delete", entity_type="news", entity_id=item.id, details=item.title)
    db.delete(item)
    db.commit()
    return {"ok": True}
