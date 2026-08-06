from pathlib import Path

from sqlalchemy import inspect, select, text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import Base, engine
from app.core.security import hash_password
from app.core.seed_data import LEGAL_DOCS, SETTLEMENTS
from app.models import LegalDocument, Settlement, User, UserRole

USER_COLUMNS = {
    "last_ip": "VARCHAR(64)",
    "device_brand": "VARCHAR(80)",
    "device_model": "VARCHAR(120)",
    "device_os": "VARCHAR(80)",
    "app_version": "VARCHAR(40)",
    "device_info": "TEXT",
    "last_seen_at": "DATETIME",
}


def init_db() -> None:
    Path("data").mkdir(exist_ok=True)
    Base.metadata.create_all(bind=engine)
    _migrate_user_columns()


def _migrate_user_columns() -> None:
    inspector = inspect(engine)
    if "users" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("users")}
    with engine.begin() as conn:
        for name, sql_type in USER_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE users ADD COLUMN {name} {sql_type}"))


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
        elif found.version != doc["version"]:
            found.title = doc["title"]
            found.version = doc["version"]
            found.body = doc["body"]

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
