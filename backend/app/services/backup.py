"""SQLite snapshots: keep the last 7 files in data/backups."""
from __future__ import annotations

import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from shutil import disk_usage

from app.core.config import settings

KEEP = 7
NAME_RE = re.compile(r"^ryadom56-\d{8}-\d{4}\.db$")


def _db_path() -> Path:
    raw = settings.database_url.replace("sqlite:///", "")
    path = Path(raw)
    if not path.is_absolute():
        path = Path.cwd() / path
    return path


def backup_dir() -> Path:
    path = _db_path().parent / "backups"
    path.mkdir(parents=True, exist_ok=True)
    return path


def list_backup_files() -> list[Path]:
    files = [p for p in backup_dir().glob("ryadom56-*.db") if p.is_file() and NAME_RE.match(p.name)]
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return files


def prune_backups(keep: int = KEEP) -> None:
    for old in list_backup_files()[keep:]:
        try:
            old.unlink()
        except OSError:
            pass


def create_backup() -> Path:
    src = _db_path()
    if not src.exists():
        raise FileNotFoundError("database file missing")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M")
    dest = backup_dir() / f"ryadom56-{stamp}.db"
    src_conn = sqlite3.connect(f"file:{src.as_posix()}?mode=ro", uri=True)
    try:
        dst_conn = sqlite3.connect(dest.as_posix())
        try:
            src_conn.backup(dst_conn)
        finally:
            dst_conn.close()
    finally:
        src_conn.close()
    prune_backups()
    return dest


def ensure_daily_backup(max_age_hours: float = 20) -> Path | None:
    files = list_backup_files()
    if files:
        age_h = (datetime.now().timestamp() - files[0].stat().st_mtime) / 3600
        if age_h < max_age_hours:
            return files[0]
    try:
        return create_backup()
    except Exception:
        return files[0] if files else None


def disk_info() -> dict:
    root = _db_path().parent
    usage = disk_usage(str(root))
    data_bytes = 0
    db_file = _db_path()
    if db_file.is_file():
        data_bytes += db_file.stat().st_size
    for p in list_backup_files():
        try:
            data_bytes += p.stat().st_size
        except OSError:
            pass
    return {
        "disk_free_mb": round(usage.free / (1024 * 1024)),
        "disk_total_mb": round(usage.total / (1024 * 1024)),
        "data_dir_mb": round(data_bytes / (1024 * 1024), 1),
    }


def backup_meta(path: Path) -> dict:
    st = path.stat()
    return {
        "name": path.name,
        "size": st.st_size,
        "created_at": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat().replace("+00:00", "Z"),
    }


if __name__ == "__main__":
    p = create_backup()
    print(p.name, p.stat().st_size)
