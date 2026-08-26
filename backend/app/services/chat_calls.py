"""Системные сообщения о звонках внутри чата объявления."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import AppCall, Listing, ListingMessage

TERMINAL_CALL_STATUSES = ("ended", "missed", "declined", "cancelled", "failed", "busy")


def format_call_duration(sec: int | None) -> str:
    total = max(0, int(sec or 0))
    minutes, seconds = divmod(total, 60)
    if minutes >= 60:
        hours, minutes = divmod(minutes, 60)
        return f"{hours}:{minutes:02d}:{seconds:02d}"
    return f"{minutes}:{seconds:02d}"


def ended_by_name(call: AppCall) -> str | None:
    eid = getattr(call, "ended_by_id", None)
    if not eid:
        return None
    if call.caller is not None and call.caller_id == eid:
        return call.caller.full_name
    if call.callee is not None and call.callee_id == eid:
        return call.callee.full_name
    return None


def call_event_body(status: str, duration_sec: int | None = 0, *, ended_by: str | None = None) -> str:
    st = (status or "").strip()
    name = (ended_by or "").strip()
    if st == "missed":
        return "Пропущенный звонок"
    if st == "declined":
        return f"{name} отклонил звонок" if name else "Звонок отклонён"
    if st == "cancelled":
        return f"{name} отменил звонок" if name else "Звонок отменён"
    if st == "failed":
        return "Звонок не состоялся"
    if st == "busy":
        return "Абонент занят"
    if st == "ended":
        dur = format_call_duration(duration_sec)
        if name:
            return f"{name} завершил звонок · {dur}"
        return f"Звонок · {dur}"
    return "Звонок"


def thread_buyer_id(call: AppCall, listing: Listing | None = None) -> int | None:
    author_id = listing.author_id if listing is not None else None
    if author_id is None:
        return None
    if call.caller_id != author_id:
        return call.caller_id
    if call.callee_id != author_id:
        return call.callee_id
    return None


def record_call_in_chat(
    db: Session, call: AppCall, *, mark_read: bool | None = None
) -> ListingMessage | None:
    """Пишет в тред одно сообщение на завершённый звонок. Повторно не дублирует."""
    if call.status not in TERMINAL_CALL_STATUSES:
        return None
    existing = db.execute(
        select(ListingMessage).where(ListingMessage.call_id == call.id)
    ).scalar_one_or_none()
    who = ended_by_name(call)
    if existing:
        existing.body = call_event_body(call.status, call.duration_sec, ended_by=who)
        existing.kind = "call"
        if mark_read is True:
            existing.is_read = True
        return existing

    listing = db.get(Listing, call.listing_id)
    if listing is None:
        return None
    buyer_id = thread_buyer_id(call, listing)
    if buyer_id is None:
        return None

    sender_id = call.callee_id if call.status == "declined" else call.caller_id
    read = True if mark_read is True else (call.status == "ended" if mark_read is None else bool(mark_read))
    msg = ListingMessage(
        listing_id=call.listing_id,
        sender_id=sender_id,
        buyer_id=buyer_id,
        body=call_event_body(call.status, call.duration_sec, ended_by=who),
        kind="call",
        call_id=call.id,
        is_read=read,
    )
    db.add(msg)
    db.flush()
    return msg
