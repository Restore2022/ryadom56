"""ICE-серверы для звонков: Cloudflare TURN или свой coturn, иначе только STUN."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import time
import urllib.error
import urllib.request

from app.core.config import settings

logger = logging.getLogger(__name__)

_CF_URL = "https://rtc.live.cloudflare.com/v1/turn/keys/{key}/credentials/generate-ice-servers"
_TTL_SEC = 6 * 60 * 60
_CACHE_SEC = 10 * 60

STUN_FALLBACK: list[dict] = [
    {"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]},
]

_cache: list[dict] | None = None
_cache_until: float = 0.0
_cache_turn: bool = False


def _cf_ok() -> bool:
    return bool((settings.cloudflare_turn_key_id or "").strip() and (settings.cloudflare_turn_api_token or "").strip())


def _self_ok() -> bool:
    return bool((settings.turn_auth_secret or "").strip())


def turn_configured() -> bool:
    return _cf_ok() or _self_ok()


def get_ice_servers() -> tuple[list[dict], bool]:
    global _cache, _cache_until, _cache_turn
    now = time.time()
    if _cache and now < _cache_until:
        return _cache, _cache_turn
    if _cf_ok():
        fetched = _fetch_cloudflare()
        if fetched:
            _cache, _cache_turn, _cache_until = fetched, True, now + _CACHE_SEC
            return _cache, True
        logger.warning("Cloudflare TURN unavailable — trying local coturn/STUN")
    if _self_ok():
        servers = [*STUN_FALLBACK, _self_turn_server()]
        _cache, _cache_turn, _cache_until = servers, True, now + _CACHE_SEC
        return _cache, True
    _cache, _cache_turn, _cache_until = STUN_FALLBACK, False, now + 60
    return _cache, False


def _self_turn_server() -> dict:
    secret = settings.turn_auth_secret.strip()
    host = (settings.turn_host or "legac.ru").strip()
    expiry = int(time.time()) + _TTL_SEC
    username = f"{expiry}:ryadom"
    digest = hmac.new(secret.encode("utf-8"), username.encode("utf-8"), hashlib.sha1).digest()
    credential = base64.b64encode(digest).decode("ascii")
    return {
        "urls": [
            f"turn:{host}:3478?transport=udp",
            f"turn:{host}:3478?transport=tcp",
        ],
        "username": username,
        "credential": credential,
    }


def _fetch_cloudflare() -> list[dict] | None:
    key = settings.cloudflare_turn_key_id.strip()
    token = settings.cloudflare_turn_api_token.strip()
    url = _CF_URL.format(key=key)
    body = json.dumps({"ttl": _TTL_SEC}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            raw = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        err = exc.read().decode("utf-8", "replace")[:400]
        logger.warning("Cloudflare TURN HTTP %s: %s", exc.code, err)
        return None
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        logger.warning("Cloudflare TURN failed: %s", exc)
        return None
    rows = raw.get("iceServers") or raw.get("ice_servers") or []
    if not isinstance(rows, list) or not rows:
        return None
    out: list[dict] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        urls = _clean_urls(row.get("urls"))
        if not urls:
            continue
        item: dict = {"urls": urls}
        user = row.get("username")
        cred = row.get("credential")
        if user and cred:
            item["username"] = str(user)
            item["credential"] = str(cred)
        out.append(item)
    return out or None


def _clean_urls(raw) -> list[str]:
    if isinstance(raw, str):
        items = [raw]
    elif isinstance(raw, list):
        items = [str(u) for u in raw if u]
    else:
        return []
    cleaned: list[str] = []
    for url in items:
        host = url.split("?", 1)[0]
        if host.endswith(":53") or ":53:" in host:
            continue
        cleaned.append(url)
    return cleaned
