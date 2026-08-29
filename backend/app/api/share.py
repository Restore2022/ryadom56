import html as html_lib

from fastapi import APIRouter, Depends
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.core.database import get_db
from app.models import Listing, ListingStatus

router = APIRouter(tags=["share"])

PAGE = """<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>__TITLE__ — Рядом56</title>
  <link rel="canonical" href="https://legac.ru/l/__ID__">
  <meta property="og:type" content="website">
  <meta property="og:locale" content="ru_RU">
  <meta property="og:url" content="https://legac.ru/l/__ID__">
  <meta property="og:title" content="__TITLE__">
  <meta property="og:description" content="__DESC__">
  <meta property="og:image" content="__IMAGE__">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="__TITLE__">
  <meta name="twitter:description" content="__DESC__">
  <meta name="twitter:image" content="__IMAGE__">
  <meta http-equiv="refresh" content="0;url=https://legac.ru/#l=__ID__">
</head>
<body>
  <p><a href="https://legac.ru/#l=__ID__">Открыть объявление на сайте Рядом56</a></p>
</body>
</html>
"""

MISSING = """<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Объявление не найдено — Рядом56</title>
  <link rel="canonical" href="https://legac.ru/">
  <meta property="og:title" content="Рядом56">
  <meta property="og:description" content="Объявление не найдено или уже снято.">
  <meta property="og:image" content="https://legac.ru/og.jpg">
  <meta name="robots" content="noindex">
</head>
<body>
  <p>Объявление не найдено или уже снято. <a href="https://legac.ru/">На главную</a></p>
</body>
</html>
"""


def _page(listing_id: int, title: str, desc: str, image: str) -> str:
    return (
        PAGE.replace("__ID__", str(listing_id))
        .replace("__TITLE__", html_lib.escape(title, quote=True))
        .replace("__DESC__", html_lib.escape(desc, quote=True))
        .replace("__IMAGE__", html_lib.escape(image, quote=True))
    )


@router.get("/l/{listing_id}", response_class=HTMLResponse)
def listing_share(listing_id: int, db: Session = Depends(get_db)):
    item = db.execute(
        select(Listing)
        .options(selectinload(Listing.images), selectinload(Listing.settlement))
        .where(Listing.id == listing_id)
    ).scalar_one_or_none()
    if not item or item.status != ListingStatus.approved:
        return HTMLResponse(MISSING.replace("__ID__", str(listing_id)), status_code=404)
    title = (item.title or "Объявление").strip()[:80]
    body = " ".join((item.description or "").split())[:180] or "Объявление в Сакмарском районе — Рядом56"
    image = "https://legac.ru/og.jpg"
    photos = sorted(item.images or [], key=lambda x: x.sort_order)
    if photos:
        path = photos[0].path.replace("\\", "/")
        image = f"https://legac.ru/uploads/{path}"
    return HTMLResponse(_page(item.id, title, body, image))
