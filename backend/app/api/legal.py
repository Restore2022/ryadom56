from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.orm import Session
import html as html_lib

from app.api.deps import require_roles
from app.core.database import get_db
from app.models import LegalDocument, User, UserRole
from app.schemas import LegalOut, LegalUpdate
from app.services.audit import log_action

router = APIRouter(prefix="/legal", tags=["legal"])
public_router = APIRouter(tags=["legal-html"])


@router.get("", response_model=list[LegalOut])
def list_legal(db: Session = Depends(get_db)):
    return db.execute(select(LegalDocument).order_by(LegalDocument.slug)).scalars().all()


@router.get("/{slug}", response_model=LegalOut)
def get_legal(slug: str, db: Session = Depends(get_db)):
    doc = db.execute(select(LegalDocument).where(LegalDocument.slug == slug)).scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Документ не найден")
    return doc


@public_router.get("/legal/{slug}", response_class=HTMLResponse)
def legal_html(slug: str, db: Session = Depends(get_db)):
    doc = db.execute(select(LegalDocument).where(LegalDocument.slug == slug)).scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Документ не найден")
    body = html_lib.escape(doc.body).replace("\n\n", "</p><p>").replace("\n", "<br>")
    title = html_lib.escape(doc.title)
    return f"""<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title} — Рядом56</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 720px; margin: 24px auto; padding: 0 16px; line-height: 1.5; color: #1c2b1f; }}
    h1 {{ font-size: 1.6rem; }}
    p {{ margin: 0 0 12px; }}
  </style>
</head>
<body>
  <h1>{title}</h1>
  <p>{body}</p>
</body>
</html>"""


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
