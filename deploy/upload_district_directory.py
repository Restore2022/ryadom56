"""Залить справочник района на прод. Существующие карточки не трогает."""
from __future__ import annotations

import json
import os
from pathlib import Path

import paramiko

HOST = "155.212.174.201"
PASS = os.environ.get("RYADOM_SSH_PASS", "")
if not PASS:
    raise SystemExit("Set RYADOM_SSH_PASS env var")
REMOTE = "/opt/ryadom56"
JSON_PATH = Path(__file__).resolve().parents[1] / "deploy" / "sakmarsky_yandex_directory.json"


def run(c: paramiko.SSHClient, cmd: str, timeout: int = 180) -> str:
    print(">", cmd[:180])
    _, so, se = c.exec_command(cmd, timeout=timeout)
    out = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    code = so.channel.recv_exit_status()
    text = out + ("\n" + err if err.strip() else "")
    if text.strip():
        print(text[-6000:])
    if code != 0:
        raise SystemExit(f"fail {code}")
    return out


def main() -> None:
    payload = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    items = payload.get("items") or payload
    if isinstance(items, dict):
        items = items.get("items") or []
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASS, timeout=60, allow_agent=False, look_for_keys=False)
    sftp = c.open_sftp()
    remote_json = "/tmp/district_directory_upload.json"
    with sftp.file(remote_json, "w") as f:
        f.write(json.dumps(items, ensure_ascii=False))
    remote_py = "/tmp/upload_district_directory_run.py"
    with sftp.file(remote_py, "w") as f:
        f.write(
            r'''
import json
from pathlib import Path
from sqlalchemy import select
from app.core.database import SessionLocal
from app.models import DirectoryCategory, DirectoryItem, Settlement

items = json.loads(Path("/tmp/district_directory_upload.json").read_text(encoding="utf-8"))
db = SessionLocal()
try:
    settlements = {s.display_name: s.id for s in db.execute(select(Settlement)).scalars().all()}
    existing = db.execute(select(DirectoryItem)).scalars().all()
    keys = {
        (x.settlement_id, x.title.strip().lower(), (x.address or "").strip().lower())
        for x in existing
    }
    created = skipped = missing = 0
    by_s = {}
    for row in items:
        disp = row.get("settlement_display")
        sid = settlements.get(disp)
        if sid is None:
            missing += 1
            print("MISSING", disp, row.get("title"))
            continue
        title = (row.get("title") or "").strip()
        addr = (row.get("address") or "").strip()
        key = (sid, title.lower(), addr.lower())
        if key in keys:
            skipped += 1
            continue
        hours = row.get("hours")
        if hours and len(hours) > 255:
            hours = hours[:255]
        db.add(
            DirectoryItem(
                settlement_id=sid,
                category=DirectoryCategory(row["category"]),
                title=title[:200],
                description=row.get("description"),
                address=addr or None,
                phone=row.get("phone"),
                website=row.get("website"),
                hours=hours,
                lat=row.get("lat"),
                lon=row.get("lon"),
                is_published=True,
            )
        )
        keys.add(key)
        created += 1
        by_s[disp] = by_s.get(disp, 0) + 1
    db.commit()
    total = db.execute(select(DirectoryItem)).scalars().all()
    print(f"OK created={created} skipped={skipped} missing={missing} directory_total={len(total)}")
    for name, n in sorted(by_s.items(), key=lambda x: -x[1]):
        print(f"  +{n} {name}")
finally:
    db.close()
'''
        )
    sftp.close()
    run(
        c,
        f"cd {REMOTE}/backend && PYTHONPATH={REMOTE}/backend "
        f"{REMOTE}/venv/bin/python {remote_py}",
    )
    c.close()
    print("DONE")


if __name__ == "__main__":
    main()
