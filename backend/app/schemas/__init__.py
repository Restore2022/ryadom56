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

    class Config:
        from_attributes = True


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


class ListingCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    description: str = Field(min_length=3, max_length=5000)
    category: ListingCategory
    settlement_id: int
    price: float | None = None
    contact_phone: str | None = Field(default=None, max_length=32)


class ListingUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    description: str | None = Field(default=None, min_length=3, max_length=5000)
    category: ListingCategory | None = None
    settlement_id: int | None = None
    price: float | None = None
    contact_phone: str | None = None


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


class ListingOut(BaseModel):
    id: int
    author_id: int
    author_name: str | None = None
    settlement_id: int
    settlement_name: str | None = None
    category: ListingCategory
    title: str
    description: str
    price: float | None
    contact_phone: str | None
    status: ListingStatus
    moderation_note: str | None
    close_reason: str | None = None
    close_note: str | None = None
    images: list[ListingImageOut] = []
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class DirectoryCreate(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    category: DirectoryCategory
    settlement_id: int | None = None
    description: str | None = None
    address: str | None = None
    phone: str | None = None
    website: str | None = None
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
    lat: float | None
    lon: float | None
    is_published: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


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


class DeviceInfoIn(BaseModel):
    device_brand: str | None = Field(default=None, max_length=80)
    device_model: str | None = Field(default=None, max_length=120)
    device_os: str | None = Field(default=None, max_length=80)
    app_version: str | None = Field(default=None, max_length=40)
    device_info: str | None = Field(default=None, max_length=2000)


class StatsOut(BaseModel):
    users: int
    listings_pending: int
    listings_approved: int
    directory_items: int
    settlements: int
