from math import asin, cos, radians, sin, sqrt

from sqlalchemy.orm import Session

from app.models import Settlement


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1, p2 = radians(lat1), radians(lat2)
    dphi = radians(lat2 - lat1)
    dlmb = radians(lon2 - lon1)
    a = sin(dphi / 2) ** 2 + cos(p1) * cos(p2) * sin(dlmb / 2) ** 2
    return 2 * r * asin(sqrt(min(1.0, a)))


def resolve_origin(
    db: Session,
    lat: float | None,
    lon: float | None,
    settlement_id: int | None,
) -> tuple[float, float] | None:
    if lat is not None and lon is not None:
        return float(lat), float(lon)
    if settlement_id is None:
        return None
    row = db.get(Settlement, settlement_id)
    if row is None or row.lat is None or row.lon is None:
        return None
    return float(row.lat), float(row.lon)
