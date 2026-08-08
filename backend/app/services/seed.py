from datetime import datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import inspect, select, text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import Base, engine
from app.core.security import hash_password
from app.core.seed_data import LEGAL_DOCS, SETTLEMENTS
from app.models import Event, LegalDocument, Settlement, TransportRoute, User, UserRole

USER_COLUMNS = {
    "last_ip": "VARCHAR(64)",
    "device_brand": "VARCHAR(80)",
    "device_model": "VARCHAR(120)",
    "device_os": "VARCHAR(80)",
    "app_version": "VARCHAR(40)",
    "device_info": "TEXT",
    "last_seen_at": "DATETIME",
    "fcm_token": "VARCHAR(255)",
}

LISTING_COLUMNS = {
    "close_reason": "VARCHAR(40)",
    "close_note": "TEXT",
    "is_urgent": "BOOLEAN DEFAULT 0",
    "is_pinned": "BOOLEAN DEFAULT 0",
    "auto_flagged": "BOOLEAN DEFAULT 0",
    "previous_snapshot": "TEXT",
}

REPORT_COLUMNS = {
    "moderator_reply": "TEXT",
}

DIRECTORY_COLUMNS = {
    "hours": "VARCHAR(255)",
}


def init_db() -> None:
    Path("data").mkdir(exist_ok=True)
    Path("data/uploads").mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)
    _migrate_user_columns()
    _migrate_listing_columns()
    _migrate_directory_columns()
    _migrate_report_columns()


def _migrate_user_columns() -> None:
    inspector = inspect(engine)
    if "users" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("users")}
    with engine.begin() as conn:
        for name, sql_type in USER_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE users ADD COLUMN {name} {sql_type}"))


def _migrate_listing_columns() -> None:
    inspector = inspect(engine)
    if "listings" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("listings")}
    with engine.begin() as conn:
        for name, sql_type in LISTING_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE listings ADD COLUMN {name} {sql_type}"))


def _migrate_directory_columns() -> None:
    inspector = inspect(engine)
    if "directory_items" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("directory_items")}
    with engine.begin() as conn:
        for name, sql_type in DIRECTORY_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE directory_items ADD COLUMN {name} {sql_type}"))


def _migrate_report_columns() -> None:
    inspector = inspect(engine)
    if "listing_reports" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("listing_reports")}
    with engine.begin() as conn:
        for name, sql_type in REPORT_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE listing_reports ADD COLUMN {name} {sql_type}"))


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

    _seed_events(session)
    _seed_transport(session)

    session.commit()


def _settlement_id(session: Session, display_name: str) -> int | None:
    row = session.execute(select(Settlement).where(Settlement.display_name == display_name)).scalar_one_or_none()
    return row.id if row else None


def _seed_events(session: Session) -> None:
    if session.execute(select(Event).limit(1)).scalar_one_or_none() is not None:
        return
    sakmara = _settlement_id(session, "село Сакмара")
    orenburg = _settlement_id(session, "город Оренбург")
    now = datetime.now(timezone.utc)
    samples = [
        Event(
            title="Ярмарка выходного дня",
            description="Местные продукты, мёд, овощи и рукоделие. Приглашаем жителей района.",
            starts_at=now + timedelta(days=3, hours=9),
            ends_at=now + timedelta(days=3, hours=14),
            place_text="Площадь у Дома культуры",
            settlement_id=sakmara,
            address="село Сакмара",
            is_published=True,
        ),
        Event(
            title="Концерт ко Дню района",
            description="Выступления творческих коллективов Сакмарского района. Вход свободный.",
            starts_at=now + timedelta(days=10, hours=17),
            ends_at=now + timedelta(days=10, hours=19),
            place_text="ДК Сакмара",
            settlement_id=sakmara,
            address="ул. Советская",
            is_published=True,
        ),
        Event(
            title="Спортивный забег «Рядом56»",
            description="Любительский забег 3 и 5 км. Регистрация на месте за 30 минут до старта.",
            starts_at=now + timedelta(days=18, hours=8),
            ends_at=now + timedelta(days=18, hours=11),
            place_text="Стадион",
            settlement_id=sakmara,
            is_published=True,
        ),
        Event(
            title="Встреча с предпринимателями",
            description="Консультации по поддержке малого бизнеса в районе.",
            starts_at=now + timedelta(days=7, hours=14),
            ends_at=now + timedelta(days=7, hours=16),
            place_text="Администрация района",
            settlement_id=sakmara,
            is_published=True,
        ),
        Event(
            title="Выставка ремёсел (архив)",
            description="Пример прошедшего события — видно в разделе «Прошедшие».",
            starts_at=now - timedelta(days=14, hours=12),
            ends_at=now - timedelta(days=14, hours=16),
            place_text="Выставочный зал",
            settlement_id=orenburg or sakmara,
            is_published=True,
        ),
    ]
    for item in samples:
        session.add(item)


def _seed_transport(session: Session) -> None:
    if session.execute(select(TransportRoute).limit(1)).scalar_one_or_none() is not None:
        return
    sakmara = _settlement_id(session, "село Сакмара")
    samples = [
        TransportRoute(
            title="Сакмара — Оренбург",
            route_number="112",
            description="Междугородный автобус через трассу.",
            schedule_text=(
                "Отправление из Сакмары:\n"
                "06:40, 08:10, 10:30, 13:00, 16:20, 18:45\n\n"
                "Отправление из Оренбурга (автовокзал):\n"
                "07:30, 09:20, 11:40, 14:15, 17:10, 20:00\n\n"
                "В пути около 40–50 минут. Расписание ориентировочное."
            ),
            notes="Уточняйте у перевозчика в праздничные дни.",
            settlement_id=sakmara,
            is_published=True,
        ),
        TransportRoute(
            title="Сакмара — Егорьевка",
            route_number="м/т",
            description="Маршрутка по населённым пунктам.",
            schedule_text=(
                "Будни:\n"
                "Сакмара → Егорьевка: 07:15, 12:40, 17:30\n"
                "Егорьевка → Сакмара: 08:00, 13:20, 18:10\n\n"
                "Суббота: 08:30 и 15:00 в обе стороны.\n"
                "Воскресенье: рейсов нет."
            ),
            notes=None,
            settlement_id=sakmara,
            is_published=True,
        ),
        TransportRoute(
            title="Сакмара — Татарская Каргала",
            route_number="м/т",
            description="Пригородный маршрут.",
            schedule_text=(
                "Сакмара → Татарская Каргала:\n"
                "07:00, 11:20, 15:40\n\n"
                "Татарская Каргала → Сакмара:\n"
                "07:50, 12:10, 16:30"
            ),
            notes="Остановки по требованию на согласованных точках.",
            settlement_id=sakmara,
            is_published=True,
        ),
        TransportRoute(
            title="Сакмара — Светлый",
            route_number="разовый",
            description="Рейс по пятницам и воскресеньям.",
            schedule_text=(
                "Пятница и воскресенье:\n"
                "Сакмара 09:00 → Светлый ~09:45\n"
                "Светлый 17:30 → Сакмара ~18:15"
            ),
            notes="Мест ограничено — лучше уточнять заранее.",
            settlement_id=sakmara,
            is_published=True,
        ),
    ]
    for item in samples:
        session.add(item)

