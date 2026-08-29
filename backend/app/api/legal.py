from datetime import datetime
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

LEGAL_PAGE = """<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>__TITLE__ — Рядом56</title>
  <link rel="canonical" href="https://legac.ru/legal/__SLUG__">
  <meta name="theme-color" content="#102016">
  <link rel="icon" type="image/svg+xml" href="/favicon.svg">
  <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">
  <link rel="apple-touch-icon" href="/icon-512.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Unbounded:wght@500;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/styles.css?v=25">
</head>
<body class="legal-page">
  <a class="skip" href="#main">К содержимому</a>
  <header class="top">
    <div class="wrap top-inner">
      <a class="brand" href="/" aria-label="Рядом56 — на главную">
        <span class="brand-mark" aria-hidden="true">
          <img src="/favicon.svg" width="28" height="28" alt="">
        </span>
        <span>Рядом56</span>
      </a>
      <nav class="nav" aria-label="Разделы">
        <a href="/">На главную</a>
        <a href="/#feed">Объявления</a>
        <a href="/#contacts">Контакты</a>
      </nav>
      <a class="btn btn-solid top-cta" href="/#download">Скачать</a>
    </div>
  </header>
  <main id="main">
    <article class="wrap legal-doc">
      <p class="eyebrow">Официальный сайт · legac.ru</p>
      <h1>__TITLE__</h1>
      __UPDATED__
      <div class="legal-body">__BODY__</div>
      <a class="legal-back" href="/">← На главную</a>
    </article>
  </main>
  <footer class="foot">
    <div class="wrap foot-inner">
      <div>
        <p class="brand foot-brand">Рядом56</p>
        <p>Локальный сервис для Сакмарского района и Оренбурга.</p>
      </div>
      <div class="foot-links">
        <a href="/legal/terms">Соглашение</a>
        <a href="/legal/privacy">Конфиденциальность</a>
        <a href="/legal/listing_rules">Правила объявлений</a>
      </div>
    </div>
    <div class="wrap">
        <p class="copy">__YEAR__ · Рядом56 · Андроид (Android)</p>
        <p class="copy-legal">Оператор персональных данных — физическое лицо. ИНН организации не присвоен. ОГРН не присвоен. Почта info@legac.ru, телефон +7 908 321-18-01.</p>
    </div>
  </footer>
</body>
</html>"""


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
        page = (
            LEGAL_PAGE.replace("__TITLE__", "Страница не найдена")
            .replace("__SLUG__", html_lib.escape(slug))
            .replace("__BODY__", "<p>Такого документа нет. Вернитесь на главную или откройте ссылку из подвала сайта.</p>")
            .replace("__UPDATED__", "")
            .replace("__YEAR__", str(datetime.now().year))
        )
        return HTMLResponse(page, status_code=404)
    body = html_lib.escape(doc.body).replace("\n\n", "</p><p>").replace("\n", "<br>")
    title = html_lib.escape(doc.title)
    slug_safe = html_lib.escape(doc.slug)
    updated = ""
    if doc.updated_at:
        updated = f'<p class="legal-updated">Обновлено {html_lib.escape(doc.updated_at.strftime("%d.%m.%Y"))}</p>'
    page = (
        LEGAL_PAGE.replace("__TITLE__", title)
        .replace("__SLUG__", slug_safe)
        .replace("__BODY__", f"<p>{body}</p>")
        .replace("__UPDATED__", updated)
        .replace("__YEAR__", str(datetime.now().year))
    )
    return page


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
