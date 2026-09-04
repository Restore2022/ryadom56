from contextlib import asynccontextmanager
from pathlib import Path
import struct
import zlib

from fastapi import FastAPI, HTTPException
from datetime import datetime, timezone

from fastapi.encoders import ENCODERS_BY_TYPE
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.responses import FileResponse, Response

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
    geo,
    legal,
    listings,
    news,
    share,
    search,
    promo,
    notifications,
    push,
    rides,
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


def _placeholder_png() -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    pixel = b"\x00\xc0\xc0\xc0"
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(pixel, 9))
        + chunk(b"IEND", b"")
    )


_PLACEHOLDER_PNG = _placeholder_png()


class SoftUploads(StaticFiles):
    async def get_response(self, path: str, scope):
        try:
            resp = await super().get_response(path, scope)
            if getattr(resp, "status_code", 200) == 200:
                resp.headers.setdefault("Cache-Control", "public, max-age=2592000")
            return resp
        except StarletteHTTPException as exc:
            if exc.status_code != 404:
                raise
            if not path.lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".gif")):
                raise
            return Response(
                content=_PLACEHOLDER_PNG,
                media_type="image/png",
                headers={"Cache-Control": "no-store"},
            )


@asynccontextmanager
async def lifespan(_: FastAPI):
    Path("data/uploads").mkdir(parents=True, exist_ok=True)
    Path("data/uploads/avatars").mkdir(parents=True, exist_ok=True)
    Path("data/thumbs").mkdir(parents=True, exist_ok=True)
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
app.include_router(search.router, prefix="/api")
app.include_router(directory.router, prefix="/api")
app.include_router(events.router, prefix="/api")
app.include_router(geo.router, prefix="/api")
app.include_router(transport.router, prefix="/api")
app.include_router(rides.router, prefix="/api")
app.include_router(news.router, prefix="/api")
app.include_router(alerts.router, prefix="/api")
app.include_router(legal.router, prefix="/api")
app.include_router(legal.public_router)
app.include_router(share.router)
app.include_router(promo.public_router)
app.include_router(notifications.router, prefix="/api")
app.include_router(app_update.router, prefix="/api")
app.include_router(calls.router, prefix="/api")
app.include_router(calls.admin_calls_router, prefix="/api")
app.include_router(admin_panel.router, prefix="/api")
app.include_router(promo.admin_router, prefix="/api")
app.include_router(client_errors.router, prefix="/api")
app.include_router(contact.router, prefix="/api")
app.include_router(presence.router, prefix="/api")
app.include_router(push.router, prefix="/api")
app.mount("/uploads", SoftUploads(directory="data/uploads"), name="uploads")


@app.get("/t/{width}/{path:path}")
def serve_card_thumb(width: int, path: str):
    from app.services.card_image import CACHE_HEADERS, card_thumb

    dest = card_thumb(width, path)
    if dest is None:
        raise HTTPException(status_code=404)
    return FileResponse(dest, media_type="image/webp", headers=CACHE_HEADERS)


@app.get("/api/health")
async def health():
    return {"status": "ok", "app": settings.app_name, "turn": turn_configured()}
