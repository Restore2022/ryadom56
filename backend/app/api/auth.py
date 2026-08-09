from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.security import create_access_token, hash_password, verify_password
from app.models import Listing, ListingReport, ListingStatus, Settlement, User
from app.schemas import DeviceInfoIn, LoginIn, ProfileUpdateIn, PublicUserOut, RegisterIn, TokenOut, UserOut
from app.services.rate_limit import limiter

router = APIRouter(prefix="/auth", tags=["auth"])


def enrich_user_out(db: Session, user: User) -> UserOut:
    listings_count = int(
        db.execute(
            select(func.count(Listing.id)).where(
                Listing.author_id == user.id,
                Listing.status == ListingStatus.approved,
            )
        ).scalar_one()
    )
    reports_against = int(
        db.execute(
            select(func.count(ListingReport.id))
            .join(Listing, Listing.id == ListingReport.listing_id)
            .where(
                Listing.author_id == user.id,
                ListingReport.status.in_(["open", "reviewed"]),
            )
        ).scalar_one()
    )
    data = UserOut.model_validate(user)
    data.listings_count = listings_count
    data.reports_against = reports_against
    return data


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
        if device.fcm_token is not None:
            user.fcm_token = device.fcm_token.strip() or None


@router.post("/register", response_model=TokenOut)
def register(payload: RegisterIn, request: Request, db: Session = Depends(get_db)):
    ip = client_ip(request) or "unknown"
    if not limiter.allow(f"register:{ip}", limit=8, window_sec=3600):
        raise HTTPException(status_code=429, detail="Слишком много регистраций с этого адреса. Попробуйте позже")
    if not (payload.accepted_terms and payload.accepted_privacy and payload.accepted_listing_rules):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Нужно принять пользовательское соглашение, политику и правила объявлений",
        )
    exists = db.execute(select(User).where(User.email == payload.email.lower())).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=400, detail="Email уже зарегистрирован")
    settlement = db.execute(select(Settlement).where(Settlement.id == payload.settlement_id)).scalar_one_or_none()
    if not settlement:
        raise HTTPException(status_code=400, detail="Населённый пункт не найден")

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
    ip = client_ip(request) or "unknown"
    if not limiter.allow(f"login:{ip}", limit=40, window_sec=600):
        raise HTTPException(status_code=429, detail="Слишком много попыток входа. Подождите")
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
def me(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    return enrich_user_out(db, db_user)


@router.get("/users/{user_id}/public", response_model=PublicUserOut)
def public_profile(user_id: int, db: Session = Depends(get_db)):
    u = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user_id)
    ).scalar_one_or_none()
    if not u or not u.is_active:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    listings_count = int(
        db.execute(
            select(func.count(Listing.id)).where(
                Listing.author_id == u.id,
                Listing.status == ListingStatus.approved,
            )
        ).scalar_one()
    )
    reports_against = int(
        db.execute(
            select(func.count(ListingReport.id))
            .join(Listing, Listing.id == ListingReport.listing_id)
            .where(
                Listing.author_id == u.id,
                ListingReport.status.in_(["open", "reviewed"]),
            )
        ).scalar_one()
    )
    return PublicUserOut(
        id=u.id,
        full_name=u.full_name,
        settlement_name=u.settlement.display_name if u.settlement else None,
        badge=u.badge,
        rating_score=u.rating_score,
        listings_count=listings_count,
        reports_against=reports_against,
        member_since=u.created_at,
        is_active=u.is_active,
    )


@router.patch("/me", response_model=UserOut)
def update_me(
    payload: ProfileUpdateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    data = payload.model_dump(exclude_unset=True)
    if "password" in data and data["password"]:
        if not payload.current_password or not verify_password(payload.current_password, db_user.password_hash):
            raise HTTPException(status_code=400, detail="Неверный текущий пароль")
        db_user.password_hash = hash_password(data.pop("password"))
    data.pop("current_password", None)
    if "settlement_id" in data and data["settlement_id"] is not None:
        settlement = db.execute(select(Settlement).where(Settlement.id == data["settlement_id"])).scalar_one_or_none()
        if not settlement:
            raise HTTPException(status_code=400, detail="Населённый пункт не найден")
    if "full_name" in data and data["full_name"]:
        db_user.full_name = data["full_name"].strip()
    if "phone" in data:
        phone = data["phone"]
        db_user.phone = phone.strip() if phone else None
    if "settlement_id" in data and data["settlement_id"] is not None:
        db_user.settlement_id = data["settlement_id"]
    db.commit()
    db_user = db.execute(
        select(User).options(selectinload(User.settlement)).where(User.id == user.id)
    ).scalar_one()
    return db_user


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
