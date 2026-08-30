"""Залить справочник Красного Коммунара на прод. Существующие карточки не трогает."""
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
JSON_PATH = Path(__file__).resolve().parents[1] / "deploy" / "krasny_kommunar_directory.json"


def run(c: paramiko.SSHClient, cmd: str, timeout: int = 120) -> str:
    print(">", cmd[:180])
    _, so, se = c.exec_command(cmd, timeout=timeout)
    out = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    code = so.channel.recv_exit_status()
    text = out + ("\n" + err if err.strip() else "")
    if text.strip():
        print(text[-4000:])
    if code != 0:
        raise SystemExit(f"fail {code}")
    return out


def main() -> None:
    payload = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASS, timeout=60, allow_agent=False, look_for_keys=False)
    sftp = c.open_sftp()
    remote_json = "/tmp/kk_directory_upload.json"
    with sftp.file(remote_json, "w") as f:
        f.write(json.dumps(payload, ensure_ascii=False))
    remote_py = "/tmp/upload_kk_directory_run.py"
    with sftp.file(remote_py, "w") as f:
        f.write(
            r'''
import json
from pathlib import Path
from sqlalchemy import select
from app.core.database import SessionLocal
from app.models import DirectoryCategory, DirectoryItem, Settlement

items = json.loads(Path("/tmp/kk_directory_upload.json").read_text(encoding="utf-8"))
db = SessionLocal()
try:
    sid = db.execute(
        select(Settlement.id).where(Settlement.display_name == "посёлок Красный Коммунар")
    ).scalar_one()
    existing = db.execute(
        select(DirectoryItem).where(DirectoryItem.settlement_id == sid)
    ).scalars().all()
    keys = {(x.title.strip().lower(), (x.address or "").strip().lower()) for x in existing}
    created = skipped = 0
    for row in items:
        key = (row["title"].strip().lower(), (row.get("address") or "").strip().lower())
        if key in keys:
            skipped += 1
            print("SKIP", row["title"], row.get("address"))
            continue
        hours = row.get("hours")
        if hours and len(hours) > 255:
            hours = hours[:255]
        db.add(
            DirectoryItem(
                settlement_id=sid,
                category=DirectoryCategory(row["category"]),
                title=row["title"][:200],
                description=row.get("description"),
                address=row.get("address"),
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
        print("ADD", row["title"], row.get("address"))
    db.commit()
    total = db.execute(
        select(DirectoryItem).where(DirectoryItem.settlement_id == sid)
    ).scalars().all()
    print(f"OK created={created} skipped={skipped} village_total={len(total)}")
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
