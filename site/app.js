const CAT = {
  goods: "Товары",
  services: "Услуги",
  jobs: "Работа",
  rent: "Аренда",
  free: "Отдам",
  lost_found: "Потеряшки",
};

const SITE_URL = "https://legac.ru/";
const SELO_KEY = "ryadom56.selo";
const SPOTLIGHT = ["jobs", "free", "lost_found"];

const state = {
  category: "",
  settlementId: "",
  q: "",
  offset: 0,
  limit: 6,
  total: 0,
  byId: {},
  overlayPhotos: [],
  overlayPhoto: 0,
  searchHits: 0,
  stories: { event: {}, news: {} },
  overlayMode: "",
};

function $(id) {
  return document.getElementById(id);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function formatPrice(item) {
  if (item.category === "free") return "Отдам";
  if (item.price == null) return "Цена не указана";
  return `${Number(item.price).toLocaleString("ru-RU")} ₽`;
}

const LOCAL_TZ = "Asia/Yekaterinburg";

function tzParts(d) {
  const fmt = new Intl.DateTimeFormat("en-GB", {
    timeZone: LOCAL_TZ,
    day: "numeric",
    month: "numeric",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    hourCycle: "h23",
  });
  const map = {};
  for (const p of fmt.formatToParts(d)) {
    if (p.type !== "literal") map[p.type] = p.value;
  }
  return map;
}

function formatDate(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleString("ru-RU", {
    timeZone: LOCAL_TZ,
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

const MONTHS_GEN = [
  "января", "февраля", "марта", "апреля", "мая", "июня",
  "июля", "августа", "сентября", "октября", "ноября", "декабря",
];

function pad2(n) {
  return String(n).padStart(2, "0");
}

function formatEventWhen(startIso, endIso) {
  if (!startIso) return "";
  const start = new Date(startIso);
  if (Number.isNaN(start.getTime())) return "";
  const s = tzParts(start);
  const monthIdx = Number(s.month) - 1;
  const date = `${Number(s.day)} ${MONTHS_GEN[monthIdx] || ""}`;
  const t1 = `${pad2(s.hour)}:${pad2(s.minute)}`;
  if (!endIso) return `${date}, ${t1}`;
  const end = new Date(endIso);
  if (Number.isNaN(end.getTime())) return `${date}, ${t1}`;
  const e = tzParts(end);
  const t2 = `${pad2(e.hour)}:${pad2(e.minute)}`;
  const same = s.year === e.year && s.month === e.month && s.day === e.day;
  if (same) return `${date}, ${t1}–${t2}`;
  return `${date}, ${t1} — ${Number(e.day)} ${MONTHS_GEN[Number(e.month) - 1] || ""}, ${t2}`;
}

function formatDistance(km) {
  if (km == null || Number.isNaN(Number(km))) return "";
  const n = Number(km);
  if (n < 1) return "рядом";
  return `${n.toLocaleString("ru-RU")} км`;
}

function shortText(value, max) {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  if (text.length <= max) return text;
  return `${text.slice(0, max).trim()}…`;
}

function isIos() {
  const ua = navigator.userAgent || "";
  if (/iPhone|iPod|iPad/i.test(ua)) return true;
  return navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
}

let apkLocked = false;

function disableApk() {
  if (apkLocked) return;
  apkLocked = true;
  document.querySelectorAll(".js-apk").forEach((el) => {
    el.classList.add("is-disabled");
    el.setAttribute("aria-disabled", "true");
    el.addEventListener("click", (e) => e.preventDefault());
  });
}

function toast(message) {
  const el = $("toast");
  if (!el) return;
  el.textContent = message;
  el.hidden = false;
  window.clearTimeout(toast.timer);
  toast.timer = window.setTimeout(() => {
    el.hidden = true;
  }, 2400);
}

async function shareSite() {
  const data = {
    title: "Рядом56",
    text: "Объявления и справочник Сакмарского района",
    url: SITE_URL,
  };
  try {
    if (navigator.share) {
      await navigator.share(data);
      return;
    }
  } catch (err) {
    if (err && err.name === "AbortError") return;
  }
  try {
    await navigator.clipboard.writeText(SITE_URL);
    toast("Ссылка на сайт скопирована");
  } catch {
    toast(SITE_URL);
  }
}

async function getJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(String(res.status));
  if (res.status === 204) return null;
  const text = await res.text();
  if (!text) return null;
  return JSON.parse(text);
}

function media(url) {
  if (!url) return "";
  if (url.startsWith("http")) return url;
  return url;
}

function listingCard(item) {
  const img = item.images?.[0]?.url;
  const place = item.settlement_name || "";
  const dist = formatDistance(item.distance_km);
  const meta = [CAT[item.category], place, dist].filter(Boolean).join(" · ");
  const title = escapeHtml(item.title || "Объявление");
  return `<article class="listing-card" data-id="${item.id}" tabindex="0" role="button">
    <div class="card-photo${img ? "" : " empty"}" ${img ? `style="background-image:url('${escapeHtml(media(img))}')"` : ""}>${img ? "" : "Без фото"}</div>
    <div class="muted">${escapeHtml(meta)}</div>
    <h3>${title}</h3>
    <p class="price">${escapeHtml(formatPrice(item))}</p>
  </article>`;
}

function listingUrl(id) {
  return `${SITE_URL.replace(/\/$/, "")}/l/${id}`;
}

function setListingParam(id) {
  const u = new URL(location.href);
  u.searchParams.delete("l");
  u.hash = id ? `l=${id}` : "";
  history.replaceState(null, "", u);
}

function requestedListingId() {
  const path = (location.pathname || "").match(/^\/l\/(\d+)\/?$/);
  if (path) return path[1];
  const q = new URLSearchParams(location.search).get("l");
  if (q && /^\d+$/.test(q)) return q;
  const hash = (location.hash || "").match(/^#l=(\d+)/);
  return hash ? hash[1] : "";
}

function rememberStories(kind, items) {
  (items || []).forEach((item) => {
    state.stories[kind][String(item.id)] = item;
  });
}

function storyCard(kind, item, whenText) {
  return `<article class="story-card" data-kind="${kind}" data-id="${item.id}" tabindex="0" role="button">
    <div class="when">${escapeHtml(whenText)}</div>
    <h3>${escapeHtml(item.title)}</h3>
    <p class="muted">${escapeHtml(
      kind === "event"
        ? [item.place_text, item.settlement_name].filter(Boolean).join(" · ")
        : shortText(item.body, 140),
    )}</p>
  </article>`;
}

function closeOverlay() {
  const overlay = $("overlay");
  if (!overlay) return;
  overlay.hidden = true;
  document.body.style.overflow = "";
  state.overlayPhotos = [];
  state.overlayPhoto = 0;
  if (state.overlayMode === "listing") setListingParam(null);
  state.overlayMode = "";
}

function showOverlayPhoto() {
  const img = $("overlay-img");
  const n = $("overlay-photo-n");
  const prev = $("overlay-prev");
  const next = $("overlay-next");
  const photos = state.overlayPhotos;
  if (!img) return;
  if (!photos.length) {
    img.hidden = true;
    if (n) n.hidden = true;
    if (prev) prev.hidden = true;
    if (next) next.hidden = true;
    return;
  }
  const i = ((state.overlayPhoto % photos.length) + photos.length) % photos.length;
  state.overlayPhoto = i;
  img.hidden = false;
  img.src = media(photos[i]);
  const many = photos.length > 1;
  if (n) {
    n.hidden = !many;
    n.textContent = `${i + 1} / ${photos.length}`;
  }
  if (prev) prev.hidden = !many;
  if (next) next.hidden = !many;
}

function stepOverlayPhoto(dir) {
  if (state.overlayPhotos.length < 2) return;
  state.overlayPhoto += dir;
  showOverlayPhoto();
}

function openOverlay(mode, data) {
  const overlay = $("overlay");
  const card = overlay?.querySelector(".overlay-card");
  const img = $("overlay-img");
  const meta = $("overlay-meta");
  const title = $("overlay-title");
  const price = $("overlay-price");
  const text = $("overlay-text");
  const cta = $("overlay-cta");
  const share = $("overlay-share");
  if (!overlay || !card || !img) return;

  state.overlayMode = mode;
  card.classList.toggle("is-shot", mode === "shot");
  if (share) share.hidden = true;

  if (mode === "shot") {
    setListingParam(null);
    state.overlayPhotos = data.src ? [data.src] : [];
    state.overlayPhoto = 0;
    img.alt = data.title || "";
    showOverlayPhoto();
    meta.hidden = true;
    price.hidden = true;
    text.hidden = true;
    cta.hidden = true;
    title.textContent = data.title || "";
  } else if (mode === "story") {
    setListingParam(null);
    state.overlayPhotos = data.photos || [];
    state.overlayPhoto = 0;
    img.alt = data.title || "";
    showOverlayPhoto();
    meta.hidden = false;
    price.hidden = true;
    text.hidden = false;
    cta.hidden = false;
    meta.textContent = data.meta || "";
    title.textContent = data.title || "";
    text.textContent = data.text || "Подробности — в приложении.";
  } else {
    const photos = (data.images || []).map((x) => x.url).filter(Boolean);
    state.overlayPhotos = photos;
    state.overlayPhoto = 0;
    img.alt = data.title || "";
    showOverlayPhoto();
    meta.hidden = false;
    price.hidden = false;
    text.hidden = false;
    cta.hidden = false;
    meta.textContent = [CAT[data.category], data.settlement_name, formatDistance(data.distance_km)].filter(Boolean).join(" · ");
    title.textContent = data.title || "Объявление";
    price.textContent = formatPrice(data);
    text.textContent = data.description || "Подробности, фото и контакты — в приложении.";
    if (share && data.id) {
      share.hidden = false;
      share.dataset.id = String(data.id);
    }
    setListingParam(data.id);
  }
  overlay.hidden = false;
  document.body.style.overflow = "hidden";
}

function openListing(id) {
  const item = state.byId[String(id)];
  if (item) openOverlay("listing", item);
}

function openStory(kind, id) {
  const item = state.stories[kind]?.[String(id)];
  if (!item) return;
  if (kind === "event") {
    openOverlay("story", {
      photos: item.cover_url ? [item.cover_url] : [],
      title: item.title,
      meta: [formatEventWhen(item.starts_at, item.ends_at), item.place_text, item.settlement_name].filter(Boolean).join(" · "),
      text: item.description || "Подробности и напоминания — в приложении.",
    });
    return;
  }
  openOverlay("story", {
    photos: item.cover_url ? [item.cover_url] : [],
    title: item.title,
    meta: ["Новость", item.settlement_name].filter(Boolean).join(" · "),
    text: item.body || "Подробности — в приложении.",
  });
}

async function openListingDeep(id) {
  if (!id) return;
  let item = state.byId[String(id)];
  if (!item) {
    try {
      item = await getJson(`/api/listings/${id}`);
    } catch {
      toast("Объявление не найдено или уже снято");
      setListingParam(null);
      return;
    }
    if (item) state.byId[String(item.id)] = item;
  }
  if (!item) return;
  openOverlay("listing", item);
  $("feed")?.scrollIntoView({ block: "start" });
}

async function copyText(value, okMessage) {
  try {
    await navigator.clipboard.writeText(value);
    toast(okMessage);
  } catch {
    toast(value);
  }
}

function inPlacePhrase(name) {
  const raw = String(name || "").trim();
  if (!raw) return "в вашем селе";
  const m = raw.match(/^(село|посёлок|поселок|деревня|город)\s+(.+)$/i);
  if (!m) return `в ${raw}`;
  const kind = m[1].toLowerCase();
  const rest = m[2];
  if (kind === "село") return `в селе ${rest}`;
  if (kind === "деревня") return `в деревне ${rest}`;
  if (kind === "город") return `в городе ${rest}`;
  return `в посёлке ${rest}`;
}

function updateFeedPlace() {
  const el = $("feed-place");
  const sel = $("settlement-select");
  if (!el) return;
  if (!state.settlementId) {
    el.textContent = "Весь район";
    return;
  }
  const name = sel?.selectedOptions?.[0]?.textContent || "";
  el.textContent = name ? `Сначала то, что ближе к «${name}»` : "Как у вас рядом";
}

async function loadListings(append) {
  const params = new URLSearchParams({ limit: String(state.limit), offset: String(state.offset) });
  if (state.category) params.set("category", state.category);
  if (state.settlementId) {
    params.set("sort", "near");
    params.set("settlement_id", String(state.settlementId));
  }
  if (state.q) params.set("q", state.q);
  const grid = $("listing-grid");
  const empty = $("listing-empty");
  const more = $("load-more");
  try {
    const data = await getJson(`/api/listings?${params}`);
    const items = data?.items || [];
    state.total = data?.total || 0;
    if (!append) state.byId = {};
    items.forEach((item) => {
      state.byId[String(item.id)] = item;
    });
    const html = items.map((item) => listingCard(item)).join("");
    if (append) grid.insertAdjacentHTML("beforeend", html);
    else grid.innerHTML = html;
    if (empty) {
      empty.hidden = true;
      empty.textContent = "В этой категории пока тихо — загляните в приложение чуть позже.";
    }
    if (more) more.hidden = grid.children.length >= state.total;
    if (!append) await searchExtra();
    await updateFirstAuthor(grid.children.length > 0);
  } catch (err) {
    if (append) {
      toast("Не удалось подгрузить ленту. Попробуйте ещё раз.");
    } else {
      if (grid) grid.innerHTML = "";
      if (empty) {
        empty.hidden = false;
        empty.textContent = "Лента сейчас не открылась. Обновите страницу.";
      }
      if (more) more.hidden = true;
      toast("Лента не загрузилась");
    }
    throw err;
  }
}

async function updateFirstAuthor(hasCards) {
  const box = $("first-author");
  const text = $("first-author-text");
  const empty = $("listing-empty");
  const cta = $("first-author-cta");
  if (!box || !text) return;

  const gridEmpty = !hasCards;
  if (cta) cta.hidden = false;

  if (state.q && gridEmpty && state.searchHits > 0) {
    box.hidden = true;
    if (cta) cta.hidden = true;
    return;
  }
  if (state.q && gridEmpty) {
    text.textContent = "По такому запросу в ленте пока пусто. Попробуйте другое слово.";
    box.hidden = false;
    if (cta) cta.hidden = true;
    return;
  }

  let localTotal = null;
  if (state.settlementId) {
    const params = new URLSearchParams({ limit: "1", settlement_id: String(state.settlementId) });
    if (state.category) params.set("category", state.category);
    try {
      const local = await getJson(`/api/listings?${params}`);
      localTotal = local?.total || 0;
    } catch {
      localTotal = null;
    }
  }

  const place = $("settlement-select")?.selectedOptions?.[0]?.textContent?.trim() || "";
  const villageEmpty = Boolean(state.settlementId && localTotal === 0);

  if (villageEmpty) {
    text.textContent = `${inPlacePhrase(place).replace(/^в/, "В")} пока пусто — вы будете первым. Поставьте приложение и подайте.`;
    box.hidden = false;
    return;
  }
  if (gridEmpty) {
    text.textContent = state.category
      ? "В этой категории пока пусто — вы будете первым. Поставьте приложение и подайте."
      : "В районе пока пусто — вы будете первым. Поставьте приложение и подайте.";
    box.hidden = false;
    return;
  }
  box.hidden = true;
  if (empty) empty.hidden = true;
}

function fillEventLine(items) {
  const bar = $("event-line");
  const link = $("event-line-link");
  if (!bar || !link) return;
  const ev = items?.[0];
  if (!ev) {
    bar.hidden = true;
    link.textContent = "";
    delete link.dataset.id;
    delete link.dataset.kind;
    return;
  }
  const when = formatEventWhen(ev.starts_at, ev.ends_at);
  const settlement = String(ev.settlement_name || "").trim();
  const spot = String(ev.place_text || "").trim();
  let place = settlement || spot;
  if (settlement && spot && !settlement.includes(spot) && !spot.includes(settlement)) {
    place = `${spot}, ${settlement}`;
  }
  const rest = [escapeHtml(ev.title || "Событие"), escapeHtml(when), escapeHtml(place)].filter(Boolean).join(" · ");
  link.innerHTML = `<span class="event-kicker">Ближайшее</span> ${rest}`;
  link.dataset.id = String(ev.id);
  link.dataset.kind = "event";
  bar.hidden = false;
}

function departureScore(text) {
  const t = String(text || "").toLowerCase();
  const m = t.match(/(\d{1,2}):(\d{2})/);
  if (!m) return 99999;
  let n = Number(m[1]) * 60 + Number(m[2]);
  if (/завтра/i.test(t)) return n + 24 * 60;
  const names = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"];
  const hit = names.findIndex((d) => t.includes(d));
  if (hit >= 0) {
    const todayName = new Intl.DateTimeFormat("ru-RU", {
      timeZone: LOCAL_TZ,
      weekday: "short",
    })
      .format(new Date())
      .replace(".", "")
      .toLowerCase()
      .slice(0, 2);
    const today = names.findIndex((d) => todayName.startsWith(d) || d.startsWith(todayName));
    const todayIdx = today >= 0 ? today : new Date().getDay() === 0 ? 6 : new Date().getDay() - 1;
    let ahead = (hit - todayIdx + 7) % 7;
    if (ahead === 0) ahead = 7;
    n += ahead * 24 * 60;
  }
  return n;
}

async function loadBuses() {
  const el = $("bus-line");
  if (!el) return;
  const params = new URLSearchParams({ limit: "40", day: "today" });
  if (state.settlementId) params.set("settlement_id", String(state.settlementId));
  let items = [];
  try {
    const data = await getJson(`/api/transport?${params}`);
    items = data?.items || [];
  } catch {
    items = [];
  }
  const soon = items
    .filter((r) => r.next_departure)
    .sort((a, b) => departureScore(a.next_departure) - departureScore(b.next_departure))
    .slice(0, 3);
  if (!soon.length) {
    if (state.settlementId) {
      el.innerHTML = `<span class="event-kicker">Рейсы</span> В этом селе рейсов в справочнике пока нет.`;
      el.hidden = false;
    } else {
      el.hidden = true;
      el.textContent = "";
    }
    return;
  }
  const bits = soon.map((r) => {
    const name = r.title || "рейс";
    return `${name} · ${r.next_departure}`;
  });
  el.innerHTML = `<span class="event-kicker">Рейсы</span> ${escapeHtml(bits.join("  ·  "))}. Подробности — в приложении.`;
  el.hidden = false;
}

async function searchExtra() {
  const box = $("search-hits");
  const title = $("search-hits-title");
  const list = $("search-hits-list");
  if (!box || !list) return;
  if (!state.q) {
    state.searchHits = 0;
    box.hidden = true;
    list.innerHTML = "";
    return;
  }
  const q = encodeURIComponent(state.q);
  const [events, news] = await Promise.all([
    getJson(`/api/events?q=${q}&limit=3`).catch(() => null),
    getJson(`/api/news?q=${q}&limit=3`).catch(() => null),
  ]);
  const evItems = events?.items || [];
  const newsItems = news?.items || [];
  state.searchHits = evItems.length + newsItems.length;
  if (!state.searchHits) {
    box.hidden = true;
    list.innerHTML = "";
    return;
  }
  const rows = [
    ...evItems.map((ev) => {
      rememberStories("event", [ev]);
      return storyCard("event", ev, `Афиша · ${formatEventWhen(ev.starts_at, ev.ends_at)}`);
    }),
    ...newsItems.map((n) => {
      rememberStories("news", [n]);
      return storyCard("news", n, "Новость");
    }),
  ];
  if (title) title.textContent = "Ещё в афише и новостях";
  list.innerHTML = rows.join("");
  box.hidden = false;
}

async function loadNearbyLine() {
  const el = $("nearby-line");
  if (!el) return;
  const keys = [...SPOTLIGHT, "goods", "services", "rent"];
  const pages = await Promise.all(keys.map((c) => getJson(`/api/listings?category=${c}&limit=1`).catch(() => null)));
  const live = keys.filter((_, i) => (pages[i]?.total || 0) > 0).map((c) => CAT[c].toLowerCase());
  const shown = SPOTLIGHT.map((c) => CAT[c].toLowerCase()).filter((name) => live.includes(name));
  const names = shown.length ? shown : live;
  if (!names.length) {
    el.textContent = "Лента пока тихая — первые объявления появятся в приложении.";
    return;
  }
  el.innerHTML = `Сегодня в ленте: <b>${escapeHtml(names.join(", "))}</b>`;
}

function savedSelo() {
  const fromUrl = new URLSearchParams(location.search).get("s");
  if (fromUrl) return fromUrl;
  try {
    return localStorage.getItem(SELO_KEY) || "";
  } catch {
    return "";
  }
}

function persistSelo(id) {
  try {
    if (id) localStorage.setItem(SELO_KEY, id);
    else localStorage.removeItem(SELO_KEY);
  } catch {
    /* ignore */
  }
  const url = new URL(location.href);
  if (id) url.searchParams.set("s", id);
  else url.searchParams.delete("s");
  history.replaceState(null, "", url);
}

function fillSettlements(list) {
  if (!Array.isArray(list)) return;
  const feed = $("settlement-select");
  const contact = $("contact-settlement");
  [feed, contact].forEach((sel) => {
    if (!sel) return;
    list.forEach((s) => {
      const opt = document.createElement("option");
      opt.value = String(s.id);
      opt.textContent = s.display_name || s.name;
      sel.append(opt);
    });
  });
  if (feed) {
    if (state.settlementId && [...feed.options].some((o) => o.value === state.settlementId)) {
      feed.value = state.settlementId;
    } else {
      state.settlementId = "";
      feed.value = "";
    }
    updateFeedPlace();
  }
  if (contact && state.settlementId && [...contact.options].some((o) => o.value === state.settlementId)) {
    contact.value = state.settlementId;
  }
}

function apiError(data, fallback) {
  const detail = data?.detail;
  if (typeof detail === "string" && detail.trim()) return detail;
  return fallback;
}

function stampContactShown() {
  const el = $("contact-shown");
  if (el) el.value = String(Math.floor(Date.now() / 1000));
}

function bindContactForm() {
  const form = $("contact-form");
  const status = $("contact-status");
  const btn = $("contact-send");
  if (!form || !btn) return;
  stampContactShown();
  form.addEventListener("focusin", stampContactShown, { once: true });
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const name = ($("contact-name")?.value || "").trim();
    const sel = $("contact-settlement");
    const settlement = sel?.value ? sel.selectedOptions[0]?.textContent?.trim() || "" : "";
    const phone = ($("contact-phone")?.value || "").trim();
    const message = ($("contact-message")?.value || "").trim();
    const website = ($("contact-website")?.value || "").trim();
    const shown = Number($("contact-shown")?.value || 0);
    const consent = Boolean($("contact-consent")?.checked);
    if (status) {
      status.hidden = true;
      status.classList.remove("is-ok", "is-bad");
    }
    if (!consent) {
      const text = "Отметьте согласие на обработку персональных данных.";
      if (status) {
        status.textContent = text;
        status.classList.add("is-bad");
        status.hidden = false;
      }
      toast(text);
      return;
    }
    const elapsed = Math.floor(Date.now() / 1000) - shown;
    if (!shown || elapsed < 3) {
      const text = "Подождите пару секунд и отправьте ещё раз.";
      if (status) {
        status.textContent = text;
        status.classList.add("is-bad");
        status.hidden = false;
      }
      toast(text);
      return;
    }
    btn.disabled = true;
    const prev = btn.textContent;
    btn.textContent = "Отправляем…";
    try {
      const res = await fetch("/api/contact", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, settlement, phone, message, website, shown, consent: true }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        const text = apiError(data, "Не отправилось. Напишите на почту или позвоните.");
        if (status) {
          status.textContent = text;
          status.classList.add("is-bad");
          status.hidden = false;
        }
        toast(text);
        return;
      }
      const ok = data?.message || "Отправили.";
      if (status) {
        status.textContent = ok;
        status.classList.add("is-ok");
        status.hidden = false;
      }
      toast(ok);
      form.reset();
      stampContactShown();
      const selAfter = $("contact-settlement");
      if (selAfter && state.settlementId) selAfter.value = state.settlementId;
    } catch {
      const text = "Нет связи. Напишите на почту или позвоните.";
      if (status) {
        status.textContent = text;
        status.classList.add("is-bad");
        status.hidden = false;
      }
      toast(text);
    } finally {
      btn.disabled = false;
      btn.textContent = prev;
    }
  });
}

function bindOverlay() {
  $("overlay-close")?.addEventListener("click", (e) => {
    e.stopPropagation();
    closeOverlay();
  });
  $("overlay")?.addEventListener("click", (e) => {
    if (e.target === $("overlay")) closeOverlay();
  });
  $("overlay-cta")?.addEventListener("click", closeOverlay);
  $("overlay-prev")?.addEventListener("click", (e) => {
    e.stopPropagation();
    stepOverlayPhoto(-1);
  });
  $("overlay-next")?.addEventListener("click", (e) => {
    e.stopPropagation();
    stepOverlayPhoto(1);
  });
  $("overlay-img")?.addEventListener("click", () => stepOverlayPhoto(1));
  document.addEventListener("keydown", (e) => {
    if ($("overlay")?.hidden) return;
    if (e.key === "Escape") closeOverlay();
    if (e.key === "ArrowLeft") stepOverlayPhoto(-1);
    if (e.key === "ArrowRight") stepOverlayPhoto(1);
  });

  document.querySelectorAll(".shot").forEach((btn) => {
    btn.addEventListener("click", () => {
      openOverlay("shot", { src: btn.dataset.shot, title: btn.dataset.caption });
    });
  });

  $("overlay-share")?.addEventListener("click", async () => {
    const id = $("overlay-share")?.dataset.id;
    if (!id) return;
    await copyText(listingUrl(id), "Ссылка на объявление скопирована");
  });
  function onStoryClick(e) {
    const card = e.target.closest("[data-kind][data-id]");
    if (!card) return;
    openStory(card.dataset.kind, card.dataset.id);
  }
  function onStoryKey(e) {
    if (e.key !== "Enter" && e.key !== " ") return;
    const card = e.target.closest("[data-kind][data-id]");
    if (!card) return;
    e.preventDefault();
    openStory(card.dataset.kind, card.dataset.id);
  }
  ["events-list", "news-list", "search-hits-list"].forEach((id) => {
    $(id)?.addEventListener("click", onStoryClick);
    $(id)?.addEventListener("keydown", onStoryKey);
  });
  $("event-line-link")?.addEventListener("click", (e) => {
    const id = e.currentTarget.dataset.id;
    if (!id) return;
    e.preventDefault();
    openStory("event", id);
  });
  document.querySelectorAll("a[href^='tel:']").forEach((a) => {
    a.addEventListener("click", async (e) => {
      const coarse = window.matchMedia && window.matchMedia("(pointer: coarse)").matches;
      if (coarse) return;
      e.preventDefault();
      const num = (a.getAttribute("href") || "").replace(/^tel:/, "");
      await copyText(num, "Номер скопирован");
    });
  });
  $("listing-grid")?.addEventListener("click", (e) => {
    const card = e.target.closest("[data-id]");
    if (card) openListing(card.dataset.id);
  });
  $("listing-grid")?.addEventListener("keydown", (e) => {
    if (e.key !== "Enter" && e.key !== " ") return;
    const card = e.target.closest("[data-id]");
    if (!card) return;
    e.preventDefault();
    openListing(card.dataset.id);
  });
}

function bindDock() {
  const hero = document.querySelector(".hero");
  if (!hero || isIos()) return;
  if (!("IntersectionObserver" in window)) return;
  const io = new IntersectionObserver(
    ([entry]) => {
      document.body.classList.toggle("dock-on", Boolean(entry) && !entry.isIntersecting);
    },
    { threshold: 0.12 },
  );
  io.observe(hero);
}

function loadInstallShots() {
  document.querySelectorAll("#install-help img[data-src]").forEach((img) => {
    img.src = img.dataset.src;
  });
}

function openFoldFromHash() {
  const hash = location.hash.replace("#", "");
  if (hash === "install-help") {
    $("install-help")?.setAttribute("open", "");
    loadInstallShots();
  }
  if (hash === "how") $("how")?.setAttribute("open", "");
}

function bindFolds() {
  openFoldFromHash();
  window.addEventListener("hashchange", openFoldFromHash);
  $("install-help")?.addEventListener("toggle", () => {
    if ($("install-help")?.open) loadInstallShots();
  });
  document.querySelectorAll('a[href="#install-help"], a[href="#how"]').forEach((a) => {
    a.addEventListener("click", () => {
      window.setTimeout(openFoldFromHash, 0);
    });
  });
}

async function boot() {
  $("year").textContent = String(new Date().getFullYear());
  state.settlementId = savedSelo();

  if (isIos()) {
    document.body.classList.add("is-ios");
    const banner = $("ios-banner");
    if (banner) banner.hidden = false;
    disableApk();
  }

  bindOverlay();
  bindContactForm();
  bindDock();
  bindFolds();
  document.querySelectorAll(".js-share-site").forEach((el) => {
    el.addEventListener("click", shareSite);
  });

  const menuBtn = document.querySelector(".menu-btn");
  const mobileNav = $("mobile-nav");

  function closeMenu() {
    if (!mobileNav) return;
    mobileNav.hidden = true;
    menuBtn?.setAttribute("aria-expanded", "false");
  }

  menuBtn?.addEventListener("click", () => {
    const open = mobileNav.hidden;
    mobileNav.hidden = !open;
    menuBtn.setAttribute("aria-expanded", String(open));
  });
  mobileNav?.querySelectorAll("a").forEach((a) => a.addEventListener("click", closeMenu));
  window.addEventListener("resize", () => {
    if (window.innerWidth > 760) closeMenu();
  });

  window.addEventListener("scroll", () => {
    document.querySelector(".top")?.classList.toggle("scrolled", window.scrollY > 8);
  });

  document.querySelectorAll(".feed-toolbar .chip").forEach((btn) => {
    btn.addEventListener("click", async () => {
      document.querySelectorAll(".feed-toolbar .chip").forEach((el) => el.classList.remove("on"));
      btn.classList.add("on");
      state.category = btn.dataset.cat || "";
      state.offset = 0;
      try {
        await loadListings(false);
      } catch {
        $("listing-empty").hidden = false;
      }
    });
  });

  const qInput = $("feed-q");
  let qTimer = 0;
  async function applySearch() {
    state.q = (qInput?.value || "").trim().slice(0, 80);
    state.offset = 0;
    try {
      await loadListings(false);
    } catch {
      $("listing-empty").hidden = false;
    }
  }
  qInput?.addEventListener("input", () => {
    window.clearTimeout(qTimer);
    qTimer = window.setTimeout(applySearch, 280);
  });
  qInput?.addEventListener("keydown", (e) => {
    if (e.key !== "Enter") return;
    e.preventDefault();
    window.clearTimeout(qTimer);
    applySearch();
  });

  $("settlement-select")?.addEventListener("change", async (e) => {
    state.settlementId = e.target.value || "";
    state.offset = 0;
    persistSelo(state.settlementId);
    updateFeedPlace();
    const contactSel = $("contact-settlement");
    if (contactSel) contactSel.value = state.settlementId;
    void loadBuses();
    try {
      await loadListings(false);
    } catch {
      $("listing-empty").hidden = false;
    }
  });

  $("load-more")?.addEventListener("click", async () => {
    const prev = state.offset;
    state.offset += state.limit;
    try {
      await loadListings(true);
    } catch {
      state.offset = prev;
      toast("Не удалось подгрузить ленту. Попробуйте ещё раз.");
    }
  });

  let taps = 0;
  let tapTimer = 0;
  $("year")?.addEventListener("click", () => {
    taps += 1;
    window.clearTimeout(tapTimer);
    tapTimer = window.setTimeout(() => {
      taps = 0;
    }, 1800);
    if (taps >= 7) window.location.href = "/console/";
  });

  const [update, listingsOk, directory, events, news, settlements, alert, nearbyOk] = await Promise.allSettled([
    getJson("/api/app/update"),
    loadListings(false),
    getJson("/api/directory?limit=1"),
    getJson("/api/events?upcoming=true&limit=4"),
    getJson("/api/news?limit=3"),
    getJson("/api/settlements"),
    getJson("/api/alerts/active"),
    loadNearbyLine(),
    loadBuses(),
  ]);

  if (update.status === "fulfilled" && update.value) {
    const info = update.value;
    const ver = info.version ? `Сейчас на сайте версия ${info.version}` : "Для Андроид";
    $("version-line").textContent = info.has_apk
      ? "Можно ставить на телефон прямо с этого сайта"
      : "Файл для установки скоро появится";
    $("download-meta").textContent = info.has_apk ? ver : "Файл для установки скоро появится";
    if (!info.has_apk) disableApk();
  }

  if (listingsOk.status === "fulfilled") {
    $("stat-listings").textContent = String(state.total);
  }
  if (directory.status === "fulfilled") {
    $("stat-places").textContent = String(directory.value?.total ?? "—");
  }
  if (events.status === "fulfilled") {
    const items = events.value?.items || [];
    $("stat-events").textContent = String(events.value?.total ?? items.length);
    fillEventLine(items);
    rememberStories("event", items);
    $("events-list").innerHTML =
      items.map((ev) => storyCard("event", ev, formatEventWhen(ev.starts_at, ev.ends_at))).join("") ||
      `<article><p class="muted">Ближайших событий пока нет — они появятся в афише приложения.</p></article>`;
  } else {
    fillEventLine([]);
    $("events-list").innerHTML = `<article><p class="muted">Афиша сейчас не открылась. Обновите страницу.</p></article>`;
  }
  if (news.status === "fulfilled") {
    const items = news.value?.items || [];
    rememberStories("news", items);
    $("news-list").innerHTML =
      items.map((n) => storyCard("news", n, "Новость")).join("") ||
      `<article><p class="muted">Новости района публикуются в приложении.</p></article>`;
  } else {
    $("news-list").innerHTML = `<article><p class="muted">Новости сейчас не открылись. Обновите страницу.</p></article>`;
  }
  if (settlements.status === "fulfilled" && Array.isArray(settlements.value)) {
    const names = settlements.value.map((s) => s.display_name || s.name).filter(Boolean);
    $("stat-settlements").textContent = String(names.length || 48);
    const line = names
      .slice(0, 6)
      .map((n) => String(n).replace(/^(село|посёлок|поселок|деревня)\s+/i, ""))
      .join(" · ");
    const track = $("settlement-ticker");
    if (track) track.textContent = line ? `${line} · ${line}` : track.textContent;
    fillSettlements(settlements.value);
    if (state.settlementId) {
      await updateFirstAuthor(($("listing-grid")?.children.length || 0) > 0);
    }
  }
  if (alert.status === "fulfilled" && alert.value?.message) {
    const bar = $("alert-banner");
    if (bar) {
      bar.hidden = false;
      bar.textContent = alert.value.message;
      bar.classList.toggle("is-danger", alert.value.kind === "danger");
      bar.classList.toggle("is-warn", alert.value.kind === "warn");
      bar.classList.toggle("is-info", !alert.value.kind || alert.value.kind === "info");
    }
  }
  void nearbyOk;
  await openListingDeep(requestedListingId());
}

function bootPresence() {
  const key = "ryadom56.presence";
  let id = "";
  try {
    id = localStorage.getItem(key) || "";
  } catch (_) {}
  if (!id || id.length < 8) {
    id = `${Date.now()}${Math.random().toString(16).slice(2)}${Math.random().toString(16).slice(2)}`.replace(
      /[^a-zA-Z0-9_-]/g,
      ""
    );
    if (id.length < 8) id = `${Date.now()}ryadom56`;
    try {
      localStorage.setItem(key, id);
    } catch (_) {}
  }
  const ping = () => {
    fetch("/api/presence/ping", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ source: "site", client_id: id }),
      keepalive: true,
    }).catch(() => {});
  };
  ping();
  setInterval(ping, 90000);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") ping();
  });
}

boot().catch(() => {
  $("version-line").textContent = "Скачайте приложение для Андроид — лента откроется на телефоне.";
});
bootPresence();
