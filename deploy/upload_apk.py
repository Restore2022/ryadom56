"""Upload local APK to VPS releases dir and mark AppUpdate."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import paramiko

HOST = "155.212.174.201"
PASS = os.environ.get("RYADOM_SSH_PASS", "")
if not PASS:
    raise SystemExit("Set RYADOM_SSH_PASS env var")

REMOTE = "/opt/ryadom56"
REMOTE_APK = f"{REMOTE}/backend/data/releases/ryadom56-latest.apk"
LOCAL_APK = Path(__file__).resolve().parents[1] / "mobile" / "apk" / "app-release.apk"
VERSION_NAME = "0.25.0"
VERSION_CODE = 39
APK_FILENAME = "ryadom56-0.25.0.apk"


def run(c: paramiko.SSHClient, cmd: str, timeout: int = 120) -> str:
    print(">", cmd[:200])
    _, so, se = c.exec_command(cmd, timeout=timeout)
    out = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    code = so.channel.recv_exit_status()
    text = (out + ("\n" + err if err.strip() else "")).encode("ascii", "replace").decode()
    if text.strip():
        print(text[-3000:])
    if code != 0:
        raise SystemExit(f"fail {code}: {cmd}")
    return out


def main() -> None:
    if not LOCAL_APK.is_file():
        raise SystemExit(f"Missing APK: {LOCAL_APK}")
    size = LOCAL_APK.stat().st_size
    print(f"Local APK: {LOCAL_APK} ({size} bytes)")

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASS, timeout=60, allow_agent=False, look_for_keys=False)
    transport = c.get_transport()
    if transport:
        transport.set_keepalive(15)

    run(c, f"mkdir -p {REMOTE}/backend/data/releases")
    run(c, f"ls -la {REMOTE}/backend/data/releases || true")

    print("Uploading via SFTP...")
    sftp = c.open_sftp()
    tmp = REMOTE_APK + ".tmp"
    sftp.put(str(LOCAL_APK), tmp, confirm=False)
    sftp.close()
    run(c, f"mv -f {tmp} {REMOTE_APK} && ls -la {REMOTE_APK} && chmod 644 {REMOTE_APK}")

    notes = (
        "Приложение переведено на https://legac.ru. "
        "Сброс пароля на почту, шаблоны объявлений, черновики, срок 30/60 дней."
    )
    py = f"""# coding: utf-8
from sqlalchemy import select
from app.core.database import SessionLocal
from app.models import AppUpdate

db = SessionLocal()
try:
    row = db.execute(select(AppUpdate).where(AppUpdate.id == 1)).scalar_one_or_none()
    if row is None:
        row = AppUpdate(id=1)
        db.add(row)
    row.version_name = {VERSION_NAME!r}
    row.version_code = {VERSION_CODE}
    row.force_update = False
    row.notes = {notes.encode("unicode_escape").decode("ascii")!r}.encode("utf-8").decode("unicode_escape")
    row.apk_filename = {APK_FILENAME!r}
    db.commit()
    print("DB OK", row.version_name, row.version_code, row.apk_filename)
finally:
    db.close()
"""
    sftp = c.open_sftp()
    with sftp.file("/tmp/mark_apk.py", "wb") as f:
        f.write(py.encode("utf-8"))
    sftp.close()
    run(
        c,
        f"cd {REMOTE}/backend && PYTHONPATH={REMOTE}/backend {REMOTE}/venv/bin/python /tmp/mark_apk.py",
    )
    run(c, "curl -sS http://127.0.0.1:8080/api/app/update")
    run(c, f"stat -c '%s' {REMOTE_APK}")
    # quick download smoke (first bytes)
    run(
        c,
        "curl -sS -D - -o /tmp/apk_head.bin --range 0-15 http://127.0.0.1:8080/api/app/apk | head -n 20",
    )
    c.close()
    print()
    print("PUBLIC LINK:")
    print("https://legac.ru/api/app/apk")
    print(f"http://{HOST}:8080/api/app/apk")
    print("DONE")


if __name__ == "__main__":
    main()
