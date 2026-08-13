import re

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import BlacklistEntry

_CHAT_SPAM_RE = re.compile(
    r"(https?://|t\.me/|whatsapp|телег|казино|ставк|крипт|заработ|подписыва)",
    re.IGNORECASE,
)


def looks_like_chat_spam(body: str) -> bool:
    return bool(body and _CHAT_SPAM_RE.search(body))


def normalize_phone(value: str | None) -> str:
    if not value:
        return ""
    digits = re.sub(r"\D+", "", value)
    if digits.startswith("8") and len(digits) == 11:
        digits = "7" + digits[1:]
    return digits


def normalize_word(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


def match_blacklist(
    db: Session,
    *,
    title: str = "",
    description: str = "",
    phone: str | None = None,
) -> list[str]:
    rows = db.execute(select(BlacklistEntry)).scalars().all()
    if not rows:
        return []
    text = f"{title}\n{description}".lower()
    phone_norm = normalize_phone(phone)
    hits: list[str] = []
    for row in rows:
        if row.kind == "phone":
            target = normalize_phone(row.value)
            if target and phone_norm and (target in phone_norm or phone_norm in target):
                hits.append(f"телефон: {row.value}")
        elif row.kind == "word":
            word = normalize_word(row.value)
            if word and word in text:
                hits.append(f"слово: {row.value}")
    return hits
