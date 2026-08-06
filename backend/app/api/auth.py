from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.security import create_access_token, hash_password, verify_password
from app.models import User
from app.schemas import DeviceInfoIn, LoginIn, RegisterIn, TokenOut, UserOut

router = APIRouter(prefix="/auth", tags=["auth"])


def client_ip(request: Request) -> str | None:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()[:64]
    if request.client:
        return (request.client.host or "")[:64] or None
    return None


def touch_user(user: User, request: Request, device: DeviceInfoIn | None = None) -> None:
    user.last_ip = client_ip(request)
    user.last_seen_at = datetime.now(timezone.utc)
    if device:
        if device.device_brand is not None:
            user.device_brand = device.device_brand.strip() or None
        if device.device_model is not None:
            user.device_model = device.device_model.strip() or None
        if device.device_os is not None:
            user.device_os = device.device_os.strip() or None
        if device.app_version is not None:
            user.app_version = device.app_version.strip() or None
        if device.device_info is not None:
            user.device_info = device.device_info.strip() or None


@router.post("/register", response_model=TokenOut)
def register(payload: RegisterIn, request: Request, db: Session = Depends(get_db)):
    if not (payload.accepted_terms and payload.accepted_privacy and payload.accepted_listing_rules):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Нужно принять пользовательское соглашение, политику и правила объявлений",
        )
    exists = db.execute(select(User).where(User.email == payload.email.lower())).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=400, detail="Email уже зарегистрирован")

    user = User(
        email=payload.email.lower(),
        password_hash=hash_password(payload.password),
        full_name=payload.full_name.strip(),
        phone=payload.phone.strip() if payload.phone else None,
        settlement_id=payload.settlement_id,
        accepted_terms=True,
    )
    touch_user(user, request)
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token(str(user.id), {"role": user.role.value})
    return TokenOut(access_token=token)


@router.post("/login", response_model=TokenOut)
def login(payload: LoginIn, request: Request, db: Session = Depends(get_db)):
    user = db.execute(select(User).where(User.email == payload.email.lower())).scalar_one_or_none()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Неверный email или пароль")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Аккаунт заблокирован")
    touch_user(user, request)
    db.commit()
    token = create_access_token(str(user.id), {"role": user.role.value})
    return TokenOut(access_token=token)


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return user


@router.post("/device", response_model=UserOut)
def report_device(
    payload: DeviceInfoIn,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    touch_user(db_user, request, payload)
    db.commit()
    db.refresh(db_user)
    return db_user
