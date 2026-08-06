from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import LegalDocument
from app.schemas import LegalOut

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
