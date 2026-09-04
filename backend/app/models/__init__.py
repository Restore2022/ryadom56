import enum
from datetime import datetime

from sqlalchemy import Boolean, Enum, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, UtcDateTime


class UserRole(str, enum.Enum):
    user = "user"
    moderator = "moderator"
    editor = "editor"
    admin = "admin"


class ListingCategory(str, enum.Enum):
    goods = "goods"  # товары
    wanted = "wanted"  # куплю
    services = "services"  # услуги
    jobs = "jobs"  # работа
    rent = "rent"  # аренда
    free = "free"  # отдам даром
    lost_found = "lost_found"  # потеряшки


class ListingStatus(str, enum.Enum):
    draft = "draft"
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    archived = "archived"


class DirectoryCategory(str, enum.Enum):
    school = "school"
    hospital = "hospital"
    shop = "shop"
    pharmacy = "pharmacy"
    admin = "admin"
    bank = "bank"
    post = "post"
    transport = "transport"
    culture = "culture"
    sport = "sport"
    other = "other"


class Settlement(Base):
    __tablename__ = "settlements"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    settlement_type: Mapped[str] = mapped_column(String(40), default="село")
    council: Mapped[str | None] = mapped_column(String(120), nullable=True)
    display_name: Mapped[str] = mapped_column(String(180), nullable=False, unique=True)
    is_district: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    lon: Mapped[float | None] = mapped_column(Float, nullable=True)

    users: Mapped[list["User"]] = relationship(back_populates="settlement")


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    settlement_id: Mapped[int] = mapped_column(ForeignKey("settlements.id"), nullable=False)
    role: Mapped[UserRole] = mapped_column(Enum(UserRole), default=UserRole.user)
    accepted_terms: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    last_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    device_brand: Mapped[str | None] = mapped_column(String(80), nullable=True)
    device_model: Mapped[str | None] = mapped_column(String(120), nullable=True)
    device_os: Mapped[str | None] = mapped_column(String(80), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(40), nullable=True)
    device_info: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    fcm_token: Mapped[str | None] = mapped_column(String(512), nullable=True)
    badge: Mapped[str | None] = mapped_column(String(40), nullable=True)  # new|trusted|caution
    rating_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    token_version: Mapped[int] = mapped_column(Integer, default=0)
    avatar_path: Mapped[str | None] = mapped_column(String(255), nullable=True)
    ban_reason: Mapped[str | None] = mapped_column(String(255), nullable=True)

    settlement: Mapped["Settlement"] = relationship(back_populates="users")
    listings: Mapped[list["Listing"]] = relationship(back_populates="author")
    favorites: Mapped[list["Favorite"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    reports: Mapped[list["ListingReport"]] = relationship(
        back_populates="reporter",
        foreign_keys="ListingReport.reporter_id",
    )
    sessions: Mapped[list["UserSession"]] = relationship(back_populates="user", cascade="all, delete-orphan")


class UserSession(Base):
    __tablename__ = "user_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    jti: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    device_id: Mapped[str | None] = mapped_column(String(64), index=True, nullable=True)
    device_brand: Mapped[str | None] = mapped_column(String(80), nullable=True)
    device_model: Mapped[str | None] = mapped_column(String(120), nullable=True)
    device_os: Mapped[str | None] = mapped_column(String(80), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(40), nullable=True)
    last_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    fcm_token: Mapped[str | None] = mapped_column(String(512), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    last_seen_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)

    user: Mapped["User"] = relationship(back_populates="sessions")


class Listing(Base):
    __tablename__ = "listings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    author_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    settlement_id: Mapped[int] = mapped_column(ForeignKey("settlements.id"), nullable=False)
    category: Mapped[ListingCategory] = mapped_column(Enum(ListingCategory), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    price: Mapped[float | None] = mapped_column(Float, nullable=True)
    contact_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    status: Mapped[ListingStatus] = mapped_column(Enum(ListingStatus), default=ListingStatus.pending)
    moderation_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_urgent: Mapped[bool] = mapped_column(Boolean, default=False)
    is_pinned: Mapped[bool] = mapped_column(Boolean, default=False)
    auto_flagged: Mapped[bool] = mapped_column(Boolean, default=False)
    previous_snapshot: Mapped[str | None] = mapped_column(Text, nullable=True)
    close_reason: Mapped[str | None] = mapped_column(String(40), nullable=True)
    close_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    lifetime_days: Mapped[int] = mapped_column(Integer, default=30)
    expires_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    last_relevant_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    relevance_reminded_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime(), server_default=func.now(), onupdate=func.now()
    )

    author: Mapped["User"] = relationship(back_populates="listings")
    settlement: Mapped["Settlement"] = relationship()
    images: Mapped[list["ListingImage"]] = relationship(
        back_populates="listing",
        cascade="all, delete-orphan",
        order_by="ListingImage.sort_order",
    )


class ListingImage(Base):
    __tablename__ = "listing_images"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    listing_id: Mapped[int] = mapped_column(ForeignKey("listings.id"), nullable=False, index=True)
    path: Mapped[str] = mapped_column(String(255), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    listing: Mapped["Listing"] = relationship(back_populates="images")


class DirectoryItem(Base):
    __tablename__ = "directory_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    settlement_id: Mapped[int | None] = mapped_column(ForeignKey("settlements.id"), nullable=True)
    category: Mapped[DirectoryCategory] = mapped_column(Enum(DirectoryCategory), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    address: Mapped[str | None] = mapped_column(String(255), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(64), nullable=True)
    website: Mapped[str | None] = mapped_column(String(255), nullable=True)
    hours: Mapped[str | None] = mapped_column(String(255), nullable=True)
    lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    lon: Mapped[float | None] = mapped_column(Float, nullable=True)
    is_published: Mapped[bool] = mapped_column(Boolean, default=True)
    view_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime(), server_default=func.now(), onupdate=func.now()
    )

    settlement: Mapped["Settlement | None"] = relationship()


class LegalDocument(Base):
    __tablename__ = "legal_documents"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    slug: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    version: Mapped[str] = mapped_column(String(32), default="1.0")
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime(), server_default=func.now(), onupdate=func.now()
    )


class Event(Base):
    __tablename__ = "events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    starts_at: Mapped[datetime] = mapped_column(UtcDateTime(), nullable=False, index=True)
    ends_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    place_text: Mapped[str] = mapped_column(String(255), nullable=False)
    settlement_id: Mapped[int | None] = mapped_column(ForeignKey("settlements.id"), nullable=True)
    address: Mapped[str | None] = mapped_column(String(255), nullable=True)
    lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    lon: Mapped[float | None] = mapped_column(Float, nullable=True)
    cover_path: Mapped[str | None] = mapped_column(String(255), nullable=True)
    publish_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True, index=True)
    is_published: Mapped[bool] = mapped_column(Boolean, default=True)
    view_count: Mapped[int] = mapped_column(Integer, default=0)
    favorite_add_count: Mapped[int] = mapped_column(Integer, default=0)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime(), server_default=func.now(), onupdate=func.now()
    )

    settlement: Mapped["Settlement | None"] = relationship()
    created_by: Mapped["User | None"] = relationship()


class TransportRoute(Base):
    __tablename__ = "transport_routes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    route_number: Mapped[str | None] = mapped_column(String(40), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    schedule_text: Mapped[str] = mapped_column(Text, nullable=False)
    schedule_weekdays: Mapped[str | None] = mapped_column(Text, nullable=True)
    schedule_weekends: Mapped[str | None] = mapped_column(Text, nullable=True)
    stops_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    days_mode: Mapped[str] = mapped_column(String(20), default="all")  # all | weekdays | weekends
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    fare_text: Mapped[str | None] = mapped_column(String(120), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    settlement_id: Mapped[int | None] = mapped_column(ForeignKey("settlements.id"), nullable=True)
    is_published: Mapped[bool] = mapped_column(Boolean, default=True)
    view_count: Mapped[int] = mapped_column(Integer, default=0)
    favorite_count: Mapped[int] = mapped_column(Integer, default=0)
    outdated_reports: Mapped[int] = mapped_column(Integer, default=0)
    times_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime(), server_default=func.now(), onupdate=func.now()
    )

    settlement: Mapped["Settlement | None"] = relationship()
    stop_links: Mapped[list["TransportRouteStop"]] = relationship(
        back_populates="route",
        cascade="all, delete-orphan",
        order_by="TransportRouteStop.sort_order",
    )
    place_links: Mapped[list["TransportRoutePlace"]] = relationship(
        back_populates="route",
        cascade="all, delete-orphan",
    )


class TransportStop(Base):
    __tablename__ = "transport_stops"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False, index=True)
    settlement_id: Mapped[int | None] = mapped_column(ForeignKey("settlements.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    settlement: Mapped["Settlement | None"] = relationship()


class TransportRouteStop(Base):
    __tablename__ = "transport_route_stops"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    route_id: Mapped[int] = mapped_column(ForeignKey("transport_routes.id"), nullable=False, index=True)
    stop_id: Mapped[int] = mapped_column(ForeignKey("transport_stops.id"), nullable=False, index=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    route: Mapped["TransportRoute"] = relationship(back_populates="stop_links")
    stop: Mapped["TransportStop"] = relationship()


class TransportRoutePlace(Base):
    __tablename__ = "transport_route_places"
    __table_args__ = (UniqueConstraint("route_id", "settlement_id", name="uq_transport_route_place"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    route_id: Mapped[int] = mapped_column(ForeignKey("transport_routes.id"), nullable=False, index=True)
    settlement_id: Mapped[int] = mapped_column(ForeignKey("settlements.id"), nullable=False, index=True)

    route: Mapped["TransportRoute"] = relationship(back_populates="place_links")
    settlement: Mapped["Settlement"] = relationship()


class TransportFavorite(Base):
    __tablename__ = "transport_favorites"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    route_id: Mapped[int] = mapped_column(ForeignKey("transport_routes.id"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())


class DistrictNews(Base):
    __tablename__ = "district_news"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    cover_path: Mapped[str | None] = mapped_column(String(255), nullable=True)
    settlement_id: Mapped[int | None] = mapped_column(ForeignKey("settlements.id"), nullable=True)
    is_published: Mapped[bool] = mapped_column(Boolean, default=True)
    is_pinned: Mapped[bool] = mapped_column(Boolean, default=False)
    published_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    source: Mapped[str | None] = mapped_column(String(40), nullable=True)
    source_url: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # oblast — вся область; sakmarsky — Сакмарский район; local — одно село
    audience: Mapped[str] = mapped_column(String(20), default="oblast", nullable=False)
    vk_post_id: Mapped[str | None] = mapped_column(String(64), nullable=True, unique=True, index=True)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime(), server_default=func.now(), onupdate=func.now()
    )

    settlement: Mapped["Settlement | None"] = relationship()
    images: Mapped[list["NewsImage"]] = relationship(
        back_populates="news",
        cascade="all, delete-orphan",
        order_by="NewsImage.sort_order",
    )


class NewsImage(Base):
    __tablename__ = "news_images"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    news_id: Mapped[int] = mapped_column(ForeignKey("district_news.id"), nullable=False, index=True)
    path: Mapped[str] = mapped_column(String(255), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    news: Mapped["DistrictNews"] = relationship(back_populates="images")


class VkNewsRun(Base):
    """Лог забора новостей со стены VK."""

    __tablename__ = "vk_news_runs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    started_at: Mapped[datetime] = mapped_column(UtcDateTime(), nullable=False)
    finished_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="ok")  # ok | error
    source: Mapped[str] = mapped_column(String(120), default="vk.ru/sakmaraadm")
    fetched: Mapped[int] = mapped_column(Integer, default=0)
    created: Mapped[int] = mapped_column(Integer, default=0)
    skipped: Mapped[int] = mapped_column(Integer, default=0)
    photos: Mapped[int] = mapped_column(Integer, default=0)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    triggered_by: Mapped[str] = mapped_column(String(40), default="timer")


class DistrictAlert(Base):
    """Срочный баннер сверху ленты объявлений."""

    __tablename__ = "district_alerts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    message: Mapped[str] = mapped_column(String(280), nullable=False)
    kind: Mapped[str] = mapped_column(String(20), default="info")  # info | warn | danger
    priority: Mapped[int] = mapped_column(Integer, default=0)  # выше = важнее
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    starts_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    ends_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    settlement_ids: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime(), server_default=func.now(), onupdate=func.now()
    )


class ListingMessage(Base):
    """Личная переписка покупатель↔продавец по объявлению (тред = listing_id + buyer_id)."""

    __tablename__ = "listing_messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    listing_id: Mapped[int] = mapped_column(ForeignKey("listings.id"), nullable=False, index=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    buyer_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    # text — обычное сообщение; photo — фото; call — системное событие звонка
    kind: Mapped[str] = mapped_column(String(20), default="text", server_default="text")
    call_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    image_path: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())


class Favorite(Base):
    __tablename__ = "favorites"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    listing_id: Mapped[int] = mapped_column(ForeignKey("listings.id"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    user: Mapped["User"] = relationship(back_populates="favorites")
    listing: Mapped["Listing"] = relationship()


class ListingReport(Base):
    __tablename__ = "listing_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    listing_id: Mapped[int] = mapped_column(ForeignKey("listings.id"), nullable=False, index=True)
    reporter_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    reason: Mapped[str] = mapped_column(String(40), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="open")  # open / reviewed / dismissed
    moderator_reply: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    reviewed_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    reviewed_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)

    listing: Mapped["Listing"] = relationship()
    reporter: Mapped["User"] = relationship(foreign_keys=[reporter_id], back_populates="reports")
    reviewed_by: Mapped["User | None"] = relationship(foreign_keys=[reviewed_by_id])


class UserReport(Base):
    __tablename__ = "user_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    target_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    reporter_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    listing_id: Mapped[int | None] = mapped_column(ForeignKey("listings.id"), nullable=True)
    reason: Mapped[str] = mapped_column(String(40), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="open")
    moderator_reply: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    reviewed_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    reviewed_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)

    target: Mapped["User"] = relationship(foreign_keys=[target_id])
    reporter: Mapped["User"] = relationship(foreign_keys=[reporter_id])
    listing: Mapped["Listing | None"] = relationship()
    reviewed_by: Mapped["User | None"] = relationship(foreign_keys=[reviewed_by_id])


class DirectoryFavorite(Base):
    __tablename__ = "directory_favorites"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    directory_id: Mapped[int] = mapped_column(ForeignKey("directory_items.id"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    user: Mapped["User"] = relationship()
    directory_item: Mapped["DirectoryItem"] = relationship()


class DirectoryReport(Base):
    __tablename__ = "directory_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    directory_id: Mapped[int] = mapped_column(ForeignKey("directory_items.id"), nullable=False, index=True)
    reporter_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    reason: Mapped[str] = mapped_column(String(40), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="open")  # open / reviewed / dismissed
    moderator_reply: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    reviewed_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    reviewed_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)

    directory_item: Mapped["DirectoryItem"] = relationship()
    reporter: Mapped["User"] = relationship(foreign_keys=[reporter_id])
    reviewed_by: Mapped["User | None"] = relationship(foreign_keys=[reviewed_by_id])


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    actor_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    action: Mapped[str] = mapped_column(String(80), nullable=False)
    entity_type: Mapped[str] = mapped_column(String(40), nullable=False)
    entity_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    actor: Mapped["User"] = relationship()


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(40), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str | None] = mapped_column(Text, nullable=True)
    listing_id: Mapped[int | None] = mapped_column(ForeignKey("listings.id"), nullable=True)
    ride_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    user: Mapped["User"] = relationship()
    listing: Mapped["Listing | None"] = relationship()


class BlacklistEntry(Base):
    __tablename__ = "blacklist_entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    kind: Mapped[str] = mapped_column(String(20), nullable=False)  # phone | word
    value: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    note: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    created_by: Mapped["User | None"] = relationship()


class PasswordReset(Base):
    __tablename__ = "password_resets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    email: Mapped[str] = mapped_column(String(255), index=True, nullable=False)
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    expires_at: Mapped[datetime] = mapped_column(UtcDateTime(), nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    created_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    user: Mapped["User"] = relationship()


class AppUpdate(Base):
    """Единственная строка (id=1): актуальная версия Android APK."""

    __tablename__ = "app_updates"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    version_name: Mapped[str] = mapped_column(String(40), nullable=False, default="0.11.0")
    version_code: Mapped[int] = mapped_column(Integer, nullable=False, default=12)
    force_update: Mapped[bool] = mapped_column(Boolean, default=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    apk_filename: Mapped[str | None] = mapped_column(String(255), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime(), server_default=func.now(), onupdate=func.now()
    )


class AppCall(Base):
    """Интернет-звонок 1-на-1 по объявлению. Медиа P2P, на сервере только журнал и сигнал."""

    __tablename__ = "app_calls"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    listing_id: Mapped[int] = mapped_column(ForeignKey("listings.id"), index=True, nullable=False)
    caller_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    callee_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    # ringing / active / ended / missed / declined / cancelled / failed / busy
    status: Mapped[str] = mapped_column(String(20), default="ringing", index=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now(), index=True)
    answered_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    duration_sec: Mapped[int] = mapped_column(Integer, default=0)
    end_reason: Mapped[str | None] = mapped_column(String(80), nullable=True)
    ended_by_id: Mapped[int | None] = mapped_column(Integer, nullable=True)

    listing: Mapped["Listing"] = relationship()
    caller: Mapped["User"] = relationship(foreign_keys=[caller_id])
    callee: Mapped["User"] = relationship(foreign_keys=[callee_id])


class ClientErrorLog(Base):
    __tablename__ = "client_error_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now(), index=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    message: Mapped[str] = mapped_column(String(500), nullable=False)
    stack: Mapped[str | None] = mapped_column(Text, nullable=True)
    screen: Mapped[str | None] = mapped_column(String(120), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(40), nullable=True)
    device_brand: Mapped[str | None] = mapped_column(String(80), nullable=True)
    device_model: Mapped[str | None] = mapped_column(String(120), nullable=True)
    device_os: Mapped[str | None] = mapped_column(String(80), nullable=True)
    client_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False, index=True)


class SiteContact(Base):
    __tablename__ = "site_contacts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    settlement: Mapped[str | None] = mapped_column(String(120), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="new", index=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now(), index=True)


class Presence(Base):
    """Анонимный пульс сайта и приложения: кто сейчас онлайн, в том числе без входа."""

    __tablename__ = "presence"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    client_key: Mapped[str] = mapped_column(String(48), unique=True, index=True, nullable=False)
    source: Mapped[str] = mapped_column(String(12), index=True, nullable=False)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    first_seen_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    last_seen_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now(), index=True)


class GuestPushDevice(Base):
    """Пуш-токен телефона без входа — только общие рассылки и срочные баннеры."""

    __tablename__ = "guest_push_devices"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    fcm_token: Mapped[str] = mapped_column(String(512), nullable=False)
    app_version: Mapped[str | None] = mapped_column(String(40), nullable=True)
    settlement_id: Mapped[int | None] = mapped_column(ForeignKey("settlements.id"), nullable=True, index=True)
    first_seen_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    last_seen_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now(), index=True)


class PromoLink(Base):
    """Короткая ссылка для рекламы в группах: https://legac.ru/r/otdam"""

    __tablename__ = "promo_links"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    slug: Mapped[str] = mapped_column(String(32), unique=True, index=True, nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    note: Mapped[str | None] = mapped_column(String(255), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    hits: Mapped[list["PromoHit"]] = relationship(back_populates="link")


class PromoHit(Base):
    """Заход по рекламной ссылке или скачивание APK с этой ссылки."""

    __tablename__ = "promo_hits"
    __table_args__ = (
        Index("ix_promo_hits_link_kind_created", "link_id", "kind", "created_at"),
        Index("ix_promo_hits_link_kind_visitor", "link_id", "kind", "visitor_key"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    link_id: Mapped[int] = mapped_column(ForeignKey("promo_links.id"), index=True, nullable=False)
    kind: Mapped[str] = mapped_column(String(12), index=True, nullable=False)  # visit | download
    visitor_key: Mapped[str] = mapped_column(String(48), index=True, nullable=False)
    ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now(), index=True)

    link: Mapped["PromoLink"] = relationship(back_populates="hits")


class Ride(Base):
    """Попутка: человек едет или ищет место в машине."""

    __tablename__ = "rides"
    __table_args__ = (
        Index("ix_rides_status_depart", "status", "depart_at"),
        Index("ix_rides_from_settlement", "from_settlement_id"),
        Index("ix_rides_to_settlement", "to_settlement_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    author_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    kind: Mapped[str] = mapped_column(String(12), nullable=False, index=True)  # drive | need
    from_settlement_id: Mapped[int] = mapped_column(ForeignKey("settlements.id"), nullable=False)
    to_settlement_id: Mapped[int] = mapped_column(ForeignKey("settlements.id"), nullable=False)
    depart_at: Mapped[datetime] = mapped_column(UtcDateTime(), nullable=False, index=True)
    seats: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    note: Mapped[str | None] = mapped_column(String(400), nullable=True)
    contact_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    status: Mapped[str] = mapped_column(String(12), default="open", index=True)  # open | closed | hidden
    close_reason: Mapped[str | None] = mapped_column(String(40), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        UtcDateTime(), server_default=func.now(), onupdate=func.now()
    )

    author: Mapped["User"] = relationship(foreign_keys=[author_id])
    from_place: Mapped["Settlement"] = relationship(foreign_keys=[from_settlement_id])
    to_place: Mapped["Settlement"] = relationship(foreign_keys=[to_settlement_id])


class RideMessage(Base):
    """Личная переписка по попутке (тред = ride_id + passenger_id)."""

    __tablename__ = "ride_messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ride_id: Mapped[int] = mapped_column(ForeignKey("rides.id"), nullable=False, index=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    passenger_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())


class RideReport(Base):
    __tablename__ = "ride_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ride_id: Mapped[int] = mapped_column(ForeignKey("rides.id"), nullable=False, index=True)
    reporter_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    reason: Mapped[str] = mapped_column(String(40), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="open")
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now())

    ride: Mapped["Ride"] = relationship()
    reporter: Mapped["User"] = relationship(foreign_keys=[reporter_id])


class ApkDownload(Base):
    """Скачивание APK с сайта, из приложения или по рекламной ссылке."""

    __tablename__ = "apk_downloads"
    __table_args__ = (Index("ix_apk_downloads_visitor_created", "visitor_key", "created_at"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), server_default=func.now(), index=True)
    visitor_key: Mapped[str] = mapped_column(String(48), index=True, nullable=False)
    ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    slug: Mapped[str | None] = mapped_column(String(32), nullable=True)
    source: Mapped[str] = mapped_column(String(20), default="site", index=True)
