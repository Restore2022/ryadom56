from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user, require_roles
from app.api.listings import author_replied_to_buyer
from app.core.database import SessionLocal, get_db
from app.core.security import decode_access_token
from app.models import AppCall, Listing, ListingStatus, User, UserRole
from app.schemas import CallActionIn, CallCreateIn, CallOut, CallPageOut
from app.services.call_hub import hub
from app.services.notify import fcm_tokens_for_user, notify_user, push_user
from app.services.rate_limit import limiter
from app.services.sessions import assert_token_session

router = APIRouter(prefix="/calls", tags=["calls"])

RING_TIMEOUT_SEC = 40
OPEN_STATUSES = ("ringing", "active")


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _close(call: AppCall, status: str, *, reason: str | None = None) -> None:
    if call.status not in OPEN_STATUSES:
        return
    now = _utcnow()
    call.status = status
    call.ended_at = now
    call.end_reason = reason
    if call.answered_at:
        start = call.answered_at
        if start.tzinfo is None:
            start = start.replace(tzinfo=timezone.utc)
        call.duration_sec = max(0, int((now - start).total_seconds()))
    else:
        call.duration_sec = 0


def _expire_if_stale(call: AppCall) -> bool:
    if call.status != "ringing":
        return False
    created = call.created_at
    if created is None:
        return False
    if created.tzinfo is None:
        created = created.replace(tzinfo=timezone.utc)
    if _utcnow() - created <= timedelta(seconds=RING_TIMEOUT_SEC):
        return False
    _close(call, "missed", reason="timeout")
    return True


def _gsm_for(db: Session, listing: Listing, viewer: User, other: User) -> tuple[bool, str | None]:
    is_staff = viewer.role in (UserRole.admin, UserRole.moderator)
    if viewer.id == listing.author_id:
        phone = (other.phone or "").strip() or None
        return bool(phone), phone
    raw = (listing.contact_phone or (listing.author.phone if listing.author else None) or "").strip() or None
    if not raw:
        return False, None
    if is_staff or author_replied_to_buyer(db, listing, viewer):
        return True, raw
    return False, None


def to_call_out(db: Session, call: AppCall, viewer: User | None = None) -> CallOut:
    listing = call.listing
    caller = call.caller
    callee = call.callee
    gsm_ok, gsm_phone = (False, None)
    if viewer is not None and listing is not None:
        other = callee if viewer.id == call.caller_id else caller
        if other:
            gsm_ok, gsm_phone = _gsm_for(db, listing, viewer, other)
    return CallOut(
        id=call.id,
        listing_id=call.listing_id,
        listing_title=listing.title if listing else None,
        caller_id=call.caller_id,
        caller_name=caller.full_name if caller else None,
        callee_id=call.callee_id,
        callee_name=callee.full_name if callee else None,
        status=call.status,
        created_at=call.created_at,
        answered_at=call.answered_at,
        ended_at=call.ended_at,
        duration_sec=int(call.duration_sec or 0),
        end_reason=call.end_reason,
        callee_online=hub.is_online(call.callee_id),
        callee_has_push=bool(fcm_tokens_for_user(db, call.callee_id)),
        gsm_fallback=gsm_ok,
        gsm_phone=gsm_phone if gsm_ok else None,
        ring_timeout_sec=RING_TIMEOUT_SEC,
    )


def _payload(db: Session, call: AppCall, viewer: User | None, event: str) -> dict:
    out = to_call_out(db, call, viewer)
    return {"type": event, "call": out.model_dump(mode="json")}


def _load_call(db: Session, call_id: int) -> AppCall | None:
    return db.execute(
        select(AppCall)
        .options(
            selectinload(AppCall.listing).selectinload(Listing.author),
            selectinload(AppCall.caller),
            selectinload(AppCall.callee),
        )
        .where(AppCall.id == call_id)
    ).scalar_one_or_none()


def _busy(db: Session, user_id: int) -> AppCall | None:
    return db.execute(
        select(AppCall)
        .where(AppCall.status.in_(OPEN_STATUSES), or_(AppCall.caller_id == user_id, AppCall.callee_id == user_id))
        .order_by(AppCall.id.desc())
    ).scalars().first()


def _emit_both(db: Session, call: AppCall, event: str) -> None:
    hub.emit(call.caller_id, _payload(db, call, call.caller, event))
    hub.emit(call.callee_id, _payload(db, call, call.callee, event))


@router.post("", response_model=CallOut)
def create_call(
    payload: CallCreateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if not limiter.allow(f"call-hour:{user.id}", limit=20, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много звонков. Подождите")
    listing = db.execute(
        select(Listing).options(selectinload(Listing.author)).where(Listing.id == payload.listing_id)
    ).scalar_one_or_none()
    if not listing:
        raise HTTPException(status_code=404, detail="Объявление не найдено")
    if listing.status not in (ListingStatus.approved, ListingStatus.pending, ListingStatus.archived):
        raise HTTPException(status_code=400, detail="По этому объявлению нельзя звонить")

    if user.id == listing.author_id:
        if not payload.callee_id:
            raise HTTPException(status_code=400, detail="Укажите, кому звонить")
        callee_id = int(payload.callee_id)
        if callee_id == user.id:
            raise HTTPException(status_code=400, detail="Нельзя звонить самому себе")
    else:
        callee_id = listing.author_id
        if payload.callee_id and int(payload.callee_id) != callee_id:
            raise HTTPException(status_code=400, detail="Звонок только автору объявления")

    callee = db.get(User, callee_id)
    if not callee or not callee.is_active:
        raise HTTPException(status_code=404, detail="Собеседник недоступен")

    mine = _busy(db, user.id)
    if mine:
        if _expire_if_stale(mine):
            db.commit()
        else:
            raise HTTPException(status_code=409, detail="У вас уже идёт звонок")
    theirs = _busy(db, callee_id)
    if theirs:
        if _expire_if_stale(theirs):
            db.commit()
        else:
            raise HTTPException(status_code=409, detail="Абонент занят")

    call = AppCall(
        listing_id=listing.id,
        caller_id=user.id,
        callee_id=callee_id,
        status="ringing",
        created_at=_utcnow(),
    )
    db.add(call)
    db.commit()
    call = _load_call(db, call.id)
    assert call is not None
    out = to_call_out(db, call, user)
    hub.emit(callee_id, _payload(db, call, callee, "incoming"))
    push_user(
        db,
        user_id=callee_id,
        title="Входящий звонок",
        body=f"{user.full_name} звонит по объявлению «{listing.title}»",
        data={
            "type": "incoming_call",
            "call_id": str(call.id),
            "listing_id": str(listing.id),
            "caller_id": str(user.id),
            "caller_name": user.full_name,
        },
        channel_id="ryadom56_calls",
    )
    return out


@router.get("/pending", response_model=list[CallOut])
def pending_calls(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    rows = (
        db.execute(
            select(AppCall)
            .options(
                selectinload(AppCall.listing).selectinload(Listing.author),
                selectinload(AppCall.caller),
                selectinload(AppCall.callee),
            )
            .where(
                AppCall.status.in_(OPEN_STATUSES),
                or_(AppCall.caller_id == user.id, AppCall.callee_id == user.id),
            )
            .order_by(AppCall.id.desc())
        )
        .scalars()
        .all()
    )
    out: list[CallOut] = []
    changed = False
    for call in rows:
        if _expire_if_stale(call):
            changed = True
            _emit_both(db, call, "hangup")
            if call.status == "missed":
                notify_user(
                    db,
                    user_id=call.callee_id,
                    type="missed_call",
                    title="Пропущенный звонок",
                    body=f"{call.caller.full_name if call.caller else 'Пользователь'} звонил по объявлению",
                    listing_id=call.listing_id,
                    extra={"call_id": call.id, "caller_id": call.caller_id},
                )
            continue
        out.append(to_call_out(db, call, user))
    if changed:
        db.commit()
    return out


@router.get("/{call_id}", response_model=CallOut)
def get_call(call_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    call = _load_call(db, call_id)
    if not call or user.id not in (call.caller_id, call.callee_id):
        raise HTTPException(status_code=404, detail="Звонок не найден")
    if _expire_if_stale(call):
        db.commit()
        _emit_both(db, call, "hangup")
    return to_call_out(db, call, user)


@router.post("/{call_id}/accept", response_model=CallOut)
def accept_call(call_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    call = _load_call(db, call_id)
    if not call or user.id != call.callee_id:
        raise HTTPException(status_code=404, detail="Звонок не найден")
    if _expire_if_stale(call):
        db.commit()
        _emit_both(db, call, "hangup")
        raise HTTPException(status_code=410, detail="Звонок уже завершён")
    if call.status != "ringing":
        raise HTTPException(status_code=409, detail="Нельзя принять этот звонок")
    call.status = "active"
    call.answered_at = _utcnow()
    db.commit()
    call = _load_call(db, call_id)
    assert call is not None
    _emit_both(db, call, "accepted")
    return to_call_out(db, call, user)


@router.post("/{call_id}/decline", response_model=CallOut)
def decline_call(
    call_id: int,
    payload: CallActionIn | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    call = _load_call(db, call_id)
    if not call or user.id not in (call.caller_id, call.callee_id):
        raise HTTPException(status_code=404, detail="Звонок не найден")
    if call.status not in OPEN_STATUSES:
        return to_call_out(db, call, user)
    reason = (payload.reason if payload else None) or ("cancelled" if user.id == call.caller_id else "declined")
    status = "cancelled" if user.id == call.caller_id and call.status == "ringing" else "declined"
    if call.status == "active":
        status = "ended"
        reason = "hangup"
    _close(call, status, reason=reason)
    db.commit()
    call = _load_call(db, call_id)
    assert call is not None
    _emit_both(db, call, "hangup")
    return to_call_out(db, call, user)


@router.post("/{call_id}/hangup", response_model=CallOut)
def hangup_call(
    call_id: int,
    payload: CallActionIn | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    call = _load_call(db, call_id)
    if not call or user.id not in (call.caller_id, call.callee_id):
        raise HTTPException(status_code=404, detail="Звонок не найден")
    if call.status not in OPEN_STATUSES:
        return to_call_out(db, call, user)
    reason = (payload.reason if payload else None) or "hangup"
    if call.status == "ringing":
        status = "cancelled" if user.id == call.caller_id else "declined"
        if reason == "timeout":
            status = "missed"
            notify_user(
                db,
                user_id=call.callee_id,
                type="missed_call",
                title="Пропущенный звонок",
                body=f"{call.caller.full_name if call.caller else 'Пользователь'} звонил по объявлению",
                listing_id=call.listing_id,
                extra={"call_id": call.id, "caller_id": call.caller_id},
            )
        elif reason == "failed":
            status = "failed"
    else:
        status = "ended"
    _close(call, status, reason=reason)
    db.commit()
    call = _load_call(db, call_id)
    assert call is not None
    _emit_both(db, call, "hangup")
    return to_call_out(db, call, user)


@router.get("", response_model=CallPageOut, include_in_schema=False)
def list_my_calls_alias(
    limit: int = Query(default=30, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return _list_calls(db, user, limit, offset)


def _list_calls(db: Session, user: User, limit: int, offset: int) -> CallPageOut:
    flt = or_(AppCall.caller_id == user.id, AppCall.callee_id == user.id)
    total = int(db.execute(select(func.count(AppCall.id)).where(flt)).scalar_one())
    rows = (
        db.execute(
            select(AppCall)
            .options(
                selectinload(AppCall.listing).selectinload(Listing.author),
                selectinload(AppCall.caller),
                selectinload(AppCall.callee),
            )
            .where(flt)
            .order_by(AppCall.id.desc())
            .offset(offset)
            .limit(limit)
        )
        .scalars()
        .all()
    )
    return CallPageOut(
        items=[to_call_out(db, c, user) for c in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


def _ws_user(token: str | None, db: Session) -> User | None:
    if not token:
        return None
    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        return None
    user = db.execute(select(User).where(User.id == int(payload["sub"]))).scalar_one_or_none()
    if not user or not user.is_active:
        return None
    try:
        assert_token_session(db, user, payload)
    except HTTPException:
        return None
    return user


@router.websocket("/ws")
async def calls_ws(websocket: WebSocket, token: str | None = None):
    db = SessionLocal()
    user: User | None = None
    try:
        user = _ws_user(token, db)
        await websocket.accept()
        if not user:
            await websocket.close(code=4401)
            return
        await hub.connect(user.id, websocket)
        pending = (
            db.execute(
                select(AppCall)
                .options(
                    selectinload(AppCall.listing).selectinload(Listing.author),
                    selectinload(AppCall.caller),
                    selectinload(AppCall.callee),
                )
                .where(AppCall.status == "ringing", AppCall.callee_id == user.id)
                .order_by(AppCall.id.desc())
            )
            .scalars()
            .all()
        )
        for call in pending:
            if _expire_if_stale(call):
                db.commit()
                continue
            await hub.send(user.id, _payload(db, call, user, "incoming"))
        while True:
            raw = await websocket.receive_json()
            if not isinstance(raw, dict):
                continue
            kind = str(raw.get("type") or "")
            call_id = raw.get("call_id")
            if kind not in ("offer", "answer", "ice") or not call_id:
                continue
            call = db.get(AppCall, int(call_id))
            if not call or user.id not in (call.caller_id, call.callee_id):
                continue
            if call.status not in OPEN_STATUSES:
                continue
            peer_id = call.callee_id if user.id == call.caller_id else call.caller_id
            await hub.send(peer_id, {**raw, "from_id": user.id})
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        if user:
            await hub.disconnect(user.id, websocket)
        db.close()


admin_calls_router = APIRouter(prefix="/admin", tags=["admin-calls"])


@admin_calls_router.get("/calls", response_model=CallPageOut)
def admin_list_calls(
    q: str | None = None,
    status: str | None = None,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin, UserRole.moderator)),
):
    stmt = select(AppCall).options(
        selectinload(AppCall.listing).selectinload(Listing.author),
        selectinload(AppCall.caller),
        selectinload(AppCall.callee),
    )
    count_stmt = select(func.count(AppCall.id))
    if status and status.strip():
        stmt = stmt.where(AppCall.status == status.strip())
        count_stmt = count_stmt.where(AppCall.status == status.strip())
    total = int(db.execute(count_stmt).scalar_one())
    rows = db.execute(stmt.order_by(AppCall.id.desc()).limit(800 if q else offset + limit)).scalars().unique().all()
    if q and q.strip():
        needle = q.strip().lower()
        rows = [
            c
            for c in rows
            if needle in (c.caller.full_name if c.caller else "").lower()
            or needle in (c.callee.full_name if c.callee else "").lower()
            or needle in (c.listing.title if c.listing else "").lower()
            or needle in str(c.id)
        ]
        total = len(rows)
        rows = rows[offset : offset + limit]
    elif offset:
        rows = rows[offset : offset + limit]
    else:
        rows = rows[:limit]
    return CallPageOut(items=[to_call_out(db, c, user) for c in rows], total=total, limit=limit, offset=offset)
