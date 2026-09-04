from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, aliased, selectinload

from app.api.deps import get_optional_user
from app.api.directory import favorite_ids_for as place_favs
from app.api.directory import to_out as place_out
from app.api.listings import favorite_ids_for as listing_favs
from app.api.listings import to_out as listing_out
from app.api.news import news_visible_clause
from app.api.news import to_out as news_out
from app.api.rides import to_out as ride_out
from app.core.database import get_db
from app.models import DirectoryItem, DistrictNews, Listing, ListingStatus, Ride, Settlement, User
from app.schemas import SearchOut

router = APIRouter(prefix="/search", tags=["search"])

_RIDE_WORDS = {"еду", "ищу", "попутка", "попутки", "попутчик", "машина"}


@router.get("", response_model=SearchOut)
def search_all(
    q: str = Query(..., min_length=1, max_length=80),
    settlement_id: int | None = None,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    needle = q.strip()
    if not needle:
        return SearchOut()
    like = f"%{needle}%"

    listing_filters = [
        Listing.status == ListingStatus.approved,
        Listing.title.ilike(like) | Listing.description.ilike(like),
    ]
    if settlement_id:
        listing_filters.append(Listing.settlement_id == settlement_id)
    listings = (
        db.execute(
            select(Listing)
            .options(selectinload(Listing.author), selectinload(Listing.settlement), selectinload(Listing.images))
            .where(*listing_filters)
            .order_by(Listing.created_at.desc())
            .limit(8)
        )
        .scalars()
        .all()
    )
    lfav = listing_favs(db, user)

    place_filters = [
        DirectoryItem.is_published.is_(True),
        or_(
            DirectoryItem.title.ilike(like),
            DirectoryItem.description.ilike(like),
            DirectoryItem.address.ilike(like),
            DirectoryItem.phone.ilike(like),
        ),
    ]
    if settlement_id:
        place_filters.append(DirectoryItem.settlement_id == settlement_id)
    places = (
        db.execute(
            select(DirectoryItem)
            .options(selectinload(DirectoryItem.settlement))
            .where(*place_filters)
            .order_by(DirectoryItem.title.asc())
            .limit(8)
        )
        .scalars()
        .all()
    )
    pfav = place_favs(db, user)

    news_filters = [
        DistrictNews.is_published.is_(True),
        DistrictNews.title.ilike(like) | DistrictNews.body.ilike(like),
        news_visible_clause(db, settlement_id),
    ]
    news = (
        db.execute(
            select(DistrictNews)
            .options(selectinload(DistrictNews.settlement), selectinload(DistrictNews.images))
            .where(*news_filters)
            .order_by(DistrictNews.created_at.desc())
            .limit(8)
        )
        .scalars()
        .all()
    )

    now = datetime.now(timezone.utc)
    from_s = aliased(Settlement)
    to_s = aliased(Settlement)
    ride_match = needle.casefold() in _RIDE_WORDS
    text_match = or_(
        Ride.note.ilike(like),
        from_s.name.ilike(like),
        from_s.display_name.ilike(like),
        to_s.name.ilike(like),
        to_s.display_name.ilike(like),
    )
    ride_stmt = (
        select(Ride)
        .options(selectinload(Ride.author), selectinload(Ride.from_place), selectinload(Ride.to_place))
        .join(from_s, from_s.id == Ride.from_settlement_id)
        .join(to_s, to_s.id == Ride.to_settlement_id)
        .where(
            Ride.status == "open",
            Ride.depart_at >= now - timedelta(hours=2),
        )
        .order_by(Ride.depart_at.asc())
        .limit(8)
    )
    if not ride_match:
        ride_stmt = ride_stmt.where(text_match)
    if settlement_id:
        ride_stmt = ride_stmt.where(
            or_(Ride.from_settlement_id == settlement_id, Ride.to_settlement_id == settlement_id)
        )
    rides = db.execute(ride_stmt).scalars().unique().all()

    return SearchOut(
        listings=[listing_out(item, lfav, viewer=user) for item in listings],
        places=[place_out(item, pfav) for item in places],
        news=[news_out(item) for item in news],
        rides=[ride_out(item, viewer=user) for item in rides],
    )
