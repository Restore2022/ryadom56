# -*- coding: utf-8 -*-
"""Снять организации Сакмарского района с Яндекс.Карт (без Оренбурга и без повторного сбора Красного Коммунара)."""
from __future__ import annotations

import json
import math
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "deploy" / "sakmarsky_yandex_directory.json"
PROGRESS = ROOT / "deploy" / "sakmarsky_yandex_progress.json"
UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)
API = "https://legac.ru/api"
SKIP_SCRAPE = {"город Оренбург", "посёлок Красный Коммунар"}
QUERIES = [
    "магазин",
    "аптека",
    "школа",
    "ФАП",
    "почта",
    "пункт выдачи",
    "администрация",
    "детский сад",
]
DAYS = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]


def fetch(url: str, timeout: int = 30) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "text/html,*/*;q=0.8",
            "Accept-Language": "ru-RU,ru;q=0.9",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def fetch_json(url: str):
    return json.loads(fetch(url))


def parse_state(html: str) -> dict | None:
    tag = '<script type="application/json"'
    i = html.find(tag)
    if i < 0:
        return None
    gt = html.find(">", i)
    end = html.find("</script>", gt)
    try:
        return json.loads(html[gt + 1 : end])
    except json.JSONDecodeError:
        return None


def haversine_km(lat1, lon1, lat2, lon2) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def fmt_hours(item: dict) -> str | None:
    text = item.get("workingTimeText")
    if isinstance(text, str) and text.strip():
        return text.strip()[:255]
    wt = item.get("workingTime")
    if not isinstance(wt, list) or not wt:
        return None
    parts = []
    for i, day in enumerate(wt):
        if i >= 7:
            break
        if not day:
            parts.append(f"{DAYS[i]} выходной")
            continue
        slots = []
        for slot in day:
            fr = slot.get("from") or {}
            to = slot.get("to") or {}
            slots.append(
                f"{fr.get('hours', 0):02d}:{fr.get('minutes', 0):02d}–"
                f"{to.get('hours', 0):02d}:{to.get('minutes', 0):02d}"
            )
        parts.append(f"{DAYS[i]} {', '.join(slots)}")
    if len(parts) == 7 and all("выходной" not in p and p[3:] == parts[0][3:] for p in parts):
        return f"ежедневно {parts[0][3:]}"[:255]
    return "; ".join(parts)[:255]


def site_of(item: dict) -> str | None:
    urls = item.get("urls") or []
    if not urls:
        return None
    u = str(urls[0]).split("?")[0].strip()
    return u or None


def phone_of(item: dict) -> str | None:
    phones = item.get("phones") or []
    if not phones:
        return None
    n = phones[0].get("number") or phones[0].get("value")
    return (str(n)[:64] if n else None)


def short_address(full: str | None, name: str) -> str | None:
    if not full:
        return None
    a = full
    for cut in (
        "Россия, ",
        "Оренбургская область, ",
        "Сакмарский район, ",
        f"посёлок {name}, ",
        f"поселок {name}, ",
        f"село {name}, ",
        f"разъезд {name}, ",
    ):
        a = a.replace(cut, "")
    a = a.replace("улица ", "").replace("ул. ", "")
    return a.strip(" ,")[:255] or None


def cleaned_addr(text: str) -> str:
    t = (text or "").replace("ё", "е").lower()
    for cut in ("оренбургская область", "сакмарский район", "россия"):
        t = t.replace(cut, " ")
    return " ".join(t.split())


def category_of(item: dict) -> str:
    cats = " ".join(
        c.get("name", "") + " " + c.get("class", "") for c in (item.get("categories") or [])
    ).lower()
    title = (item.get("title") or "").lower()
    blob = cats + " " + title
    rules = [
        ("pharmacy", ("аптек", "pharmacy")),
        (
            "hospital",
            (
                "больниц",
                "поликлин",
                "амбулатор",
                "фап",
                "медпункт",
                "медицинский пункт",
                "стомат",
                "clinic",
                "hospital",
            ),
        ),
        ("school", ("школ", "детский сад", "ясли", "school", "kindergarten")),
        ("admin", ("администрац", "мфц", "сельсовет", "поссовет")),
        ("bank", ("банк", "банкомат")),
        ("post", ("почт", "post_office")),
        ("transport", ("станци", "вокзал", "автовокзал")),
        ("culture", ("дом культуры", "библиотек", "храм", "церков", "дши", "школа искусств")),
        ("sport", ("спорт", "стадион", "фитнес")),
        (
            "shop",
            (
                "магазин",
                "супермаркет",
                "пятероч",
                "магнит",
                "рынок",
                "пекарн",
                "продукт",
                "хозтовар",
                "ozon",
                "wildberries",
                "пункт выдач",
                "постамат",
                "5post",
            ),
        ),
    ]
    for cat, keys in rules:
        if any(k in blob for k in keys):
            return cat
    return "other"


def assign(item: dict, settlements: list[dict]) -> dict | None:
    coords = item.get("coordinates") or item.get("displayCoordinates") or []
    lat = lon = None
    if len(coords) >= 2:
        lon, lat = float(coords[0]), float(coords[1])
    blob = cleaned_addr(
        " ".join(
            [
                str(item.get("address") or ""),
                str(item.get("fullAddress") or ""),
                str(item.get("description") or ""),
            ]
        )
    )
    if ("г. оренбург" in blob or ", оренбург," in blob or blob.startswith("оренбург,")) and "сакмар" not in blob:
        return None
    named = []
    for s in settlements:
        name = s["name"].replace("ё", "е").lower()
        if len(name) < 4 and name not in ("202 км",):
            continue
        if name in blob:
            named.append(s)
    if len(named) == 1:
        return named[0]
    if len(named) > 1 and lat is not None:
        return min(named, key=lambda s: haversine_km(lat, lon, s["lat"], s["lon"]))
    if lat is None or lon is None:
        return None
    nearest = min(settlements, key=lambda s: haversine_km(lat, lon, s["lat"], s["lon"]))
    dist = haversine_km(lat, lon, nearest["lat"], nearest["lon"])
    if dist <= 0.7:
        return nearest
    return None


def normalize(item: dict, settlement: dict) -> dict:
    coords = item.get("coordinates") or item.get("displayCoordinates") or [None, None]
    cats = [c.get("name") for c in (item.get("categories") or []) if c.get("name")]
    return {
        "yandex_id": str(item.get("id") or ""),
        "settlement_display": settlement["display_name"],
        "title": (item.get("title") or item.get("shortTitle") or "")[:200],
        "category": category_of(item),
        "address": short_address(item.get("fullAddress") or item.get("address"), settlement["name"]),
        "description": (", ".join(cats)[:500] or None),
        "phone": phone_of(item),
        "website": site_of(item),
        "hours": fmt_hours(item),
        "lat": coords[1] if len(coords) > 1 else None,
        "lon": coords[0] if coords else None,
    }


def search(query: str, lon: float, lat: float) -> list[dict]:
    q = urllib.parse.quote(query)
    url = f"https://yandex.ru/maps/11084/orenburg-oblast/search/{q}/?ll={lon:.6f}%2C{lat:.6f}&z=15"
    html = fetch(url)
    state = parse_state(html)
    if not state:
        return []
    stack = state.get("stack") or []
    if not stack:
        return []
    return (stack[0].get("results") or {}).get("items") or []


def save_progress(by_id: dict, done: set, log: list) -> None:
    items = sorted(by_id.values(), key=lambda x: (x["settlement_display"], x["title"]))
    payload = {
        "source": "Яндекс.Карты, Сакмарский район",
        "collected": "2026-08-30",
        "count": len(items),
        "done": sorted(done),
        "log": log[-200:],
        "items": items,
    }
    PROGRESS.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> None:
    only = set(sys.argv[1:]) if len(sys.argv) > 1 else None
    all_settlements = [
        s
        for s in fetch_json(f"{API}/settlements")
        if s.get("is_district") and s.get("lat") is not None and s.get("lon") is not None
    ]
    todo = [s for s in all_settlements if s["display_name"] not in SKIP_SCRAPE]
    if only:
        todo = [s for s in todo if s["name"] in only or s["display_name"] in only]

    progress = json.loads(PROGRESS.read_text(encoding="utf-8")) if PROGRESS.exists() and not only else {}
    by_id = {row["yandex_id"]: row for row in progress.get("items") or [] if row.get("yandex_id")}
    done = set(progress.get("done") or [])
    log: list = list(progress.get("log") or [])

    for s in todo:
        key = s["display_name"]
        if key in done:
            print("DONE", key, flush=True)
            continue
        print(f"== {key}", flush=True)
        got = 0
        for q in QUERIES:
            text = f"{q} {s['settlement_type']} {s['name']} Сакмарский район"
            try:
                items = search(text, float(s["lon"]), float(s["lat"]))
            except Exception as e:
                print("  ERR", q, type(e).__name__, e, flush=True)
                log.append({"s": key, "q": q, "error": str(e)})
                time.sleep(2.0)
                continue
            local = 0
            for it in items:
                if it.get("type") != "business":
                    continue
                assigned = assign(it, all_settlements)
                if not assigned or assigned["display_name"] in SKIP_SCRAPE:
                    continue
                if assigned["display_name"] != key:
                    continue
                row = normalize(it, assigned)
                oid = row["yandex_id"]
                if not oid or not row["title"]:
                    continue
                if oid in by_id:
                    old = by_id[oid]
                    if row["hours"] and not old.get("hours"):
                        old["hours"] = row["hours"]
                    if row["website"] and not old.get("website"):
                        old["website"] = row["website"]
                    if row["phone"] and not old.get("phone"):
                        old["phone"] = row["phone"]
                else:
                    by_id[oid] = row
                    local += 1
                    got += 1
            print(f"  {q}: raw={len(items)} new={local}", flush=True)
            time.sleep(1.15)
        done.add(key)
        save_progress(by_id, done, log)
        print(f"  village_new={got} total={len(by_id)}", flush=True)

    save_progress(by_id, done, log)
    from collections import Counter

    c = Counter(x["settlement_display"] for x in by_id.values())
    print("TOTAL", len(by_id))
    for name, n in c.most_common():
        print(f"  {n:3} {name}")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
