from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import require_roles
from app.core.database import get_db
from app.models import AppUpdate, User, UserRole
from app.schemas import AppUpdateAdminOut, AppUpdateOut, AppUpdatePatch
from app.services.audit import log_action

router = APIRouter(prefix="/app", tags=["app"])

RELEASES_DIR = Path("data/releases")
APK_NAME = "ryadom56-latest.apk"
MAX_APK_BYTES = 120 * 1024 * 1024


def apk_path() -> Path:
    return RELEASES_DIR / APK_NAME


def get_or_create_settings(db: Session) -> AppUpdate:
    row = db.execute(select(AppUpdate).where(AppUpdate.id == 1)).scalar_one_or_none()
    if row is None:
        row = AppUpdate(
            id=1,
            version_name="0.11.0",
            version_code=12,
            force_update=False,
            notes="Текущая версия приложения",
            apk_filename=None,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


def to_public(row: AppUpdate) -> AppUpdateOut:
    has_apk = bool(row.apk_filename and apk_path().is_file())
    return AppUpdateOut(
        version=row.version_name,
        build=row.version_code,
        force=row.force_update,
        notes=row.notes,
        has_apk=has_apk,
        download_url="/api/app/apk" if has_apk else None,
        published_at=row.updated_at,
    )


def to_admin(row: AppUpdate) -> AppUpdateAdminOut:
    public = to_public(row)
    return AppUpdateAdminOut(
        **public.model_dump(),
        apk_filename=row.apk_filename,
        apk_size=apk_path().stat().st_size if public.has_apk else None,
    )


@router.get("/update", response_model=AppUpdateOut)
def get_app_update(db: Session = Depends(get_db)):
    return to_public(get_or_create_settings(db))


@router.get("/apk")
def download_apk(db: Session = Depends(get_db)):
    row = get_or_create_settings(db)
    path = apk_path()
    if not row.apk_filename or not path.is_file():
        raise HTTPException(status_code=404, detail="APK ещё не загружен на сервер")
    return FileResponse(
        path,
        media_type="application/vnd.android.package-archive",
        filename=row.apk_filename or APK_NAME,
        headers={"Cache-Control": "no-cache"},
    )


@router.get("/update/admin", response_model=AppUpdateAdminOut)
def get_app_update_admin(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(UserRole.admin)),
):
    return to_admin(get_or_create_settings(db))


@router.patch("/update", response_model=AppUpdateAdminOut)
def patch_app_update(
    payload: AppUpdatePatch,
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    row = get_or_create_settings(db)
    data = payload.model_dump(exclude_unset=True)
    for key, value in data.items():
        setattr(row, key, value)
    log_action(
        db,
        actor=user,
        action="app_update.patch",
        entity_type="app_update",
        entity_id=1,
        details=f"{row.version_name}+{row.version_code}",
    )
    db.commit()
    db.refresh(row)
    return to_admin(row)


@router.post("/apk", response_model=AppUpdateAdminOut)
async def upload_apk(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(require_roles(UserRole.admin)),
):
    name = (file.filename or "").lower()
    if not name.endswith(".apk"):
        raise HTTPException(status_code=400, detail="Нужен файл .apk")
    RELEASES_DIR.mkdir(parents=True, exist_ok=True)
    dest = apk_path()
    size = 0
    with dest.open("wb") as out:
        while True:
            chunk = await file.read(1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            if size > MAX_APK_BYTES:
                out.close()
                dest.unlink(missing_ok=True)
                raise HTTPException(status_code=400, detail="APK слишком большой (макс. 120 МБ)")
            out.write(chunk)
    row = get_or_create_settings(db)
    row.apk_filename = file.filename or APK_NAME
    log_action(
        db,
        actor=user,
        action="app_update.apk_upload",
        entity_type="app_update",
        entity_id=1,
        details=f"{row.apk_filename} ({size} bytes)",
    )
    db.commit()
    db.refresh(row)
    return to_admin(row)
