from sqlalchemy import or_


def contains_query(columns: list, q: str | None):
    """Подстрока с учётом заглавной буквы и простой русской окончания (спартакиада → спартакиад)."""
    raw = (q or "").strip()
    if not raw:
        return None
    stems = {raw}
    if len(raw) >= 6:
        stems.add(raw[:-1])
    variants: set[str] = set()
    for s in stems:
        variants.add(s)
        variants.add(s.lower())
        if s:
            variants.add(s[0].upper() + s[1:])
    clauses = [col.ilike(f"%{v}%") for col in columns for v in variants]
    return or_(*clauses) if clauses else None
