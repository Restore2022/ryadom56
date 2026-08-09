"""Pull latest code on VPS, purge demo seed content, rebuild admin, restart."""
from __future__ import annotations

import io
import os
import tarfile
import time
from pathlib import Path

import paramiko

HOST = "155.212.174.201"
PASS = os.environ["RYADOM_SSH_PASS"]
REMOTE = "/opt/ryadom56"
ROOT = Path(__file__).resolve().parents[1]


def run(c: paramiko.SSHClient, cmd: str, timeout: int = 600) -> str:
    print(">", cmd[:160])
    _, so, se = c.exec_command(cmd, timeout=timeout)
    out = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    code = so.channel.recv_exit_status()
    text = (out + "\n" + err).encode("ascii", "replace").decode()
    if text.strip():
        print(text[-3000:])
    if code != 0:
        raise SystemExit(f"fail {code}")
    return out


def main() -> None:
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASS, timeout=60, allow_agent=False, look_for_keys=False)

    run(c, f"cd {REMOTE} && git fetch --depth 1 origin main && git reset --hard origin/main")
    run(
        c,
        f"{REMOTE}/venv/bin/pip install -q -r {REMOTE}/backend/requirements.txt",
    )
    # ensure demo seed off
    run(
        c,
        f"grep -q '^SEED_DEMO_CONTENT=' {REMOTE}/backend/.env && "
        f"sed -i 's/^SEED_DEMO_CONTENT=.*/SEED_DEMO_CONTENT=false/' {REMOTE}/backend/.env || "
        f"echo 'SEED_DEMO_CONTENT=false' >> {REMOTE}/backend/.env",
    )
    # purge demo tables (keep settlements, users, legal, directory if any real)
    purge = f"""
cd {REMOTE}/backend && {REMOTE}/venv/bin/python - <<'PY'
from app.core.database import SessionLocal
from app.models import (
    DistrictAlert, DistrictNews, Event, TransportFavorite, TransportRoute,
)
db = SessionLocal()
try:
    for row in db.query(TransportFavorite).all():
        db.delete(row)
    for row in db.query(TransportRoute).all():
        db.delete(row)
    for row in db.query(Event).all():
        db.delete(row)
    for row in db.query(DistrictNews).all():
        db.delete(row)
    for row in db.query(DistrictAlert).all():
        db.delete(row)
    db.commit()
    print('purged demo content')
finally:
    db.close()
PY
"""
    run(c, purge)

    # upload freshly built admin (same-origin /api)
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        tar.add(ROOT / "admin" / "dist", arcname="dist")
    buf.seek(0)
    sftp = c.open_sftp()
    with sftp.file("/tmp/ryadom56-admin.tar.gz", "wb") as f:
        f.write(buf.read())
    sftp.close()
    run(c, f"rm -rf {REMOTE}/admin/dist && mkdir -p {REMOTE}/admin && tar -xzf /tmp/ryadom56-admin.tar.gz -C {REMOTE}/admin && rm -f /tmp/ryadom56-admin.tar.gz")
    run(c, "systemctl restart ryadom56 && systemctl reload nginx")
    time.sleep(3)
    run(c, "curl -sS http://127.0.0.1:8080/api/health")
    run(c, "curl -sS http://127.0.0.1:8080/api/events | head -c 200")
    run(c, "curl -sS http://127.0.0.1:8080/api/transport | head -c 200")
    c.close()
    print("DONE")


if __name__ == "__main__":
    main()
