from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import Settlement
from app.schemas import SettlementOut

router = APIRouter(prefix="/settlements", tags=["settlements"])


@router.get("", response_model=list[SettlementOut])
def list_settlements(db: Session = Depends(get_db)):
    return db.execute(
        select(Settlement).where(Settlement.is_active.is_(True)).order_by(Settlement.sort_order, Settlement.display_name)
    ).scalars().all()
