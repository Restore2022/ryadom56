import re

_BAD = re.compile(r"^(javascript|data|vbscript):", re.I)


def safe_http_url(value: str | None) -> str | None:
    raw = " ".join(str(value or "").split())
    if not raw:
        return None
    if _BAD.match(raw):
        return None
    if re.match(r"^https?://", raw, re.I):
        return raw[:500]
    if raw.startswith("//"):
        return f"https:{raw}"[:500]
    if "." in raw and " " not in raw:
        return f"https://{raw.lstrip('/')}"[:500]
    return None
