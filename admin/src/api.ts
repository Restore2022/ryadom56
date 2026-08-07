const API_URL = import.meta.env.VITE_API_URL || 'http://127.0.0.1:8000/api';
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

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers || {});
  headers.set('Content-Type', 'application/json');
  const token = getToken();
  if (token) headers.set('Authorization', `Bearer ${token}`);

  const res = await fetch(`${API_URL}${path}`, { ...options, headers });
  if (!res.ok) {
    let detail = 'Ошибка запроса';
    try {
      const data = await res.json();
      detail = data.detail || JSON.stringify(data);
    } catch {
      /* ignore */
    }
    throw new Error(typeof detail === 'string' ? detail : JSON.stringify(detail));
  }
  if (res.status === 204) return undefined as T;
  return res.json();
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
  created_at?: string;
  last_ip?: string | null;
  device_brand?: string | null;
  device_model?: string | null;
  device_os?: string | null;
  app_version?: string | null;
  device_info?: string | null;
  last_seen_at?: string | null;
};

export type Listing = {
  id: number;
  title: string;
  description: string;
  category: string;
  status: string;
  price?: number | null;
  settlement_name?: string | null;
  author_id?: number;
  author_name?: string | null;
  contact_phone?: string | null;
  moderation_note?: string | null;
  close_reason?: string | null;
  close_note?: string | null;
  images?: { id: number; url: string; sort_order: number }[];
  created_at: string;
};

export type ListingReport = {
  id: number;
  listing_id: number;
  listing_title?: string | null;
  reporter_id: number;
  reporter_name?: string | null;
  reason: string;
  note?: string | null;
  status: string;
  created_at: string;
};

export type AuditLog = {
  id: number;
  actor_id: number;
  actor_name?: string | null;
  action: string;
  entity_type: string;
  entity_id?: number | null;
  details?: string | null;
  created_at: string;
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
};
