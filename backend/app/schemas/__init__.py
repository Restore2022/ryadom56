from datetime import datetime
from enum import Enum

from pydantic import BaseModel, EmailStr, Field


class UserRole(str, Enum):
    user = "user"
    moderator = "moderator"
    editor = "editor"
    admin = "admin"


class ListingCategory(str, Enum):
    goods = "goods"
    services = "services"
    jobs = "jobs"
    rent = "rent"
    free = "free"
    lost_found = "lost_found"


class ListingStatus(str, Enum):
    draft = "draft"
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    archived = "archived"


class DirectoryCategory(str, Enum):
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


class SettlementOut(BaseModel):
    id: int
    name: str
    settlement_type: str
    council: str | None
    display_name: str
    is_district: bool

    class Config:
        from_attributes = True


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: int
    email: EmailStr
    full_name: str
    phone: str | None
    settlement_id: int
    settlement: SettlementOut | None = None
    role: UserRole
    is_active: bool
    created_at: datetime
    last_ip: str | None = None
    device_brand: str | None = None
    device_model: str | None = None
    device_os: str | None = None
    app_version: str | None = None
    device_info: str | None = None
    last_seen_at: datetime | None = None
    badge: str | None = None
    rating_score: float | None = None
    listings_count: int = 0
    reports_against: int = 0

    class Config:
        from_attributes = True


class PublicUserOut(BaseModel):
    id: int
    full_name: str
    settlement_name: str | None = None
    badge: str | None = None
    rating_score: float | None = None
    listings_count: int = 0
    reports_against: int = 0
    member_since: datetime | None = None
    is_active: bool = True


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)
    full_name: str = Field(min_length=2, max_length=120)
    phone: str | None = Field(default=None, max_length=32)
    settlement_id: int
    accepted_terms: bool
    accepted_privacy: bool
    accepted_listing_rules: bool


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class ForgotPasswordIn(BaseModel):
    email: EmailStr


class ResetPasswordIn(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")
    password: str = Field(min_length=6, max_length=128)


class MessageOut(BaseModel):
    ok: bool = True
    message: str


class VerifyPasswordIn(BaseModel):
    password: str = Field(min_length=1, max_length=128)


class ListingCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    description: str = Field(min_length=3, max_length=5000)
    category: ListingCategory
    settlement_id: int
    price: float | None = Field(default=None, ge=0)
    contact_phone: str | None = Field(default=None, max_length=32)
    is_urgent: bool = False
    as_draft: bool = False


class ListingUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    description: str | None = Field(default=None, min_length=3, max_length=5000)
    category: ListingCategory | None = None
    settlement_id: int | None = None
    price: float | None = Field(default=None, ge=0)
    contact_phone: str | None = None
    is_urgent: bool | None = None
    as_draft: bool | None = None


class LegalUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    body: str | None = Field(default=None, min_length=10)
    version: str | None = Field(default=None, max_length=32)


class ListingModerationIn(BaseModel):
    status: ListingStatus
    moderation_note: str | None = None


class ListingCloseIn(BaseModel):
    reason: str = Field(pattern="^(sold|not_relevant|busy|other)$")
    note: str | None = Field(default=None, max_length=500)


class ListingImageOut(BaseModel):
    id: int
    url: str
    sort_order: int


class ListingImagesReorderIn(BaseModel):
    image_ids: list[int] = Field(min_length=1, max_length=5)


class ListingSnapshot(BaseModel):
    title: str | None = None
    description: str | None = None
    category: str | None = None
    price: float | None = None
    contact_phone: str | None = None
    is_urgent: bool | None = None


class ListingOut(BaseModel):
    id: int
    author_id: int
    author_name: str | None = None
    author_badge: str | None = None
    author_rating: float | None = None
    settlement_id: int
    settlement_name: str | None = None
    category: ListingCategory
    title: str
    description: str
    price: float | None
    contact_phone: str | None
    phone_hidden: bool = False
    status: ListingStatus
    moderation_note: str | None
    close_reason: str | None = None
    close_note: str | None = None
    is_urgent: bool = False
    is_pinned: bool = False
    auto_flagged: bool = False
    previous_snapshot: ListingSnapshot | None = None
    images: list[ListingImageOut] = []
    is_favorited: bool = False
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ListingPageOut(BaseModel):
    items: list[ListingOut]
    total: int
    limit: int
    offset: int


class ProfileUpdateIn(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=120)
    phone: str | None = Field(default=None, max_length=32)
    settlement_id: int | None = None
    password: str | None = Field(default=None, min_length=6, max_length=128)
    current_password: str | None = None


class ListingReportIn(BaseModel):
    reason: str = Field(pattern="^(spam|fraud|prohibited|other)$")
    note: str | None = Field(default=None, max_length=500)


class ListingReportOut(BaseModel):
    id: int
    listing_id: int
    listing_title: str | None = None
    reporter_id: int
    reporter_name: str | None = None
    reason: str
    note: str | None
    status: str
    moderator_reply: str | None = None
    created_at: datetime

    class Config:
        from_attributes = True


class DirectoryReportIn(BaseModel):
    reason: str = Field(pattern="^(wrong_phone|wrong_address|closed|other)$")
    note: str | None = Field(default=None, max_length=500)


class DirectoryReportOut(BaseModel):
    id: int
    directory_id: int
    directory_title: str | None = None
    reporter_id: int
    reporter_name: str | None = None
    reason: str
    note: str | None
    status: str
    moderator_reply: str | None = None
    created_at: datetime

    class Config:
        from_attributes = True


class ReportStatusUpdate(BaseModel):
    status: str = Field(pattern="^(open|reviewed|dismissed)$")
    moderator_reply: str | None = Field(default=None, max_length=500)


class BulkModerateIn(BaseModel):
    ids: list[int] = Field(min_length=1, max_length=100)
    status: ListingStatus
    moderation_note: str | None = None


class AuditLogOut(BaseModel):
    id: int
    actor_id: int
    actor_name: str | None = None
    action: str
    entity_type: str
    entity_id: int | None
    details: str | None
    created_at: datetime


class DirectoryCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    category: DirectoryCategory
    settlement_id: int | None = None
    description: str | None = None
    address: str | None = None
    phone: str | None = None
    website: str | None = None
    hours: str | None = Field(default=None, max_length=255)
    lat: float | None = None
    lon: float | None = None
    is_published: bool = True


class DirectoryUpdate(BaseModel):
    title: str | None = None
    category: DirectoryCategory | None = None
    settlement_id: int | None = None
    description: str | None = None
    address: str | None = None
    phone: str | None = None
    website: str | None = None
    hours: str | None = Field(default=None, max_length=255)
    lat: float | None = None
    lon: float | None = None
    is_published: bool | None = None


class DirectoryOut(BaseModel):
    id: int
    title: str
    category: DirectoryCategory
    settlement_id: int | None
    settlement_name: str | None = None
    description: str | None
    address: str | None
    phone: str | None
    website: str | None
    hours: str | None = None
    is_open_now: bool | None = None
    maps_url: str | None = None
    lat: float | None
    lon: float | None
    is_published: bool
    is_favorited: bool = False
    view_count: int = 0
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class DirectoryPageOut(BaseModel):
    items: list[DirectoryOut]
    total: int
    limit: int
    offset: int


class LegalOut(BaseModel):
    slug: str
    title: str
    body: str
    version: str
    updated_at: datetime

    class Config:
        from_attributes = True


class UserRoleUpdate(BaseModel):
    role: UserRole | None = None
    is_active: bool | None = None
    full_name: str | None = Field(default=None, min_length=2, max_length=120)
    phone: str | None = Field(default=None, max_length=32)
    settlement_id: int | None = None
    email: EmailStr | None = None
    password: str | None = Field(default=None, min_length=6, max_length=128)
    badge: str | None = Field(default=None, max_length=40)


class AdminUserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)
    full_name: str = Field(min_length=2, max_length=120)
    phone: str | None = Field(default=None, max_length=32)
    settlement_id: int
    role: UserRole = UserRole.user
    is_active: bool = True
    badge: str | None = Field(default=None, max_length=40)


class DeviceInfoIn(BaseModel):
    device_brand: str | None = Field(default=None, max_length=80)
    device_model: str | None = Field(default=None, max_length=120)
    device_os: str | None = Field(default=None, max_length=80)
    app_version: str | None = Field(default=None, max_length=40)
    device_info: str | None = Field(default=None, max_length=2000)
    fcm_token: str | None = Field(default=None, max_length=512)
    device_id: str | None = Field(default=None, max_length=64)


class SessionOut(BaseModel):
    id: int
    device_brand: str | None = None
    device_model: str | None = None
    device_os: str | None = None
    app_version: str | None = None
    last_ip: str | None = None
    created_at: datetime | None = None
    last_seen_at: datetime | None = None
    is_current: bool = False

    class Config:
        from_attributes = True


class CategoryStat(BaseModel):
    category: str
    count: int


class DayStat(BaseModel):
    day: str
    count: int


class SettlementStat(BaseModel):
    settlement_id: int | None = None
    settlement_name: str
    listings_count: int = 0
    directory_opens: int = 0


class EventCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    description: str = Field(min_length=3, max_length=8000)
    starts_at: datetime
    ends_at: datetime | None = None
    place_text: str = Field(min_length=2, max_length=255)
    settlement_id: int | None = None
    address: str | None = Field(default=None, max_length=255)
    lat: float | None = None
    lon: float | None = None
    is_published: bool = True
    publish_at: datetime | None = None


class EventUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    description: str | None = Field(default=None, min_length=3, max_length=8000)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    place_text: str | None = Field(default=None, min_length=2, max_length=255)
    settlement_id: int | None = None
    address: str | None = Field(default=None, max_length=255)
    lat: float | None = None
    lon: float | None = None
    is_published: bool | None = None
    publish_at: datetime | None = None


class EventOut(BaseModel):
    id: int
    title: str
    description: str
    starts_at: datetime
    ends_at: datetime | None
    place_text: str
    settlement_id: int | None
    settlement_name: str | None = None
    address: str | None
    lat: float | None
    lon: float | None
    cover_url: str | None = None
    publish_at: datetime | None = None
    is_published: bool
    view_count: int = 0
    status: str = "published"  # draft | scheduled | published
    created_by_id: int | None = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class TransportCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    route_number: str | None = Field(default=None, max_length=40)
    description: str | None = Field(default=None, max_length=4000)
    schedule_text: str = Field(min_length=3, max_length=12000)
    schedule_weekdays: str | None = Field(default=None, max_length=12000)
    schedule_weekends: str | None = Field(default=None, max_length=12000)
    stops_text: str | None = Field(default=None, max_length=8000)
    days_mode: str = Field(default="all", pattern="^(all|weekdays|weekends)$")
    notes: str | None = Field(default=None, max_length=2000)
    fare_text: str | None = Field(default=None, max_length=120)
    phone: str | None = Field(default=None, max_length=32)
    settlement_id: int | None = None
    is_published: bool = True


class TransportUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    route_number: str | None = Field(default=None, max_length=40)
    description: str | None = Field(default=None, max_length=4000)
    schedule_text: str | None = Field(default=None, min_length=3, max_length=12000)
    schedule_weekdays: str | None = Field(default=None, max_length=12000)
    schedule_weekends: str | None = Field(default=None, max_length=12000)
    stops_text: str | None = Field(default=None, max_length=8000)
    days_mode: str | None = Field(default=None, pattern="^(all|weekdays|weekends)$")
    notes: str | None = Field(default=None, max_length=2000)
    fare_text: str | None = Field(default=None, max_length=120)
    phone: str | None = Field(default=None, max_length=32)
    settlement_id: int | None = None
    is_published: bool | None = None


class TransportOut(BaseModel):
    id: int
    title: str
    route_number: str | None
    description: str | None
    schedule_text: str
    schedule_weekdays: str | None = None
    schedule_weekends: str | None = None
    stops_text: str | None = None
    stops: list[str] = []
    days_mode: str = "all"
    notes: str | None
    fare_text: str | None = None
    phone: str | None = None
    next_departure: str | None = None
    settlement_id: int | None
    settlement_name: str | None = None
    is_published: bool
    is_favorited: bool = False
    view_count: int = 0
    favorite_count: int = 0
    outdated_reports: int = 0
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class NewsCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    body: str = Field(min_length=3, max_length=12000)
    settlement_id: int | None = None
    is_published: bool = True
    is_pinned: bool = False
    published_at: datetime | None = None


class NewsUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    body: str | None = Field(default=None, min_length=3, max_length=12000)
    settlement_id: int | None = None
    is_published: bool | None = None
    is_pinned: bool | None = None
    published_at: datetime | None = None


class NewsOut(BaseModel):
    id: int
    title: str
    body: str
    cover_url: str | None = None
    settlement_id: int | None
    settlement_name: str | None = None
    is_published: bool
    is_pinned: bool = False
    published_at: datetime | None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class AlertCreate(BaseModel):
    message: str = Field(min_length=3, max_length=280)
    kind: str = Field(default="info", pattern="^(info|warn|danger)$")
    priority: int = Field(default=0, ge=0, le=100)
    is_active: bool = True
    starts_at: datetime | None = None
    ends_at: datetime | None = None


class AlertUpdate(BaseModel):
    message: str | None = Field(default=None, min_length=3, max_length=280)
    kind: str | None = Field(default=None, pattern="^(info|warn|danger)$")
    priority: int | None = Field(default=None, ge=0, le=100)
    is_active: bool | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None


class AlertOut(BaseModel):
    id: int
    message: str
    kind: str
    priority: int = 0
    is_active: bool
    starts_at: datetime | None
    ends_at: datetime | None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ListingMessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=2000)
    peer_id: int | None = None  # id покупателя — обязательно, если пишет продавец


class ListingMessageOut(BaseModel):
    id: int
    listing_id: int
    sender_id: int
    sender_name: str | None = None
    peer_id: int | None = None
    body: str
    is_read: bool
    created_at: datetime
    is_mine: bool = False


class ConversationOut(BaseModel):
    listing_id: int
    peer_id: int
    listing_title: str
    listing_status: str
    peer_name: str | None = None
    last_message: str | None = None
    last_message_at: datetime | None = None
    unread_count: int = 0
    is_seller: bool = False


class AdminConversationOut(BaseModel):
    listing_id: int
    buyer_id: int
    listing_title: str
    listing_status: str
    seller_id: int
    seller_name: str | None = None
    buyer_name: str | None = None
    last_message: str | None = None
    last_message_at: datetime | None = None
    message_count: int = 0
    flagged: bool = False
    flag_reasons: list[str] = []


class AdminChatMessageOut(BaseModel):
    id: int
    listing_id: int
    buyer_id: int | None
    sender_id: int
    sender_name: str | None = None
    body: str
    created_at: datetime
    flagged: bool = False
    flag_reasons: list[str] = []


class AuthorReportOut(BaseModel):
    id: int
    listing_id: int
    listing_title: str | None = None
    reason: str
    note: str | None
    status: str
    moderator_reply: str | None
    created_at: datetime
    reviewed_at: datetime | None = None


class StatsOut(BaseModel):
    users: int
    listings_pending: int
    listings_approved: int
    directory_items: int
    settlements: int
    pending_over_24h: int = 0
    open_reports: int = 0
    moderated_approved_30d: int = 0
    moderated_rejected_30d: int = 0
    moderation_conversion: float | None = None
    listings_per_day: list[DayStat] = []
    top_categories: list[CategoryStat] = []
    events_total: int = 0
    events_upcoming: int = 0
    transport_routes: int = 0
    news_total: int = 0
    active_alerts: int = 0
    top_events: list[dict] = []
    top_routes: list[dict] = []
    transport_favorites_total: int = 0
    listing_favorites_total: int = 0
    directory_favorites_total: int = 0
    event_favorite_adds_total: int = 0
    by_settlement: list[SettlementStat] = []
    open_directory_reports: int = 0


class AdminAlertsOut(BaseModel):
    pending: int
    pending_over_24h: int
    open_reports: int


class BlacklistCreate(BaseModel):
    kind: str = Field(pattern="^(phone|word)$")
    value: str = Field(min_length=1, max_length=200)
    note: str | None = Field(default=None, max_length=255)


class BlacklistOut(BaseModel):
    id: int
    kind: str
    value: str
    note: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class ListingPinIn(BaseModel):
    pinned: bool = True


class NotificationOut(BaseModel):
    id: int
    type: str
    title: str
    body: str | None
    listing_id: int | None
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True


class AppUpdateOut(BaseModel):
    version: str
    build: int
    force: bool = False
    notes: str | None = None
    has_apk: bool = False
    download_url: str | None = None
    published_at: datetime | None = None


class AppUpdateAdminOut(AppUpdateOut):
    apk_filename: str | None = None
    apk_size: int | None = None


class AppUpdatePatch(BaseModel):
    version_name: str | None = Field(default=None, min_length=1, max_length=40)
    version_code: int | None = Field(default=None, ge=1)
    force_update: bool | None = None
    notes: str | None = Field(default=None, max_length=4000)
