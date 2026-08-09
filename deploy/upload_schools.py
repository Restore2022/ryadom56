"""Upload Sakmarsky district schools into production directory_items."""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

import paramiko

HOST = "155.212.174.201"
PASS = os.environ.get("RYADOM_SSH_PASS", "")
if not PASS:
    raise SystemExit("Set RYADOM_SSH_PASS env var")
REMOTE = "/opt/ryadom56"
ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "deploy" / "sakmarsky_schools.json"

# short title + settlement display_name for FK
SCHOOL_META = [
    ("Архиповская СОШ", "село Архиповка"),
    ("Беловская СОШ", "село Беловка"),
    ("Белоусовская СОШ", "село Белоусовка"),
    ("Верхнечебеньковская СОШ", "село Верхние Чебеньки"),
    ("Дмитриевская СОШ", "посёлок Жилгородок"),
    ("Егорьевская СОШ", "село Искра"),
    ("Краснокоммунарская СОШ", "посёлок Красный Коммунар"),
    ("Марьевская ООШ", "село Марьевка (Марьевский с/с)"),
    ("Никольская СОШ", "село Никольское"),
    ("Орловская ООШ", "село Орловка"),
    ("Сакмарская СОШ им. Героя РФ С. Панова", "село Сакмара"),
    ("Светлинская СОШ", "посёлок Светлый"),
    ("Тат.Каргалинская СОШ", "село Татарская Каргала"),
    ("Тимашевская ООШ", "село Тимашево"),
    ("Чапаевская ООШ", "село Чапаевское"),
    ("Центральная СОШ", "село Первая Григорьевка"),
]


def short_address(addr: str | None) -> str | None:
    if not addr:
        return None
    a = addr
    a = re.sub(r"^461\d{3},?\s*", "", a)
    a = re.sub(r"^Россия,?\s*", "", a, flags=re.I)
    a = re.sub(r"^Оренбургская область,?\s*", "", a, flags=re.I)
    a = re.sub(r"^Сакмарский район,?\s*", "", a, flags=re.I)
    return re.sub(r"\s+", " ", a).strip(" ,")


def run(c: paramiko.SSHClient, cmd: str, timeout: int = 120) -> str:
    print(">", cmd[:180])
    _, so, se = c.exec_command(cmd, timeout=timeout)
    out = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    code = so.channel.recv_exit_status()
    text = (out + ("\n" + err if err.strip() else "")).encode("ascii", "replace").decode()
    if text.strip():
        print(text[-4000:])
    if code != 0:
        raise SystemExit(f"fail {code}")
    return out


def main() -> None:
    schools = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    if len(schools) != len(SCHOOL_META):
        raise SystemExit(f"meta/json mismatch: {len(SCHOOL_META)} vs {len(schools)}")

    payload = []
    for raw, (title, settlement) in zip(schools, SCHOOL_META):
        desc_parts = [raw.get("description") or ""]
        if raw.get("leader"):
            desc_parts.append(f"Директор: {raw['leader']}.")
        if raw.get("email"):
            desc_parts.append(f"Email: {raw['email']}.")
        description = " ".join(p for p in desc_parts if p).strip()
        hours = raw.get("hours") or "пн–пт"
        if len(hours) > 255:
            hours = hours[:255]
        payload.append(
            {
                "title": title[:200],
                "settlement_display": settlement,
                "description": description or None,
                "address": short_address(raw.get("address")),
                "phone": raw.get("phone"),
                "website": raw.get("site"),
                "hours": hours,
                "lat": raw.get("lat"),
                "lon": raw.get("lon"),
            }
        )

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="root", password=PASS, timeout=60, allow_agent=False, look_for_keys=False)

    sftp = c.open_sftp()
    remote_json = "/tmp/sakmarsky_schools_upload.json"
    with sftp.file(remote_json, "w") as f:
        f.write(json.dumps(payload, ensure_ascii=False))
    sftp.close()

    script = r'''
import json
from pathlib import Path
from sqlalchemy import select
from app.core.database import SessionLocal
from app.models import DirectoryCategory, DirectoryItem, Settlement

items = json.loads(Path("/tmp/sakmarsky_schools_upload.json").read_text(encoding="utf-8"))
db = SessionLocal()
created = updated = 0
try:
    settlements = {
        s.display_name: s.id
        for s in db.execute(select(Settlement)).scalars().all()
    }
    for row in items:
        sid = settlements.get(row["settlement_display"])
        if sid is None:
            print("MISSING_SETTLEMENT", row["settlement_display"])
        existing = db.execute(
            select(DirectoryItem).where(
                DirectoryItem.category == DirectoryCategory.school,
                DirectoryItem.title == row["title"],
            )
        ).scalar_one_or_none()
        fields = dict(
            settlement_id=sid,
            category=DirectoryCategory.school,
            title=row["title"],
            description=row.get("description"),
            address=row.get("address"),
            phone=row.get("phone"),
            website=row.get("website"),
            hours=row.get("hours"),
            lat=row.get("lat"),
            lon=row.get("lon"),
            is_published=True,
        )
        if existing:
            for k, v in fields.items():
                setattr(existing, k, v)
            updated += 1
        else:
            db.add(DirectoryItem(**fields))
            created += 1
    db.commit()
    total = db.execute(
        select(DirectoryItem).where(DirectoryItem.category == DirectoryCategory.school)
    ).scalars().all()
    print(f"OK created={created} updated={updated} schools_total={len(total)}")
finally:
    db.close()
'''
    remote_py = "/tmp/upload_schools_run.py"
    sftp = c.open_sftp()
    with sftp.file(remote_py, "w") as f:
        f.write(script)
    sftp.close()

    run(
        c,
        f"cd {REMOTE}/backend && PYTHONPATH={REMOTE}/backend "
        f"{REMOTE}/venv/bin/python {remote_py}",
    )
    run(c, "curl -sS 'http://127.0.0.1:8080/api/directory?category=school' | python3 -c \"import sys,json; d=json.load(sys.stdin); print(len(d), [x['title'] for x in d[:3]], '...')\"")
    c.close()
    print("DONE")


if __name__ == "__main__":
    main()
