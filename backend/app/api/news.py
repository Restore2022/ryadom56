from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_optional_user, require_roles
from app.core.database import get_db
from app.models import DistrictNews, User, UserRole
from app.schemas import NewsCreate, NewsOut, NewsUpdate
from app.services.audit import log_action

router = APIRouter(prefix="/news", tags=["news"])


def to_out(item: DistrictNews) -> NewsOut:
    return NewsOut(
        id=item.id,
        title=item.title,
        body=item.body,
        settlement_id=item.settlement_id,
        settlement_name=item.settlement.display_name if item.settlement else None,
        is_published=item.is_published,
        published_at=item.published_at,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _staff(user: User | None) -> bool:
    return bool(user and user.role in (UserRole.admin, UserRole.editor))


@router.get("", response_model=list[NewsOut])
def list_news(
    settlement_id: int | None = None,
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
    stmt = stmt.order_by(DistrictNews.created_at.desc())
    return [to_out(r) for r in db.execute(stmt).scalars().all()]


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
