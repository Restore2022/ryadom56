import json
import urllib.request


def call(path, method="GET", data=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8000/api" + path, data=body, headers=headers, method=method
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())


s = call("/settlements")
print("settlements", len(s))
tok = call("/auth/login", "POST", {"email": "admin@ryadom56.ru", "password": "admin123"})[
    "access_token"
]
print("login ok")
me = call("/auth/me", token=tok)
print("me", me["role"], me["email"])
stats = call("/admin/stats", token=tok)
print("stats", stats)
sakmara_id = next(x["id"] for x in s if x["name"] == "Сакмара")
listing = call(
    "/listings",
    "POST",
    {
        "title": "Сено в тюках",
        "description": "Продаю сено, самовывоз из Сакмары, торг уместен.",
        "category": "goods",
        "settlement_id": sakmara_id,
        "price": 3500,
        "contact_phone": "+79990001122",
    },
    token=tok,
)
print("listing", listing["id"], listing["status"])
approved = call(f"/listings/{listing['id']}/moderate", "POST", {"status": "approved"}, token=tok)
print("approved", approved["status"])
print("public listings", len(call("/listings")))
dir_item = call(
    "/directory",
    "POST",
    {
        "title": "Сакмарская ЦРБ",
        "category": "hospital",
        "settlement_id": sakmara_id,
        "address": "с. Сакмара",
        "phone": "8(35331)2-11-11",
        "is_published": True,
    },
    token=tok,
)
print("directory", dir_item["title"])
print("DONE")
