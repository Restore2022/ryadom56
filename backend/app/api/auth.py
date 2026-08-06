from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.security import create_access_token, hash_password, verify_password
from app.models import User
from app.schemas import LoginIn, RegisterIn, TokenOut, UserOut

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenOut)
def register(payload: RegisterIn, db: Session = Depends(get_db)):
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
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token(str(user.id), {"role": user.role.value})
    return TokenOut(access_token=token)


@router.post("/login", response_model=TokenOut)
def login(payload: LoginIn, db: Session = Depends(get_db)):
    user = db.execute(select(User).where(User.email == payload.email.lower())).scalar_one_or_none()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Неверный email или пароль")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Аккаунт заблокирован")
    token = create_access_token(str(user.id), {"role": user.role.value})
    return TokenOut(access_token=token)


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return user
