from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import admin_panel, auth, directory, legal, listings, settlements
from app.core.config import settings
from app.core.database import SessionLocal
from app.services.seed import init_db, seed_db


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    with SessionLocal() as session:
        seed_db(session)
    yield


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)

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
app.include_router(legal.router, prefix="/api")
app.include_router(admin_panel.router, prefix="/api")


@app.get("/api/health")
async def health():
    return {"status": "ok", "app": settings.app_name}
