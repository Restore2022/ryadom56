import hashlib
import logging
import re
import time

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from app.api.auth import client_ip
from app.core.config import settings
from app.core.database import get_db
from app.models import SiteContact
from app.schemas import MessageOut
from app.services.mail import MailNotConfigured, MailSendError, mail_configured, send_email
from app.services.rate_limit import limiter

router = APIRouter(prefix="/contact", tags=["contact"])
log = logging.getLogger(__name__)

URL_RE = re.compile(r"(https?://|www\.)", re.I)
OK = "Отправили. Ответим по телефону, если указали."


class SiteContactIn(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    settlement: str = Field(default="", max_length=120)
    phone: str = Field(default="", max_length=32)
    message: str = Field(min_length=8, max_length=2000)
    website: str = Field(default="", max_length=120)
    shown: int = Field(default=0)
    consent: bool = False

    @field_validator("name", "settlement", "phone", "message", "website")
    @classmethod
    def strip_text(cls, value: str) -> str:
        return " ".join(str(value or "").split())


def _silent_ok() -> MessageOut:
    return MessageOut(message=OK)


def _looks_like_bot(payload: SiteContactIn) -> bool:
    if payload.website:
        return True
    if payload.shown <= 0:
        return True
    if URL_RE.search(payload.name or "") or URL_RE.search(payload.phone or ""):
        return True
    return False


@router.post("", response_model=MessageOut)
def site_contact(payload: SiteContactIn, request: Request, db: Session = Depends(get_db)):
    ip = client_ip(request) or "unknown"
    if _looks_like_bot(payload):
        return _silent_ok()
    now = int(time.time())
    elapsed = now - int(payload.shown or 0)
    if elapsed < 3:
        raise HTTPException(status_code=400, detail="Подождите пару секунд и отправьте ещё раз.")
    if elapsed > 172800:
        raise HTTPException(status_code=400, detail="Страница устарела. Обновите её и отправьте ещё раз.")
    if not payload.consent:
        raise HTTPException(status_code=400, detail="Отметьте согласие на обработку персональных данных.")
    digits = re.sub(r"\D", "", payload.phone or "")
    if payload.phone and len(digits) < 10:
        raise HTTPException(status_code=400, detail="Проверьте телефон или оставьте поле пустым.")
    if len(URL_RE.findall(payload.message or "")) > 1:
        raise HTTPException(status_code=400, detail="Напишите без ссылок или позвоните.")
    digest = hashlib.sha256(
        f"{ip}|{payload.name.lower()}|{digits}|{payload.message.lower()}".encode("utf-8")
    ).hexdigest()[:24]
    if not limiter.allow(f"site-contact-dup:{digest}", limit=1, window_sec=86400):
        return MessageOut(message="Это уже отправили. Ответим по телефону, если указали.")
    if not limiter.allow(f"site-contact:{ip}", limit=3, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много писем подряд. Подождите час или позвоните.")
    if not limiter.allow(f"site-contact-fast:{ip}", limit=1, window_sec=120):
        raise HTTPException(status_code=429, detail="Подождите пару минут и отправьте ещё раз.")

    row = SiteContact(
        name=payload.name,
        settlement=payload.settlement or None,
        phone=payload.phone or None,
        message=payload.message,
        ip=ip,
        status="new",
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    place = payload.settlement or "село не указано"
    phone = payload.phone or "не указан"
    subject = f"Сайт: {payload.name} · {place} · #{row.id}"
    text = (
        f"Письмо с формы на legac.ru #{row.id}\n\n"
        f"Имя: {payload.name}\n"
        f"Село: {place}\n"
        f"Телефон: {phone}\n"
        f"IP: {ip}\n\n"
        f"Вопрос:\n{payload.message}\n"
    )
    to = (settings.smtp_from or settings.smtp_user).strip()
    if mail_configured() and to:
        try:
            send_email(to=to, subject=subject, text=text)
        except (MailNotConfigured, MailSendError) as exc:
            log.warning("site contact mail failed id=%s: %s", row.id, exc)
    return MessageOut(message=f"{OK} Номер обращения: {row.id}.")
