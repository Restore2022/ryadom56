from datetime import datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import inspect, select, text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import Base, engine
from app.core.security import hash_password
from app.core.seed_data import LEGAL_DOCS, SETTLEMENT_COORDS, SETTLEMENTS
from app.models import (
    AppUpdate,
    DistrictAlert,
    DistrictNews,
    Event,
    LegalDocument,
    Settlement,
    TransportRoute,
    User,
    UserRole,
)

USER_COLUMNS = {
    "last_ip": "VARCHAR(64)",
    "device_brand": "VARCHAR(80)",
    "device_model": "VARCHAR(120)",
    "device_os": "VARCHAR(80)",
    "app_version": "VARCHAR(40)",
    "device_info": "TEXT",
    "last_seen_at": "DATETIME",
    "fcm_token": "VARCHAR(512)",
    "badge": "VARCHAR(40)",
    "rating_score": "FLOAT",
    "token_version": "INTEGER DEFAULT 0",
    "avatar_path": "VARCHAR(255)",
    "ban_reason": "VARCHAR(255)",
}

LISTING_COLUMNS = {
    "close_reason": "VARCHAR(40)",
    "close_note": "TEXT",
    "is_urgent": "BOOLEAN DEFAULT 0",
    "is_pinned": "BOOLEAN DEFAULT 0",
    "auto_flagged": "BOOLEAN DEFAULT 0",
    "previous_snapshot": "TEXT",
    "lifetime_days": "INTEGER DEFAULT 30",
    "expires_at": "DATETIME",
}

REPORT_COLUMNS = {
    "moderator_reply": "TEXT",
}

DIRECTORY_COLUMNS = {
    "hours": "VARCHAR(255)",
    "view_count": "INTEGER DEFAULT 0",
}

EVENT_COLUMNS = {
    "cover_path": "VARCHAR(255)",
    "publish_at": "DATETIME",
    "view_count": "INTEGER DEFAULT 0",
    "favorite_add_count": "INTEGER DEFAULT 0",
}

TRANSPORT_COLUMNS = {
    "schedule_weekdays": "TEXT",
    "schedule_weekends": "TEXT",
    "stops_text": "TEXT",
    "days_mode": "VARCHAR(20) DEFAULT 'all'",
    "view_count": "INTEGER DEFAULT 0",
    "fare_text": "VARCHAR(120)",
    "phone": "VARCHAR(32)",
    "favorite_count": "INTEGER DEFAULT 0",
    "outdated_reports": "INTEGER DEFAULT 0",
}

NEWS_COLUMNS = {
    "cover_path": "VARCHAR(255)",
    "is_pinned": "BOOLEAN DEFAULT 0",
}

ALERT_COLUMNS = {
    "priority": "INTEGER DEFAULT 0",
}

SETTLEMENT_COLUMNS = {
    "lat": "FLOAT",
    "lon": "FLOAT",
}

MESSAGE_COLUMNS = {
    "buyer_id": "INTEGER",
    "kind": "VARCHAR(20) DEFAULT 'text'",
    "call_id": "INTEGER",
}


def init_db() -> None:
    Path("data").mkdir(exist_ok=True)
    Path("data/uploads").mkdir(parents=True, exist_ok=True)
    Path("data/uploads/events").mkdir(parents=True, exist_ok=True)
    Path("data/uploads/news").mkdir(parents=True, exist_ok=True)
    Path("data/uploads/avatars").mkdir(parents=True, exist_ok=True)
    Path("data/releases").mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)
    _migrate_user_columns()
    _migrate_listing_columns()
    _backfill_listing_expiry()
    _migrate_directory_columns()
    _migrate_report_columns()
    _migrate_event_columns()
    _migrate_transport_columns()
    _migrate_news_columns()
    _migrate_alert_columns()
    _migrate_message_columns()
    _migrate_settlement_columns()
    _backfill_call_chat_messages()


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


def _backfill_listing_expiry() -> None:
    inspector = inspect(engine)
    if "listings" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("listings")}
    if "expires_at" not in existing:
        return
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                UPDATE listings
                SET lifetime_days = COALESCE(lifetime_days, 30)
                WHERE lifetime_days IS NULL
                """
            )
        )
        conn.execute(
            text(
                """
                UPDATE listings
                SET expires_at = datetime(created_at, '+30 days')
                WHERE status = 'approved' AND expires_at IS NULL
                """
            )
        )


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


def _migrate_event_columns() -> None:
    inspector = inspect(engine)
    if "events" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("events")}
    with engine.begin() as conn:
        for name, sql_type in EVENT_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE events ADD COLUMN {name} {sql_type}"))


def _migrate_transport_columns() -> None:
    inspector = inspect(engine)
    if "transport_routes" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("transport_routes")}
    with engine.begin() as conn:
        for name, sql_type in TRANSPORT_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE transport_routes ADD COLUMN {name} {sql_type}"))


def _migrate_news_columns() -> None:
    inspector = inspect(engine)
    if "district_news" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("district_news")}
    with engine.begin() as conn:
        for name, sql_type in NEWS_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE district_news ADD COLUMN {name} {sql_type}"))


def _migrate_alert_columns() -> None:
    inspector = inspect(engine)
    if "district_alerts" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("district_alerts")}
    with engine.begin() as conn:
        for name, sql_type in ALERT_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE district_alerts ADD COLUMN {name} {sql_type}"))


def _migrate_message_columns() -> None:
    inspector = inspect(engine)
    if "listing_messages" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("listing_messages")}
    with engine.begin() as conn:
        for name, sql_type in MESSAGE_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE listing_messages ADD COLUMN {name} {sql_type}"))
        # Покупательские сообщения → buyer_id = sender_id
        conn.execute(
            text(
                """
                UPDATE listing_messages
                SET buyer_id = sender_id
                WHERE buyer_id IS NULL
                  AND sender_id != (
                    SELECT author_id FROM listings WHERE listings.id = listing_messages.listing_id
                  )
                """
            )
        )
        # Сообщения продавца без buyer_id — к последнему покупателю по этому объявлению
        conn.execute(
            text(
                """
                UPDATE listing_messages
                SET buyer_id = (
                    SELECT m2.sender_id FROM listing_messages m2
                    JOIN listings l ON l.id = m2.listing_id
                    WHERE m2.listing_id = listing_messages.listing_id
                      AND m2.sender_id != l.author_id
                      AND m2.id < listing_messages.id
                    ORDER BY m2.id DESC
                    LIMIT 1
                )
                WHERE buyer_id IS NULL
                  AND sender_id = (
                    SELECT author_id FROM listings WHERE listings.id = listing_messages.listing_id
                  )
                """
            )
        )
        conn.execute(text("UPDATE listing_messages SET kind = 'text' WHERE kind IS NULL OR kind = ''"))


def _backfill_call_chat_messages() -> None:
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    if "app_calls" not in tables or "listing_messages" not in tables:
        return
    cols = {col["name"] for col in inspector.get_columns("listing_messages")}
    if "call_id" not in cols:
        return
    from app.core.database import SessionLocal
    from app.models import AppCall
    from app.services.chat_calls import TERMINAL_CALL_STATUSES, record_call_in_chat

    db = SessionLocal()
    try:
        rows = db.execute(select(AppCall).where(AppCall.status.in_(TERMINAL_CALL_STATUSES))).scalars().all()
        for call in rows:
            record_call_in_chat(db, call, mark_read=True)
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _migrate_settlement_columns() -> None:
    inspector = inspect(engine)
    if "settlements" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("settlements")}
    with engine.begin() as conn:
        for name, sql_type in SETTLEMENT_COLUMNS.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE settlements ADD COLUMN {name} {sql_type}"))


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
                    lat=(SETTLEMENT_COORDS.get(display) or (None, None))[0],
                    lon=(SETTLEMENT_COORDS.get(display) or (None, None))[1],
                )
            )
        session.flush()

    for row in session.execute(select(Settlement)).scalars():
        coords = SETTLEMENT_COORDS.get(row.display_name)
        if coords and (row.lat is None or row.lon is None):
            row.lat, row.lon = coords

    for doc in LEGAL_DOCS:
        found = session.execute(select(LegalDocument).where(LegalDocument.slug == doc["slug"])).scalar_one_or_none()
        if found is None:
            session.add(LegalDocument(**doc))
        elif found.version != doc["version"]:
            found.title = doc["title"]
            found.version = doc["version"]
            found.body = doc["body"]

    if session.execute(select(AppUpdate).where(AppUpdate.id == 1)).scalar_one_or_none() is None:
        session.add(
            AppUpdate(
                id=1,
                version_name="0.11.0",
                version_code=12,
                force_update=False,
                notes="Установите обновление, чтобы получить новые функции Рядом56.",
            )
        )

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

    if settings.seed_demo_content:
        _seed_events(session)
        _seed_transport(session)
        _seed_news(session)
        _seed_alerts(session)
        _enrich_transport(session)

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
            schedule_weekdays="06:40, 08:10, 10:30, 13:00, 16:20, 18:45",
            schedule_weekends="08:10, 13:00, 18:45",
            stops_text="Сакмара (остановка у ДК)\nТатарская Каргала\nОренбург, автовокзал",
            days_mode="all",
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
            schedule_weekdays="07:15, 12:40, 17:30",
            schedule_weekends="08:30, 15:00",
            stops_text="Сакмара\nМарьевка\nЕгорьевка",
            days_mode="all",
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
            stops_text="Сакмара\nТатарская Каргала",
            days_mode="weekdays",
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
            stops_text="Сакмара\nСветлый",
            days_mode="weekends",
            notes="Мест ограничено — лучше уточнять заранее.",
            settlement_id=sakmara,
            is_published=True,
        ),
    ]
    for item in samples:
        session.add(item)


def _enrich_transport(session: Session) -> None:
    for route in session.execute(select(TransportRoute)).scalars().all():
        if not route.stops_text and "Оренбург" in route.title:
            route.stops_text = "Сакмара (остановка у ДК)\nТатарская Каргала\nОренбург, автовокзал"
        if not route.days_mode:
            route.days_mode = "all"


def _seed_news(session: Session) -> None:
    if session.execute(select(DistrictNews).limit(1)).scalar_one_or_none() is not None:
        return
    sakmara = _settlement_id(session, "село Сакмара")
    now = datetime.now(timezone.utc)
    session.add(
        DistrictNews(
            title="График работы администрации на праздники",
            body="В праздничные дни приём граждан — по предварительной записи. Телефон для справок уточняйте в справочнике.",
            settlement_id=sakmara,
            is_published=True,
            published_at=now,
        )
    )
    session.add(
        DistrictNews(
            title="Субботник в районе",
            body="Приглашаем жителей принять участие в весеннем субботнике. Встреча у Дома культуры в 9:00.",
            settlement_id=None,
            is_published=True,
            published_at=now - timedelta(days=2),
        )
    )


def _seed_alerts(session: Session) -> None:
    if session.execute(select(DistrictAlert).limit(1)).scalar_one_or_none() is not None:
        return
    session.add(
        DistrictAlert(
            message="Будьте осторожны на дорогах: возможна гололёдица.",
            kind="warn",
            is_active=True,
        )
    )

