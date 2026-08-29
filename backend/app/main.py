from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from datetime import datetime, timezone

from fastapi.encoders import ENCODERS_BY_TYPE
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api import (
    admin_panel,
    alerts,
    app_update,
    auth,
    calls,
    client_errors,
    contact,
    directory,
    presence,
    events,
    legal,
    listings,
    news,
    share,
    notifications,
    settlements,
    transport,
)
from app.core.config import settings
from app.core.database import SessionLocal
from app.services.call_hub import hub
from app.services.seed import init_db, seed_db
from app.services.turn import turn_configured


def _json_utc(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    iso = value.astimezone(timezone.utc).isoformat()
    return iso[:-6] + "Z" if iso.endswith("+00:00") else iso


ENCODERS_BY_TYPE[datetime] = _json_utc


@asynccontextmanager
async def lifespan(_: FastAPI):
    Path("data/uploads").mkdir(parents=True, exist_ok=True)
    Path("data/uploads/avatars").mkdir(parents=True, exist_ok=True)
    init_db()
    with SessionLocal() as session:
        seed_db(session)
    import asyncio

    hub.bind_loop(asyncio.get_running_loop())
    yield


app = FastAPI(title=settings.app_name, version="0.11.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins + ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api")
app.include_router(settlements.router, prefix="/api")
app.include_router(listings.router, prefix="/api")
app.include_router(directory.router, prefix="/api")
app.include_router(events.router, prefix="/api")
app.include_router(transport.router, prefix="/api")
app.include_router(news.router, prefix="/api")
app.include_router(alerts.router, prefix="/api")
app.include_router(legal.router, prefix="/api")
app.include_router(legal.public_router)
app.include_router(share.router)
app.include_router(notifications.router, prefix="/api")
app.include_router(app_update.router, prefix="/api")
app.include_router(calls.router, prefix="/api")
app.include_router(calls.admin_calls_router, prefix="/api")
app.include_router(admin_panel.router, prefix="/api")
app.include_router(client_errors.router, prefix="/api")
app.include_router(contact.router, prefix="/api")
app.include_router(presence.router, prefix="/api")
app.mount("/uploads", StaticFiles(directory="data/uploads"), name="uploads")


@app.get("/api/health")
async def health():
    return {"status": "ok", "app": settings.app_name, "turn": turn_configured()}
