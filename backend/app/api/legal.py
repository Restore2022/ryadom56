from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import require_roles
from app.core.database import get_db
from app.models import LegalDocument, User, UserRole
from app.schemas import LegalOut, LegalUpdate
from app.services.audit import log_action

router = APIRouter(prefix="/legal", tags=["legal"])


@router.get("", response_model=list[LegalOut])
def list_legal(db: Session = Depends(get_db)):
    return db.execute(select(LegalDocument).order_by(LegalDocument.slug)).scalars().all()


@router.get("/{slug}", response_model=LegalOut)
def get_legal(slug: str, db: Session = Depends(get_db)):
    doc = db.execute(select(LegalDocument).where(LegalDocument.slug == slug)).scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Документ не найден")
    return doc


@router.patch("/{slug}", response_model=LegalOut)
def update_legal(
    slug: str,
    payload: LegalUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    doc = db.execute(select(LegalDocument).where(LegalDocument.slug == slug)).scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Документ не найден")
    data = payload.model_dump(exclude_unset=True)
    for key, value in data.items():
        setattr(doc, key, value)
    log_action(db, actor=user, action="legal.update", entity_type="legal", entity_id=doc.id, details=slug)
    db.commit()
    db.refresh(doc)
    return doc
