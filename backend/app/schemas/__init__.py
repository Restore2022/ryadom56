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
    wanted = "wanted"
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
    lat: float | None = None
    lon: float | None = None

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
    ban_reason: str | None = None
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
    has_push: bool = False
    avatar_url: str | None = None

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
    avatar_url: str | None = None


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
    lifetime_days: int = Field(default=30, ge=30, le=60)


class ListingUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    description: str | None = Field(default=None, min_length=3, max_length=5000)
    category: ListingCategory | None = None
    settlement_id: int | None = None
    price: float | None = Field(default=None, ge=0)
    contact_phone: str | None = None
    is_urgent: bool | None = None
    as_draft: bool | None = None
    lifetime_days: int | None = Field(default=None, ge=30, le=60)


class LegalUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    body: str | None = Field(default=None, min_length=10)
    version: str | None = Field(default=None, max_length=32)


class ListingModerationIn(BaseModel):
    status: ListingStatus
    moderation_note: str | None = None


class ListingAdminStatusIn(BaseModel):
    status: ListingStatus
    moderation_note: str | None = None
    close_reason: str | None = Field(default=None, max_length=40)
    close_note: str | None = Field(default=None, max_length=500)


class ListingCloseIn(BaseModel):
    reason: str = Field(pattern="^(sold|not_relevant|busy|other)$")
    note: str | None = Field(default=None, max_length=500)


class ListingExtendIn(BaseModel):
    days: int = Field(default=30, ge=30, le=60)


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
    distance_km: float | None = None
    lifetime_days: int = 30
    expires_at: datetime | None = None
    ask_if_relevant: bool = False

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


class UserReportIn(BaseModel):
    reason: str = Field(pattern="^(spam|fraud|prohibited|abuse|other)$")
    note: str | None = Field(default=None, max_length=500)
    listing_id: int | None = None


class UserReportOut(BaseModel):
    id: int
    target_id: int
    target_name: str | None = None
    reporter_id: int
    reporter_name: str | None = None
    listing_id: int | None = None
    listing_title: str | None = None
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
    actor_role: str | None = None
    action: str
    entity_type: str
    entity_id: int | None
    details: str | None
    created_at: datetime


class AuditLogPageOut(BaseModel):
    items: list[AuditLogOut]
    total: int
    limit: int
    offset: int


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
    distance_km: float | None = None

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


class AdminPushIn(BaseModel):
    title: str = Field(default="Рядом56", max_length=80)
    body: str = Field(min_length=1, max_length=400)


class AdminPushOut(BaseModel):
    ok: bool = True
    notification_id: int
    devices: int = 0
    message: str


class BroadcastIn(BaseModel):
    title: str = Field(default="", max_length=80)
    body: str = Field(min_length=3, max_length=400)
    kind: str = Field(default="info", max_length=20)
    audience: str = Field(default="all", pattern=r"^(all|users|guests)$")


class BroadcastPreviewOut(BaseModel):
    people: int
    devices: int
    user_devices: int = 0
    guest_devices: int = 0


class BroadcastOut(BaseModel):
    ok: bool = True
    people: int
    devices: int
    guest_devices: int = 0
    sent: int = 0
    message: str


class GuestPushIn(BaseModel):
    device_id: str = Field(min_length=16, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    fcm_token: str = Field(min_length=20, max_length=512)
    app_version: str | None = Field(default=None, max_length=40)
    settlement_id: int | None = None


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


class EventPageOut(BaseModel):
    items: list[EventOut]
    total: int
    limit: int
    offset: int


class TransportStopPointOut(BaseModel):
    id: int
    name: str


class TransportStopCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    settlement_id: int | None = None


class TransportStopUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    settlement_id: int | None = None


class TransportStopOut(BaseModel):
    id: int
    name: str
    settlement_id: int | None = None
    created_at: datetime

    class Config:
        from_attributes = True


class TransportTripIn(BaseModel):
    depart: str
    arrive: str | None = None
    days: list[str] = Field(min_length=1, max_length=7)


class TransportTripOut(BaseModel):
    depart: str
    arrive: str | None = None
    days: list[str]
    days_label: str


class TransportCreate(BaseModel):
    stop_ids: list[int] = Field(min_length=2, max_length=40)
    trips: list[TransportTripIn] | None = Field(default=None, min_length=1, max_length=80)
    times: list[str] | None = Field(default=None, min_length=1, max_length=80)
    description: str | None = Field(default=None, max_length=4000)
    notes: str | None = Field(default=None, max_length=2000)
    fare_text: str | None = Field(default=None, max_length=120)
    phone: str | None = Field(default=None, max_length=32)
    settlement_id: int | None = None
    is_published: bool = True


class TransportUpdate(BaseModel):
    stop_ids: list[int] | None = Field(default=None, min_length=2, max_length=40)
    trips: list[TransportTripIn] | None = Field(default=None, min_length=1, max_length=80)
    times: list[str] | None = Field(default=None, min_length=1, max_length=80)
    description: str | None = Field(default=None, max_length=4000)
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
    stop_points: list[TransportStopPointOut] = []
    times: list[str] = []
    trips: list[TransportTripOut] = []
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


class TransportPageOut(BaseModel):
    items: list[TransportOut]
    total: int
    limit: int
    offset: int


class NewsPhotoOut(BaseModel):
    id: int
    url: str
    sort_order: int


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
    photos: list[NewsPhotoOut] = []
    settlement_id: int | None
    settlement_name: str | None = None
    is_published: bool
    is_pinned: bool = False
    published_at: datetime | None
    source: str | None = None
    source_url: str | None = None
    audience: str = "oblast"
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class SearchOut(BaseModel):
    listings: list[ListingOut] = []
    places: list[DirectoryOut] = []
    news: list[NewsOut] = []
    rides: list["RideOut"] = []


class VkNewsRunOut(BaseModel):
    id: int
    started_at: datetime
    finished_at: datetime | None
    status: str
    source: str
    fetched: int
    created: int
    skipped: int
    photos: int
    details: str | None
    error: str | None
    triggered_by: str

    class Config:
        from_attributes = True


class VkNewsRunPageOut(BaseModel):
    items: list[VkNewsRunOut]
    total: int
    limit: int
    offset: int


class NewsPageOut(BaseModel):
    items: list[NewsOut]
    total: int
    limit: int
    offset: int


class AlertCreate(BaseModel):
    message: str = Field(min_length=3, max_length=280)
    kind: str = Field(default="info", pattern="^(info|warn|danger)$")
    priority: int = Field(default=0, ge=0, le=100)
    is_active: bool = True
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    settlement_ids: list[int] = Field(default_factory=list)


class AlertUpdate(BaseModel):
    message: str | None = Field(default=None, min_length=3, max_length=280)
    kind: str | None = Field(default=None, pattern="^(info|warn|danger)$")
    priority: int | None = Field(default=None, ge=0, le=100)
    is_active: bool | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    settlement_ids: list[int] | None = None


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
    settlement_ids: list[int] = Field(default_factory=list)
    settlement_names: list[str] = Field(default_factory=list)

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
    kind: str = "text"
    call_id: int | None = None
    image_url: str | None = None


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
    last_kind: str = "text"


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
    kind: str = "text"
    is_read: bool = False
    image_url: str | None = None


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
    rides_open: int = 0
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
    open_contacts: int = 0
    online_site: int = 0
    online_app: int = 0
    online_app_users: int = 0
    online_app_guests: int = 0
    users_new_7d: int = 0
    users_new_today: int = 0
    users_older: int = 0
    users_active_30d: int = 0
    online_calls: int = 0
    site_today: int = 0
    app_guests_today: int = 0
    promo_visits_today: int = 0
    promo_downloads_today: int = 0
    apk_downloads_total: int = 0
    apk_downloads_unique: int = 0
    apk_downloads_today: int = 0


class AdminAlertsOut(BaseModel):
    pending: int
    pending_over_24h: int
    open_reports: int
    open_contacts: int = 0
    unread_client_errors: int = 0


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


class SiteContactOut(BaseModel):
    id: int
    name: str
    settlement: str | None = None
    phone: str | None = None
    message: str
    ip: str | None = None
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class SiteContactPageOut(BaseModel):
    items: list[SiteContactOut]
    total: int
    limit: int
    offset: int


class SiteContactPatch(BaseModel):
    status: str = Field(pattern="^(new|read|done)$")


class BackupFileOut(BaseModel):
    name: str
    size: int
    created_at: str


class BackupListOut(BaseModel):
    items: list[BackupFileOut]
    disk_free_mb: int = 0
    disk_total_mb: int = 0
    data_dir_mb: float = 0


class HostMetricsOut(BaseModel):
    cpu_percent: float = 0
    cpu_count: int = 1
    ram_used_mb: int = 0
    ram_total_mb: int = 0
    ram_percent: float = 0
    disk_used_bytes: int = 0
    disk_total_bytes: int = 0
    disk_percent: float = 0
    cpu_warn: bool = False
    ram_warn: bool = False
    disk_warn: bool = False


class ListingPinIn(BaseModel):
    pinned: bool = True


class NotificationOut(BaseModel):
    id: int
    type: str
    title: str
    body: str | None
    listing_id: int | None
    ride_id: int | None = None
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True


class RideCreate(BaseModel):
    kind: str = Field(pattern="^(drive|need)$")
    from_settlement_id: int
    to_settlement_id: int
    depart_at: datetime
    seats: int = Field(default=1, ge=1, le=8)
    note: str | None = Field(default=None, max_length=400)
    contact_phone: str | None = Field(default=None, max_length=32)


class RideUpdate(BaseModel):
    depart_at: datetime | None = None
    seats: int | None = Field(default=None, ge=1, le=8)
    note: str | None = Field(default=None, max_length=400)
    contact_phone: str | None = Field(default=None, max_length=32)


class RideCloseIn(BaseModel):
    reason: str = Field(pattern="^(full|cancelled|gone|other)$")


class RideOut(BaseModel):
    id: int
    kind: str
    from_settlement_id: int
    to_settlement_id: int
    from_name: str
    to_name: str
    title: str
    depart_at: datetime
    seats: int
    note: str | None = None
    status: str
    close_reason: str | None = None
    author_id: int
    author_name: str | None = None
    author_avatar_url: str | None = None
    contact_phone: str | None = None
    phone_hidden: bool = False
    is_mine: bool = False
    created_at: datetime


class RidePageOut(BaseModel):
    items: list[RideOut]
    total: int
    limit: int
    offset: int


class RideMessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=2000)
    peer_id: int | None = None


class RideMessageOut(BaseModel):
    id: int
    ride_id: int
    sender_id: int
    sender_name: str | None = None
    peer_id: int | None = None
    body: str
    is_read: bool
    created_at: datetime
    is_mine: bool = False


class RideConversationOut(BaseModel):
    ride_id: int
    peer_id: int
    title: str
    ride_status: str
    peer_name: str | None = None
    last_message: str | None = None
    last_message_at: datetime | None = None
    unread_count: int = 0
    is_driver: bool = False


class RideReportIn(BaseModel):
    reason: str = Field(pattern="^(spam|fraud|other)$")
    note: str | None = Field(default=None, max_length=500)


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


class CallCreateIn(BaseModel):
    listing_id: int
    callee_id: int | None = None


class CallActionIn(BaseModel):
    reason: str | None = Field(default=None, max_length=80)


class CallOut(BaseModel):
    id: int
    listing_id: int
    listing_title: str | None = None
    caller_id: int
    caller_name: str | None = None
    callee_id: int
    callee_name: str | None = None
    status: str
    created_at: datetime
    answered_at: datetime | None = None
    ended_at: datetime | None = None
    duration_sec: int = 0
    end_reason: str | None = None
    ended_by_id: int | None = None
    ended_by_name: str | None = None
    callee_online: bool = False
    callee_has_push: bool = False
    gsm_fallback: bool = False
    gsm_phone: str | None = None
    ring_timeout_sec: int = 40


class CallPageOut(BaseModel):
    items: list[CallOut]
    total: int
    limit: int
    offset: int


class ClientErrorIn(BaseModel):
    message: str = Field(min_length=1, max_length=500)
    stack: str | None = Field(default=None, max_length=8000)
    screen: str | None = Field(default=None, max_length=120)
    app_version: str | None = Field(default=None, max_length=40)
    device_brand: str | None = Field(default=None, max_length=80)
    device_model: str | None = Field(default=None, max_length=120)
    device_os: str | None = Field(default=None, max_length=80)


class ClientErrorOut(BaseModel):
    id: int
    created_at: datetime
    user_id: int | None = None
    user_name: str | None = None
    message: str
    stack: str | None = None
    screen: str | None = None
    app_version: str | None = None
    device_brand: str | None = None
    device_model: str | None = None
    device_os: str | None = None
    client_ip: str | None = None
    is_read: bool = False

    class Config:
        from_attributes = True


class ClientErrorPatch(BaseModel):
    is_read: bool


class ClientErrorPageOut(BaseModel):
    items: list[ClientErrorOut]
    total: int
    limit: int
    offset: int
    unread_count: int = 0


class PromoLinkCreate(BaseModel):
    title: str = Field(min_length=2, max_length=120)
    slug: str = Field(min_length=2, max_length=32, pattern=r"^[a-z0-9][a-z0-9_-]*$")
    note: str | None = Field(default=None, max_length=255)


class PromoLinkPatch(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=120)
    note: str | None = Field(default=None, max_length=255)
    is_active: bool | None = None


class PromoLinkOut(BaseModel):
    id: int
    slug: str
    title: str
    note: str | None = None
    is_active: bool = True
    url: str
    created_at: datetime
    visits: int = 0
    visits_unique: int = 0
    visits_today: int = 0
    downloads: int = 0
    downloads_unique: int = 0
    downloads_today: int = 0

    class Config:
        from_attributes = True


SearchOut.model_rebuild()
