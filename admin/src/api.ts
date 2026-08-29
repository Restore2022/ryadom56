function resolveApiUrl(): string {
  const fromEnv = import.meta.env.VITE_API_URL as string | undefined;
  if (fromEnv && fromEnv.trim()) return fromEnv.trim().replace(/\/$/, '');
  // В проде админка и API на одном origin — без локальных адресов в бандле
  if (typeof window !== 'undefined' && window.location?.origin) {
    return `${window.location.origin}/api`;
  }
  return '/api';
}

const API_URL = resolveApiUrl();
const MEDIA_BASE = API_URL.replace(/\/api\/?$/, '');

export function mediaUrl(path?: string | null) {
  if (!path) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return `${MEDIA_BASE}${path.startsWith('/') ? path : `/${path}`}`;
}

function getToken() {
  return localStorage.getItem('ryadom56_token');
}

export function setToken(token: string | null) {
  if (token) localStorage.setItem('ryadom56_token', token);
  else localStorage.removeItem('ryadom56_token');
}

function friendlyDetail(detail: unknown, status: number): string {
  if (typeof detail === 'string' && detail.trim()) {
    if (detail.length < 240 && !detail.startsWith('<')) return detail;
  }
  if (Array.isArray(detail)) {
    return detail
      .map((e) => {
        if (e && typeof e === 'object' && 'msg' in e) return String((e as { msg: string }).msg);
        return String(e);
      })
      .join('; ');
  }
  if (status === 401) return 'Сессия истекла. Войдите снова';
  if (status === 403) return 'Нет доступа';
  if (status === 404) return 'Не найдено';
  if (status >= 500) return 'Ошибка сервера. Попробуйте позже';
  return 'Не удалось выполнить запрос';
}

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers || {});
  if (!(options.body instanceof FormData)) {
    headers.set('Content-Type', 'application/json');
  }
  const token = getToken();
  if (token) headers.set('Authorization', `Bearer ${token}`);

  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, { ...options, headers });
  } catch {
    throw new Error('Нет связи с сервером. Проверьте, что API запущен.');
  }

  if (!res.ok) {
    let detail: unknown = 'Ошибка запроса';
    try {
      const data = await res.json();
      detail = data.detail ?? data;
    } catch {
      /* ignore */
    }
    const authCall =
      path.startsWith('/auth/login') ||
      path.startsWith('/auth/register') ||
      path.startsWith('/auth/forgot-password') ||
      path.startsWith('/auth/reset-password');
    if (res.status === 401 && !authCall) {
      setToken(null);
      try {
        sessionStorage.setItem('ryadom56.loginMsg', 'Сессия истекла. Войдите снова');
      } catch {
        /* ignore */
      }
      window.dispatchEvent(new CustomEvent('ryadom56:unauthorized'));
      throw new Error('Сессия истекла. Войдите снова');
    }
    if (res.status === 401 && authCall) {
      throw new Error(typeof detail === 'string' && detail.trim() ? detail : 'Неверный email или пароль');
    }
    throw new Error(friendlyDetail(detail, res.status));
  }
  if (res.status === 204) return undefined as T;
  const text = await res.text();
  if (!text) return undefined as T;
  return JSON.parse(text) as T;
}

export async function apiText(path: string): Promise<string> {
  const headers = new Headers();
  const token = getToken();
  if (token) headers.set('Authorization', `Bearer ${token}`);
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, { headers });
  } catch {
    throw new Error('Нет связи с сервером. Проверьте, что API запущен.');
  }
  if (res.status === 401) {
    setToken(null);
    try {
      sessionStorage.setItem('ryadom56.loginMsg', 'Сессия истекла. Войдите снова');
    } catch {
      /* ignore */
    }
    window.dispatchEvent(new CustomEvent('ryadom56:unauthorized'));
    throw new Error('Сессия истекла. Войдите снова');
  }
  if (!res.ok) throw new Error('Ошибка экспорта');
  return res.text();
}

export async function apiDownload(path: string, filename: string): Promise<void> {
  const headers = new Headers();
  const token = getToken();
  if (token) headers.set('Authorization', `Bearer ${token}`);
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, { headers });
  } catch {
    throw new Error('Нет связи с сервером. Проверьте, что API запущен.');
  }
  if (res.status === 401) {
    setToken(null);
    try {
      sessionStorage.setItem('ryadom56.loginMsg', 'Сессия истекла. Войдите снова');
    } catch {
      /* ignore */
    }
    window.dispatchEvent(new CustomEvent('ryadom56:unauthorized'));
    throw new Error('Сессия истекла. Войдите снова');
  }
  if (!res.ok) {
    let detail = 'Ошибка скачивания';
    try {
      const data = await res.json();
      if (typeof data?.detail === 'string') detail = data.detail;
    } catch {
      /* ignore */
    }
    throw new Error(detail);
  }
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export type User = {
  id: number;
  email: string;
  full_name: string;
  phone?: string | null;
  settlement_id: number;
  settlement?: Settlement | null;
  role: 'user' | 'moderator' | 'editor' | 'admin';
  is_active: boolean;
  ban_reason?: string | null;
  created_at?: string;
  last_ip?: string | null;
  device_brand?: string | null;
  device_model?: string | null;
  device_os?: string | null;
  app_version?: string | null;
  device_info?: string | null;
  last_seen_at?: string | null;
  badge?: string | null;
  has_push?: boolean;
};

export type ListingSnapshot = {
  title?: string | null;
  description?: string | null;
  category?: string | null;
  price?: number | null;
  contact_phone?: string | null;
  is_urgent?: boolean | null;
};

export type Listing = {
  id: number;
  title: string;
  description: string;
  category: string;
  status: string;
  price?: number | null;
  settlement_id?: number;
  settlement_name?: string | null;
  author_id?: number;
  author_name?: string | null;
  contact_phone?: string | null;
  moderation_note?: string | null;
  close_reason?: string | null;
  close_note?: string | null;
  is_urgent?: boolean;
  is_pinned?: boolean;
  auto_flagged?: boolean;
  previous_snapshot?: ListingSnapshot | null;
  images?: { id: number; url: string; sort_order: number }[];
  created_at: string;
  updated_at?: string;
  lifetime_days?: number;
  expires_at?: string | null;
};

export type ListingReport = {
  id: number;
  listing_id: number;
  listing_title?: string | null;
  reporter_id: number;
  reporter_name?: string | null;
  reason: string;
  note?: string | null;
  moderator_reply?: string | null;
  status: string;
  created_at: string;
};

export type DirectoryReport = {
  id: number;
  directory_id: number;
  directory_title?: string | null;
  reporter_id: number;
  reporter_name?: string | null;
  reason: string;
  note?: string | null;
  moderator_reply?: string | null;
  status: string;
  created_at: string;
};

export type UserReport = {
  id: number;
  target_id: number;
  target_name?: string | null;
  reporter_id: number;
  reporter_name?: string | null;
  listing_id?: number | null;
  listing_title?: string | null;
  reason: string;
  note?: string | null;
  moderator_reply?: string | null;
  status: string;
  created_at: string;
};

export type AuditLog = {
  id: number;
  actor_id: number;
  actor_name?: string | null;
  actor_role?: string | null;
  action: string;
  entity_type: string;
  entity_id?: number | null;
  details?: string | null;
  created_at: string;
};

export type ClientErrorLog = {
  id: number;
  created_at: string;
  user_id?: number | null;
  user_name?: string | null;
  message: string;
  stack?: string | null;
  screen?: string | null;
  app_version?: string | null;
  device_brand?: string | null;
  device_model?: string | null;
  device_os?: string | null;
  client_ip?: string | null;
};

export type AdminConversation = {
  listing_id: number;
  buyer_id: number;
  listing_title: string;
  listing_status: string;
  seller_id: number;
  seller_name?: string | null;
  buyer_name?: string | null;
  last_message?: string | null;
  last_message_at?: string | null;
  message_count: number;
  flagged: boolean;
  flag_reasons: string[];
};

export type AdminChatMessage = {
  id: number;
  listing_id: number;
  buyer_id?: number | null;
  sender_id: number;
  sender_name?: string | null;
  body: string;
  created_at: string;
  flagged: boolean;
  flag_reasons: string[];
  kind?: string;
  is_read?: boolean;
};

export type DirectoryItem = {
  id: number;
  title: string;
  category: string;
  settlement_id?: number | null;
  settlement_name?: string | null;
  description?: string | null;
  address?: string | null;
  phone?: string | null;
  website?: string | null;
  hours?: string | null;
  lat?: number | null;
  lon?: number | null;
  is_published: boolean;
  view_count?: number;
};

export type Settlement = {
  id: number;
  display_name: string;
  name: string;
};

export type Stats = {
  users: number;
  listings_pending: number;
  listings_approved: number;
  directory_items: number;
  settlements: number;
  pending_over_24h?: number;
  open_reports?: number;
  moderated_approved_30d?: number;
  moderated_rejected_30d?: number;
  moderation_conversion?: number | null;
  listings_per_day?: { day: string; count: number }[];
  top_categories?: { category: string; count: number }[];
  events_total?: number;
  events_upcoming?: number;
  transport_routes?: number;
  news_total?: number;
  active_alerts?: number;
  top_events?: { id: number; title: string; views: number; favorites?: number }[];
  top_routes?: { id: number; title: string; views: number; favorites?: number }[];
  transport_favorites_total?: number;
  listing_favorites_total?: number;
  directory_favorites_total?: number;
  event_favorite_adds_total?: number;
  open_directory_reports?: number;
  open_contacts?: number;
  online_site?: number;
  online_app?: number;
  online_app_users?: number;
  online_app_guests?: number;
  users_new_7d?: number;
  users_new_today?: number;
  users_older?: number;
  users_active_30d?: number;
  online_calls?: number;
  site_today?: number;
  app_guests_today?: number;
  by_settlement?: {
    settlement_id?: number | null;
    settlement_name: string;
    listings_count: number;
    directory_opens: number;
  }[];
};

export type EventItem = {
  id: number;
  title: string;
  description: string;
  starts_at: string;
  ends_at?: string | null;
  place_text: string;
  settlement_id?: number | null;
  settlement_name?: string | null;
  address?: string | null;
  lat?: number | null;
  lon?: number | null;
  cover_url?: string | null;
  publish_at?: string | null;
  is_published: boolean;
  view_count?: number;
  status?: 'draft' | 'scheduled' | 'published' | string;
  created_at: string;
  updated_at: string;
};

export type TransportStop = {
  id: number;
  name: string;
  settlement_id?: number | null;
  created_at: string;
};

export type TransportTrip = {
  depart: string;
  arrive?: string | null;
  days: string[];
  days_label: string;
};

export type TransportRoute = {
  id: number;
  title: string;
  route_number?: string | null;
  description?: string | null;
  schedule_text: string;
  schedule_weekdays?: string | null;
  schedule_weekends?: string | null;
  stops_text?: string | null;
  stops?: string[];
  stop_points?: TransportStop[];
  times?: string[];
  trips?: TransportTrip[];
  days_mode?: 'all' | 'weekdays' | 'weekends' | string;
  notes?: string | null;
  fare_text?: string | null;
  phone?: string | null;
  next_departure?: string | null;
  settlement_id?: number | null;
  settlement_name?: string | null;
  is_published: boolean;
  view_count?: number;
  favorite_count?: number;
  outdated_reports?: number;
  created_at: string;
  updated_at: string;
};

export type NewsItem = {
  id: number;
  title: string;
  body: string;
  cover_url?: string | null;
  settlement_id?: number | null;
  settlement_name?: string | null;
  is_published: boolean;
  is_pinned?: boolean;
  published_at?: string | null;
  created_at: string;
  updated_at: string;
};

export type DistrictAlert = {
  id: number;
  message: string;
  kind: 'info' | 'warn' | 'danger' | string;
  priority?: number;
  is_active: boolean;
  starts_at?: string | null;
  ends_at?: string | null;
  created_at: string;
  updated_at: string;
};

export type AdminAlerts = {
  pending: number;
  pending_over_24h: number;
  open_reports: number;
};

export type BlacklistEntry = {
  id: number;
  kind: 'phone' | 'word' | string;
  value: string;
  note?: string | null;
  created_at: string;
};

export type SiteContact = {
  id: number;
  name: string;
  settlement?: string | null;
  phone?: string | null;
  message: string;
  ip?: string | null;
  status: 'new' | 'read' | 'done' | string;
  created_at: string;
};

export type BackupFile = {
  name: string;
  size: number;
  created_at: string;
};

export type BackupList = {
  items: BackupFile[];
  disk_free_mb?: number;
  disk_total_mb?: number;
  data_dir_mb?: number;
};

export type LegalDocument = {
  slug: string;
  title: string;
  body: string;
  version: string;
  updated_at: string;
};

export type AppCall = {
  id: number;
  listing_id: number;
  listing_title?: string | null;
  caller_id: number;
  caller_name?: string | null;
  callee_id: number;
  callee_name?: string | null;
  status: string;
  created_at: string;
  answered_at?: string | null;
  ended_at?: string | null;
  duration_sec: number;
  end_reason?: string | null;
  ended_by_id?: number | null;
  ended_by_name?: string | null;
};

export type AppUpdateInfo = {
  version: string;
  build: number;
  force: boolean;
  notes?: string | null;
  has_apk: boolean;
  download_url?: string | null;
  published_at?: string | null;
  apk_filename?: string | null;
  apk_size?: number | null;
};
