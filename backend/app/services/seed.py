from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import Base, engine
from app.core.security import hash_password
from app.core.seed_data import LEGAL_DOCS, SETTLEMENTS
from app.models import LegalDocument, Settlement, User, UserRole


def init_db() -> None:
    Path("data").mkdir(exist_ok=True)
    Base.metadata.create_all(bind=engine)


def seed_db(session: Session) -> None:
    existing = session.execute(select(Settlement).limit(1)).scalar_one_or_none()
    if existing is None:
        for name, stype, council, display, is_district, sort_order in SETTLEMENTS:
            session.add(
                Settlement(
                    name=name,
                    settlement_type=stype,
                    council=council,
                    display_name=display,
                    is_district=is_district,
                    sort_order=sort_order,
                )
            )
        session.flush()

    for doc in LEGAL_DOCS:
        found = session.execute(select(LegalDocument).where(LegalDocument.slug == doc["slug"])).scalar_one_or_none()
        if found is None:
            session.add(LegalDocument(**doc))

    admin = session.execute(select(User).where(User.email == settings.admin_email)).scalar_one_or_none()
    if admin is None:
        settlement = session.execute(
            select(Settlement).where(Settlement.display_name == "село Сакмара")
        ).scalar_one()
        session.add(
            User(
                email=settings.admin_email,
                password_hash=hash_password(settings.admin_password),
                full_name=settings.admin_name,
                settlement_id=settlement.id,
                role=UserRole.admin,
                accepted_terms=True,
            )
        )

    session.commit()
