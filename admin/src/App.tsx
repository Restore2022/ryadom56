import { useEffect, useMemo, useState } from 'react';
import { Navigate, NavLink, Route, Routes, useNavigate, useSearchParams } from 'react-router-dom';
import { api, apiDownload, apiText, mediaUrl, setToken } from './api';
import type {
  AuditLog,
  BlacklistEntry,
  DirectoryItem,
  AppUpdateInfo,
  DistrictAlert,
  EventItem,
  LegalDocument,
  Listing,
  ListingReport,
  NewsItem,
  Settlement,
  Stats,
  TransportRoute,
  User,
} from './api';
import './App.css';

const REJECTION_TEMPLATES = [
  'Недостаточно информации в описании',
  'Не подходит под правила раздела',
  'Подозрение на спам или рекламу',
  'Запрещённый или сомнительный товар/услуга',
  'Некорректные контакты или вводящее в заблуждение',
];

function needsModeration(item: Listing) {
  return item.status === 'pending';
}

function hoursWaiting(iso: string) {
  const ms = Date.now() - new Date(iso).getTime();
  return Math.max(0, Math.floor(ms / 3600000));
}

function canModerate(role: User['role']) {
  return role === 'admin' || role === 'moderator';
}

function canEditDirectory(role: User['role']) {
  return role === 'admin' || role === 'editor';
}

function isValidEmail(value: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim());
}

async function confirmAction(message: string): Promise<boolean> {
  return window.confirm(message);
}

function ToastHost({ message, onClose }: { message: string; onClose: () => void }) {
  useEffect(() => {
    const id = window.setTimeout(onClose, 4500);
    return () => window.clearTimeout(id);
  }, [message, onClose]);
  return (
    <div className="toast" role="status">
      <span>{message}</span>
      <button type="button" className="btn ghost" onClick={onClose}>
        Закрыть
      </button>
    </div>
  );
}

function PhotoGallery({ images }: { images: { id: number; url: string }[] }) {
  const [index, setIndex] = useState<number | null>(null);
  const urls = images.map((img) => mediaUrl(img.url)).filter(Boolean);

  useEffect(() => {
    if (index == null) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setIndex(null);
      if (e.key === 'ArrowRight') setIndex((i) => (i == null ? i : (i + 1) % urls.length));
      if (e.key === 'ArrowLeft') setIndex((i) => (i == null ? i : (i - 1 + urls.length) % urls.length));
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [index, urls.length]);

  if (!urls.length) return null;

  return (
    <>
      <div className="photo-row">
        {urls.map((url, i) => (
          <button key={images[i]?.id ?? url} type="button" className="photo-thumb" onClick={() => setIndex(i)}>
            <img src={url} alt="" />
          </button>
        ))}
      </div>
      {index != null && (
        <div className="lightbox" onClick={() => setIndex(null)} role="dialog" aria-modal="true">
          <button type="button" className="lightbox-close" onClick={() => setIndex(null)} aria-label="Закрыть">
            ×
          </button>
          {urls.length > 1 && (
            <button
              type="button"
              className="lightbox-nav prev"
              onClick={(e) => {
                e.stopPropagation();
                setIndex((i) => (i == null ? 0 : (i - 1 + urls.length) % urls.length));
              }}
              aria-label="Предыдущее"
            >
              ‹
            </button>
          )}
          <img
            className="lightbox-img"
            src={urls[index]}
            alt=""
            onClick={(e) => e.stopPropagation()}
          />
          {urls.length > 1 && (
            <button
              type="button"
              className="lightbox-nav next"
              onClick={(e) => {
                e.stopPropagation();
                setIndex((i) => (i == null ? 0 : (i + 1) % urls.length));
              }}
              aria-label="Следующее"
            >
              ›
            </button>
          )}
          <div className="lightbox-counter" onClick={(e) => e.stopPropagation()}>
            {index + 1} / {urls.length}
          </div>
        </div>
      )}
    </>
  );
}

const CATEGORY_LABELS: Record<string, string> = {
  goods: 'Товары',
  services: 'Услуги',
  jobs: 'Работа',
  rent: 'Аренда',
  free: 'Отдам',
  lost_found: 'Потеряшки',
  school: 'Школа',
  hospital: 'Больница',
  shop: 'Магазин',
  pharmacy: 'Аптека',
  admin: 'Администрация',
  bank: 'Банк',
  post: 'Почта',
  transport: 'Транспорт',
  culture: 'Культура',
  sport: 'Спорт',
  other: 'Другое',
};

const ROLE_LABELS: Record<User['role'], string> = {
  user: 'Пользователь',
  moderator: 'Модератор',
  editor: 'Редактор',
  admin: 'Админ',
};

const STATUS_CHIP: Record<string, string> = {
  pending: 'chip warn',
  approved: 'chip ok',
  rejected: 'chip danger',
  archived: 'chip neutral',
};

const STATUS_LABEL: Record<string, string> = {
  pending: 'На проверке',
  approved: 'Опубликовано',
  rejected: 'Отклонено',
  archived: 'Снято',
  draft: 'Черновик',
};

const CLOSE_REASON_LABEL: Record<string, string> = {
  sold: 'Продали / отдали',
  not_relevant: 'Неактуально',
  busy: 'Пока занят',
  other: 'Другое',
};

const REPORT_REASON_LABEL: Record<string, string> = {
  spam: 'Спам',
  fraud: 'Мошенничество',
  prohibited: 'Запрещённый контент',
  other: 'Другое',
};

const REPORT_STATUS_LABEL: Record<string, string> = {
  open: 'Открыта',
  reviewed: 'Просмотрена',
  dismissed: 'Отклонена',
};

function toDatetimeLocal(value?: string | null) {
  if (!value) return '';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromDatetimeLocal(value: string): string {
  return new Date(value).toISOString();
}

function formatDate(value?: string | null) {
  if (!value) return '—';
  try {
    return new Date(value).toLocaleString('ru-RU');
  } catch {
    return value;
  }
}

function useTheme() {
  const [theme, setTheme] = useState<'light' | 'dark'>(() => {
    const saved = localStorage.getItem('ryadom56_admin_theme');
    if (saved === 'dark' || saved === 'light') return saved;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  });

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('ryadom56_admin_theme', theme);
  }, [theme]);

  return {
    theme,
    toggle: () => setTheme((t) => (t === 'dark' ? 'light' : 'dark')),
  };
}

function useAuth() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api<User>('/auth/me')
      .then(setUser)
      .catch(() => setUser(null))
      .finally(() => setLoading(false));
  }, []);

  return { user, setUser, loading };
}

function LoginPage({ onLogin }: { onLogin: (u: User) => void }) {
  const [email, setEmail] = useState('admin@ryadom56.ru');
  const [password, setPassword] = useState('admin123');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!isValidEmail(email)) {
      setError('Введите корректный email');
      return;
    }
    if (!password.trim()) {
      setError('Введите пароль');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const token = await api<{ access_token: string }>('/auth/login', {
        method: 'POST',
        body: JSON.stringify({ email: email.trim(), password }),
      });
      setToken(token.access_token);
      const me = await api<User>('/auth/me');
      if (!['admin', 'moderator', 'editor'].includes(me.role)) {
        setToken(null);
        throw new Error('Нет доступа в админку для этой роли');
      }
      onLogin(me);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Ошибка входа';
      setError(msg.includes('Сессия') || msg.includes('401') ? 'Неверный email или пароль' : msg);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <form className="login-card" onSubmit={submit}>
        <p className="brand">Рядом56</p>
        <h1>Панель управления</h1>
        <p className="login-sub">Модерация объявлений и справочник района</p>
        <label>
          Email
          <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" required />
        </label>
        <label>
          Пароль
          <input value={password} onChange={(e) => setPassword(e.target.value)} type="password" required />
        </label>
        {error && <p className="error">{error}</p>}
        <button disabled={busy}>{busy ? 'Вход…' : 'Войти'}</button>
      </form>
    </div>
  );
}

function Shell({
  user,
  onLogout,
  theme,
  onToggleTheme,
  children,
}: {
  user: User;
  onLogout: () => void;
  theme: 'light' | 'dark';
  onToggleTheme: () => void;
  children: React.ReactNode;
}) {
  const mod = canModerate(user.role);
  const directory = canEditDirectory(user.role);
  const [toast, setToast] = useState('');

  useEffect(() => {
    function onUnauthorized() {
      setToast('Сессия истекла. Войдите снова');
      onLogout();
    }
    function onToast(e: Event) {
      const detail = (e as CustomEvent<string>).detail;
      if (detail) setToast(detail);
    }
    window.addEventListener('ryadom56:unauthorized', onUnauthorized);
    window.addEventListener('ryadom56:toast', onToast as EventListener);
    return () => {
      window.removeEventListener('ryadom56:unauthorized', onUnauthorized);
      window.removeEventListener('ryadom56:toast', onToast as EventListener);
    };
  }, [onLogout]);

  useEffect(() => {
    if (!mod) return;
    let lastPending = -1;
    let stopped = false;

    async function tick() {
      try {
        const alerts = await api<{ pending: number; pending_over_24h: number; open_reports: number }>('/admin/alerts');
        if (stopped) return;
        if (lastPending >= 0 && alerts.pending > lastPending && 'Notification' in window) {
          if (Notification.permission === 'granted') {
            new Notification('Рядом56: новые объявления', {
              body: `На проверке: ${alerts.pending}` + (alerts.pending_over_24h ? ` · старше 24ч: ${alerts.pending_over_24h}` : ''),
            });
          }
        }
        lastPending = alerts.pending;
      } catch {
        /* ignore */
      }
    }

    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission().catch(() => undefined);
    }
    tick();
    const id = window.setInterval(tick, 45000);
    return () => {
      stopped = true;
      window.clearInterval(id);
    };
  }, [mod]);

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="aside-brand">
          <strong>Рядом56</strong>
          <span>админ-панель</span>
        </div>
        <nav>
          <NavLink to="/" end>
            <span className="nav-ico">◈</span> Сводка
          </NavLink>
          {mod && (
            <NavLink to="/moderation">
              <span className="nav-ico">☰</span> Модерация
            </NavLink>
          )}
          {mod && (
            <NavLink to="/reports">
              <span className="nav-ico">!</span> Жалобы
            </NavLink>
          )}
          <NavLink to="/audit">
            <span className="nav-ico">≡</span> Лог действий
          </NavLink>
          {directory && (
            <NavLink to="/directory">
              <span className="nav-ico">◎</span> Справочник
            </NavLink>
          )}
          {directory && (
            <NavLink to="/events">
              <span className="nav-ico">★</span> Афиша
            </NavLink>
          )}
          {directory && (
            <NavLink to="/calendar">
              <span className="nav-ico">▦</span> Календарь
            </NavLink>
          )}
          {directory && (
            <NavLink to="/transport">
              <span className="nav-ico">→</span> Транспорт
            </NavLink>
          )}
          {directory && (
            <NavLink to="/news">
              <span className="nav-ico">✉</span> Новости
            </NavLink>
          )}
          {directory && (
            <NavLink to="/alerts">
              <span className="nav-ico">⚡</span> Срочное
            </NavLink>
          )}
          {mod && (
            <NavLink to="/blacklist">
              <span className="nav-ico">⊘</span> Чёрный список
            </NavLink>
          )}
          {user.role === 'admin' && (
            <NavLink to="/users">
              <span className="nav-ico">☺</span> Пользователи
            </NavLink>
          )}
          {user.role === 'admin' && (
            <NavLink to="/legal">
              <span className="nav-ico">§</span> Правовое
            </NavLink>
          )}
          {user.role === 'admin' && (
            <NavLink to="/app-update">
              <span className="nav-ico">↑</span> Обновления APK
            </NavLink>
          )}
        </nav>
        <div className="aside-user">
          <div className="name">{user.full_name}</div>
          <div className="role">{ROLE_LABELS[user.role]}</div>
          <button type="button" className="theme-toggle" onClick={onToggleTheme}>
            {theme === 'dark' ? '☀ Светлая тема' : '☾ Тёмная тема'}
          </button>
          <button type="button" onClick={onLogout}>
            Выйти
          </button>
        </div>
      </aside>
      <main className="content">{children}</main>
      {toast && <ToastHost message={toast} onClose={() => setToast('')} />}
    </div>
  );
}

function pushToast(message: string) {
  window.dispatchEvent(new CustomEvent('ryadom56:toast', { detail: message }));
}

function Dashboard({ isAdmin }: { isAdmin?: boolean }) {
  const [stats, setStats] = useState<Stats | null>(null);
  const [backupBusy, setBackupBusy] = useState(false);

  useEffect(() => {
    api<Stats>('/admin/stats').then(setStats).catch(console.error);
  }, []);

  async function downloadBackup() {
    if (backupBusy) return;
    setBackupBusy(true);
    try {
      await apiDownload('/admin/backup', 'ryadom56-backup.db');
      pushToast('Бэкап скачан');
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Ошибка скачивания');
    } finally {
      setBackupBusy(false);
    }
  }

  if (!stats) {
    return (
      <div className="page-head">
        <div>
          <h1>Сводка</h1>
          <p>Загрузка данных…</p>
        </div>
      </div>
    );
  }

  const conv =
    stats.moderation_conversion == null ? '—' : `${Math.round(stats.moderation_conversion * 100)}%`;

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Сводка</h1>
          <p>Состояние сервиса Рядом56 прямо сейчас</p>
        </div>
        {isAdmin && (
          <button className="btn secondary" type="button" disabled={backupBusy} onClick={() => downloadBackup()}>
            {backupBusy ? 'Скачивание…' : 'Скачать бэкап БД'}
          </button>
        )}
      </div>
      <div className="cards">
        <div className="stat warn">
          <div className="label">На модерации</div>
          <div className="value">{stats.listings_pending}</div>
        </div>
        <div className="stat warn">
          <div className="label">Старше 24 ч</div>
          <div className="value">{stats.pending_over_24h ?? 0}</div>
        </div>
        <div className="stat">
          <div className="label">Открытые жалобы</div>
          <div className="value">{stats.open_reports ?? 0}</div>
        </div>
        <div className="stat ok">
          <div className="label">Опубликовано</div>
          <div className="value">{stats.listings_approved}</div>
        </div>
        <div className="stat brand">
          <div className="label">В справочнике</div>
          <div className="value">{stats.directory_items}</div>
        </div>
        <div className="stat">
          <div className="label">Пользователей</div>
          <div className="value">{stats.users}</div>
        </div>
        <div className="stat brand">
          <div className="label">События (всего)</div>
          <div className="value">{stats.events_total ?? 0}</div>
        </div>
        <div className="stat ok">
          <div className="label">Скоро в афише</div>
          <div className="value">{stats.events_upcoming ?? 0}</div>
        </div>
        <div className="stat">
          <div className="label">Маршруты</div>
          <div className="value">{stats.transport_routes ?? 0}</div>
        </div>
        <div className="stat brand">
          <div className="label">Новости</div>
          <div className="value">{stats.news_total ?? 0}</div>
        </div>
        <div className="stat warn">
          <div className="label">Активные срочные</div>
          <div className="value">{stats.active_alerts ?? 0}</div>
        </div>
        <div className="stat">
          <div className="label">Одобр. / откл. (30 дн.)</div>
          <div className="value" style={{ fontSize: 22 }}>
            {stats.moderated_approved_30d ?? 0} / {stats.moderated_rejected_30d ?? 0}
          </div>
        </div>
        <div className="stat ok">
          <div className="label">Конверсия модерации</div>
          <div className="value" style={{ fontSize: 26 }}>
            {conv}
          </div>
        </div>
      </div>

      <div className="analytics-grid">
        <div className="panel">
          <h2>Объявления за 7 дней</h2>
          <div className="day-bars">
            {(stats.listings_per_day || []).map((d) => {
              const max = Math.max(1, ...(stats.listings_per_day || []).map((x) => x.count));
              return (
                <div key={d.day} className="day-bar">
                  <div className="day-bar-fill" style={{ height: `${Math.max(8, (d.count / max) * 72)}px` }} />
                  <span>{d.count}</span>
                  <small>{d.day.slice(5)}</small>
                </div>
              );
            })}
          </div>
        </div>
        <div className="panel">
          <h2>Топ категорий</h2>
          <ul className="cat-list">
            {(stats.top_categories || []).map((c) => (
              <li key={c.category}>
                <span>{CATEGORY_LABELS[c.category] || c.category}</span>
                <strong>{c.count}</strong>
              </li>
            ))}
            {!stats.top_categories?.length && <li className="muted">Пока нет данных</li>}
          </ul>
        </div>
        <div className="panel">
          <h2>Топ афиши / транспорта</h2>
          <ul className="cat-list">
            {(stats.top_events || []).map((e) => (
              <li key={`ev-${e.id}`}>
                <span>{e.title}</span>
                <strong>
                  {e.views} откр. / {e.favorites ?? 0} избр.
                </strong>
              </li>
            ))}
            {(stats.top_routes || []).map((r) => (
              <li key={`rt-${r.id}`}>
                <span>{r.title}</span>
                <strong>
                  {r.views} откр. / {r.favorites ?? 0} избр.
                </strong>
              </li>
            ))}
            {!stats.top_events?.length && !stats.top_routes?.length && (
              <li className="muted">Пока нет просмотров</li>
            )}
          </ul>
          <p className="muted" style={{ marginTop: 12 }}>
            Избранное: объявления {stats.listing_favorites_total ?? 0} · справочник{' '}
            {stats.directory_favorites_total ?? 0} · транспорт {stats.transport_favorites_total ?? 0} · афиша{' '}
            {stats.event_favorite_adds_total ?? 0}
          </p>
        </div>
      </div>
    </div>
  );
}

function ModerationPage() {
  const [searchParams] = useSearchParams();
  const listingIdParam = searchParams.get('listingId');
  const authorIdParam = searchParams.get('authorId');
  const qParam = searchParams.get('q');
  const [items, setItems] = useState<Listing[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [filter, setFilter] = useState(() => (listingIdParam || authorIdParam ? '' : 'pending'));
  const [closedOnly, setClosedOnly] = useState(false);
  const [category, setCategory] = useState('');
  const [query, setQuery] = useState('');
  const [serverQuery, setServerQuery] = useState(() => qParam || '');
  const [autoFlaggedOnly, setAutoFlaggedOnly] = useState(false);
  const [settlementId, setSettlementId] = useState<number | ''>('');
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<number | null>(null);
  const [selected, setSelected] = useState<Listing | null>(null);
  const [checked, setChecked] = useState<number[]>([]);
  const [bulkBusy, setBulkBusy] = useState(false);
  const [bulkRejectNote, setBulkRejectNote] = useState('');
  const [moderationNote, setModerationNote] = useState('');

  function closeModal() {
    if (busyId != null) return;
    setSelected(null);
    setModerationNote('');
  }

  async function load() {
    try {
      const params = new URLSearchParams();
      if (closedOnly) {
        params.set('closed_by_user', '1');
      } else if (filter) {
        params.set('status', filter);
      }
      if (serverQuery.trim()) params.set('q', serverQuery.trim());
      if (autoFlaggedOnly) params.set('auto_flagged', '1');
      if (settlementId !== '') params.set('settlement_id', String(settlementId));
      if (authorIdParam) params.set('author_id', authorIdParam);
      if (filter === 'pending' || !filter) params.set('sort', 'sla');
      const qs = params.toString();
      setItems(await api<Listing[]>(`/listings/admin/all${qs ? `?${qs}` : ''}`));
      setChecked([]);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  useEffect(() => {
    api<Settlement[]>('/settlements').then(setSettlements).catch(console.error);
  }, []);

  useEffect(() => {
    if (qParam != null) setServerQuery(qParam);
  }, [qParam]);

  useEffect(() => {
    if (!authorIdParam) return;
    setFilter('');
    setClosedOnly(false);
  }, [authorIdParam]);

  useEffect(() => {
    load();
  }, [filter, closedOnly, serverQuery, autoFlaggedOnly, settlementId, authorIdParam]);

  async function togglePin(item: Listing) {
    setBusyId(item.id);
    try {
      await api(`/listings/${item.id}/pin`, {
        method: 'POST',
        body: JSON.stringify({ pinned: !item.is_pinned }),
      });
      await load();
      if (selected?.id === item.id) {
        const next = await api<Listing[]>(`/listings/admin/all?status=approved`);
        const found = next.find((x) => x.id === item.id);
        if (found) setSelected(found);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusyId(null);
    }
  }

  useEffect(() => {
    if (!listingIdParam) return;
    const id = Number(listingIdParam);
    if (!Number.isFinite(id)) return;
    setFilter('');
    setClosedOnly(false);
    setModerationNote('');

    async function openFromParam() {
      try {
        const list = await api<Listing[]>('/listings/admin/all');
        setItems(list);
        const found = list.find((item) => item.id === id);
        if (found) {
          setSelected(found);
          return;
        }
        const item = await api<Listing>(`/listings/${id}`);
        setSelected(item);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Ошибка');
      }
    }

    openFromParam().catch(console.error);
  }, [listingIdParam]);

  const visible = useMemo(() => {
    return items.filter((item) => {
      if (category && item.category !== category) return false;
      if (query.trim()) {
        const q = query.trim().toLowerCase();
        return (
          item.title.toLowerCase().includes(q) ||
          item.description.toLowerCase().includes(q) ||
          (item.author_name || '').toLowerCase().includes(q) ||
          (item.settlement_name || '').toLowerCase().includes(q) ||
          (item.contact_phone || '').toLowerCase().includes(q)
        );
      }
      return true;
    });
  }, [items, category, query]);

  async function moderate(id: number, status: 'approved' | 'rejected', noteOverride?: string | null) {
    if (busyId != null) return;
    if (status === 'rejected') {
      if (!(noteOverride ?? moderationNote).trim()) {
        setError('Укажите причину отклонения');
        return;
      }
    }
    setBusyId(id);
    setError('');
    try {
      const note =
        status === 'rejected'
          ? (noteOverride !== undefined ? noteOverride : moderationNote.trim() || null)
          : null;
      await api(`/listings/${id}/moderate`, {
        method: 'POST',
        body: JSON.stringify({ status, moderation_note: note }),
      });
      setSelected(null);
      setModerationNote('');
      await load();
      pushToast(status === 'approved' ? 'Объявление одобрено' : 'Объявление отклонено');
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Ошибка';
      setError(msg);
      pushToast(msg);
    } finally {
      setBusyId(null);
    }
  }

  async function bulkModerate(status: 'approved' | 'rejected') {
    const ids = checked.filter((id) => items.some((x) => x.id === id && needsModeration(x)));
    if (!ids.length) return;
    let moderation_note: string | null = null;
    if (status === 'approved') {
      if (!(await confirmAction(`Одобрить выбранные объявления (${ids.length})?`))) return;
    } else {
      const note = bulkRejectNote.trim() || window.prompt('Причина отклонения для автора')?.trim() || '';
      if (!note) {
        pushToast('Укажите причину отклонения');
        return;
      }
      if (!(await confirmAction(`Отклонить выбранные объявления (${ids.length})?`))) return;
      moderation_note = note;
    }
    setBulkBusy(true);
    setError('');
    try {
      await api('/admin/listings/bulk-moderate', {
        method: 'POST',
        body: JSON.stringify({ ids, status, moderation_note }),
      });
      setBulkRejectNote('');
      await load();
      pushToast(status === 'approved' ? `Одобрено: ${ids.length}` : `Отклонено: ${ids.length}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Ошибка';
      setError(msg);
      pushToast(msg);
    } finally {
      setBulkBusy(false);
    }
  }

  function toggleCheck(id: number) {
    setChecked((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  }

  function openListing(item: Listing) {
    setSelected(item);
    setModerationNote('');
  }

  const pendingChecked = checked.filter((id) => items.find((x) => x.id === id && needsModeration(x)));
  const over24 = items.filter((i) => needsModeration(i) && hoursWaiting(i.created_at) >= 24).length;

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const tag = (e.target as HTMLElement | null)?.tagName?.toLowerCase();
      if (tag === 'input' || tag === 'textarea' || tag === 'select' || (e.target as HTMLElement)?.isContentEditable) {
        return;
      }
      if (!selected || !needsModeration(selected) || busyId != null) return;
      if (e.key === 'a' || e.key === 'A' || e.key === 'ф' || e.key === 'Ф') {
        e.preventDefault();
        void moderate(selected.id, 'approved');
      }
      if (e.key === 'r' || e.key === 'R' || e.key === 'к' || e.key === 'К') {
        e.preventDefault();
        void moderate(selected.id, 'rejected');
      }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [selected, busyId, moderationNote]);

  return (
    <div className="moderation-page">
      <div className="page-head compact">
        <div>
          <h1>Модерация</h1>
          <p>
            Очередь по SLA (дольше ждут сверху)
            {over24 > 0 ? ` · старше 24 ч: ${over24}` : ''}
            {' · '}
            <span className="muted">клавиши: A — одобрить, R — отклонить</span>
          </p>
        </div>
      </div>

      <div className="toolbar compact">
        <select
          value={closedOnly ? 'closed' : filter}
          onChange={(e) => {
            if (e.target.value === 'closed') {
              setClosedOnly(true);
              setFilter('archived');
            } else {
              setClosedOnly(false);
              setFilter(e.target.value);
            }
          }}
        >
          <option value="pending">На проверке</option>
          <option value="approved">Одобренные</option>
          <option value="rejected">Отклонённые</option>
          <option value="draft">Черновики</option>
          <option value="archived">Снятые (все)</option>
          <option value="closed">Снятые пользователем</option>
          <option value="">Все</option>
        </select>
        <select value={category} onChange={(e) => setCategory(e.target.value)}>
          <option value="">Все категории</option>
          {['goods', 'services', 'jobs', 'rent', 'free', 'lost_found'].map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABELS[c]}
            </option>
          ))}
        </select>
        <input
          placeholder="Серверный поиск: автор, телефон, email…"
          value={serverQuery}
          onChange={(e) => setServerQuery(e.target.value)}
          style={{ maxWidth: 280 }}
        />
        <input
          placeholder="Локальный фильтр…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          style={{ maxWidth: 200 }}
        />
        <select
          value={settlementId === '' ? '' : String(settlementId)}
          onChange={(e) => setSettlementId(e.target.value ? Number(e.target.value) : '')}
        >
          <option value="">Все населённые пункты</option>
          {settlements.map((s) => (
            <option key={s.id} value={s.id}>
              {s.display_name}
            </option>
          ))}
        </select>
        <label className="check-inline">
          <input
            type="checkbox"
            checked={autoFlaggedOnly}
            onChange={(e) => setAutoFlaggedOnly(e.target.checked)}
          />
          Только автофлаг
        </label>
        {authorIdParam && <span className="chip warn">Автор #{authorIdParam}</span>}
      </div>

      {pendingChecked.length > 0 && (
        <div className="toolbar compact">
          <span className="muted">Выбрано: {pendingChecked.length}</span>
          <input
            placeholder="Причина отклонения (для массового)"
            value={bulkRejectNote}
            onChange={(e) => setBulkRejectNote(e.target.value)}
            style={{ maxWidth: 280 }}
          />
          <button className="btn" type="button" disabled={bulkBusy} onClick={() => bulkModerate('approved')}>
            Одобрить выбранные
          </button>
          <button className="btn danger" type="button" disabled={bulkBusy} onClick={() => bulkModerate('rejected')}>
            Отклонить выбранные
          </button>
        </div>
      )}

      {error && <p className="error">{error}</p>}

      <div className="list compact">
        {visible.map((item) => {
          const pending = needsModeration(item);
          const waitH = hoursWaiting(item.created_at);
          return (
            <article
              key={item.id}
              className={`row-card compact${checked.includes(item.id) ? ' is-checked' : ''}`}
              onClick={() => openListing(item)}
            >
              {pending && (
                <input
                  className="row-check"
                  type="checkbox"
                  checked={checked.includes(item.id)}
                  onClick={(e) => e.stopPropagation()}
                  onChange={() => toggleCheck(item.id)}
                  aria-label={`Выбрать ${item.title}`}
                />
              )}
              <div className="row-main">
                <h3 className="row-title">{item.title}</h3>
                <div className="meta">
                  <span className={STATUS_CHIP[item.status] || 'chip'}>{STATUS_LABEL[item.status] || item.status}</span>
                  <span className="chip">{CATEGORY_LABELS[item.category] || item.category}</span>
                  <span className="chip neutral">{item.settlement_name}</span>
                  <span className="chip neutral">{item.author_name}</span>
                  {item.contact_phone && <span className="chip neutral">{item.contact_phone}</span>}
                  {item.auto_flagged && <span className="chip danger">Автофлаг</span>}
                  {item.is_pinned && <span className="chip warn">Закреплено</span>}
                  {item.previous_snapshot && <span className="chip neutral">Правка</span>}
                  {pending && waitH >= 24 && <span className="chip danger">{waitH} ч</span>}
                  {pending && waitH < 24 && waitH > 0 && <span className="chip neutral">{waitH} ч</span>}
                  {item.close_reason && (
                    <span className="chip warn">{CLOSE_REASON_LABEL[item.close_reason] || item.close_reason}</span>
                  )}
                </div>
                <p className="row-body">
                  {item.description.length > 110 ? `${item.description.slice(0, 110)}…` : item.description}
                </p>
                {item.price != null && <div className="price">{item.price.toLocaleString('ru-RU')} ₽</div>}
              </div>
              <div className="actions inline" onClick={(e) => e.stopPropagation()}>
                {pending && (
                  <>
                    <button className="btn" disabled={busyId === item.id} onClick={() => moderate(item.id, 'approved')}>
                      Одобрить
                    </button>
                    <button className="btn danger" disabled={busyId === item.id} onClick={() => openListing(item)}>
                      Отклонить
                    </button>
                  </>
                )}
                {item.status === 'approved' && (
                  <button className="btn secondary" disabled={busyId === item.id} onClick={() => togglePin(item)}>
                    {item.is_pinned ? 'Открепить' : 'Закрепить'}
                  </button>
                )}
                <button className="btn ghost" onClick={() => openListing(item)}>
                  Открыть
                </button>
              </div>
            </article>
          );
        })}
        {!visible.length && <div className="empty">Пока нет объявлений в этом фильтре</div>}
      </div>

      {selected && (
        <div
          className="modal-backdrop"
          onClick={() => {
            if (busyId == null) closeModal();
          }}
        >
          <div className="modal modal-compact" onClick={(e) => e.stopPropagation()}>
            <div className="meta">
              <span className={STATUS_CHIP[selected.status] || 'chip'}>{STATUS_LABEL[selected.status]}</span>
              <span className="chip">{CATEGORY_LABELS[selected.category]}</span>
              <span className="chip neutral">{selected.settlement_name}</span>
              {selected.auto_flagged && <span className="chip danger">Автофлаг</span>}
              {selected.is_pinned && <span className="chip warn">Закреплено</span>}
              {selected.close_reason && (
                <span className="chip warn">{CLOSE_REASON_LABEL[selected.close_reason] || selected.close_reason}</span>
              )}
            </div>
            <h2>{selected.title}</h2>
            {selected.price != null && <div className="price">{selected.price.toLocaleString('ru-RU')} ₽</div>}
            {!!selected.images?.length && <PhotoGallery images={selected.images} />}
            <p className="row-body" style={{ marginTop: 10, whiteSpace: 'pre-wrap' }}>
              {selected.description}
            </p>
            {selected.previous_snapshot && (
              <div className="diff-box">
                <h3>Было → стало</h3>
                {(
                  [
                    ['title', 'Заголовок'],
                    ['description', 'Описание'],
                    ['category', 'Категория'],
                    ['price', 'Цена'],
                    ['contact_phone', 'Телефон'],
                    ['is_urgent', 'Срочно'],
                  ] as const
                ).map(([key, label]) => {
                  const before = selected.previous_snapshot?.[key];
                  const after =
                    key === 'category'
                      ? selected.category
                      : key === 'is_urgent'
                        ? selected.is_urgent
                        : key === 'price'
                          ? selected.price
                          : key === 'contact_phone'
                            ? selected.contact_phone
                            : key === 'title'
                              ? selected.title
                              : selected.description;
                  const beforeText =
                    before == null || before === ''
                      ? '—'
                      : key === 'category'
                        ? CATEGORY_LABELS[String(before)] || String(before)
                        : key === 'is_urgent'
                          ? before
                            ? 'да'
                            : 'нет'
                          : String(before);
                  const afterText =
                    after == null || after === ''
                      ? '—'
                      : key === 'category'
                        ? CATEGORY_LABELS[String(after)] || String(after)
                        : key === 'is_urgent'
                          ? after
                            ? 'да'
                            : 'нет'
                          : String(after);
                  if (beforeText === afterText) return null;
                  return (
                    <div key={key} className="diff-row">
                      <strong>{label}</strong>
                      <div className="diff-old">{beforeText}</div>
                      <div className="diff-new">{afterText}</div>
                    </div>
                  );
                })}
              </div>
            )}
            <p className="muted" style={{ marginTop: 10 }}>
              Автор: {selected.author_name || '—'} · Тел: {selected.contact_phone || '—'} · ждёт{' '}
              {hoursWaiting(selected.created_at)} ч
            </p>
            {selected.close_reason && (
              <p className="muted">
                Снято: {CLOSE_REASON_LABEL[selected.close_reason] || selected.close_reason}
                {selected.close_note ? ` — ${selected.close_note}` : ''}
              </p>
            )}
            {selected.moderation_note && <p className="muted">Заметка: {selected.moderation_note}</p>}
            {needsModeration(selected) && (
              <label className="field" style={{ display: 'block', marginTop: 12 }}>
                Причина отклонения (для автора)
                <div className="template-row">
                  {REJECTION_TEMPLATES.map((t) => (
                    <button key={t} type="button" className="btn ghost" onClick={() => setModerationNote(t)}>
                      {t}
                    </button>
                  ))}
                </div>
                <textarea
                  value={moderationNote}
                  onChange={(e) => setModerationNote(e.target.value)}
                  placeholder="Шаблон или свой текст"
                  rows={2}
                />
              </label>
            )}
            <div className="modal-actions">
              {needsModeration(selected) && (
                <>
                  <button className="btn" disabled={busyId === selected.id} onClick={() => moderate(selected.id, 'approved')}>
                    Одобрить
                  </button>
                  <button
                    className="btn danger"
                    disabled={busyId === selected.id || !moderationNote.trim()}
                    onClick={() => moderate(selected.id, 'rejected')}
                  >
                    Отклонить
                  </button>
                </>
              )}
              {selected.status === 'approved' && (
                <button className="btn secondary" disabled={busyId === selected.id} onClick={() => togglePin(selected)}>
                  {selected.is_pinned ? 'Открепить' : 'Закрепить в ленте'}
                </button>
              )}
              <button className="btn secondary" onClick={closeModal}>
                Закрыть
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function ReportsPage() {
  const navigate = useNavigate();
  const [items, setItems] = useState<ListingReport[]>([]);
  const [status, setStatus] = useState('open');
  const [error, setError] = useState('');
  const [replyModal, setReplyModal] = useState<{
    report: ListingReport;
    next: 'reviewed' | 'dismissed';
  } | null>(null);
  const [moderatorReply, setModeratorReply] = useState('');
  const [openListingAfter, setOpenListingAfter] = useState(false);
  const [busy, setBusy] = useState(false);

  async function load() {
    try {
      const qs = status ? `?status=${status}` : '';
      setItems(await api<ListingReport[]>(`/admin/reports${qs}`));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  useEffect(() => {
    load().catch(console.error);
  }, [status]);

  function openReplyModal(report: ListingReport, next: 'reviewed' | 'dismissed') {
    setReplyModal({ report, next });
    setModeratorReply('');
    setOpenListingAfter(false);
    setError('');
  }

  function closeReplyModal() {
    if (busy) return;
    setReplyModal(null);
    setModeratorReply('');
    setOpenListingAfter(false);
  }

  async function submitReportStatus() {
    if (!replyModal || busy) return;
    if (replyModal.next === 'dismissed') {
      if (!(await confirmAction('Отклонить эту жалобу?'))) return;
    }
    const next = replyModal.next;
    const listingId = replyModal.report.listing_id;
    const shouldOpen = openListingAfter;
    setBusy(true);
    setError('');
    try {
      await api(`/admin/reports/${replyModal.report.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          status: next,
          moderator_reply: moderatorReply.trim() || null,
        }),
      });
      setReplyModal(null);
      setModeratorReply('');
      setOpenListingAfter(false);
      await load();
      pushToast(next === 'reviewed' ? 'Жалоба просмотрена' : 'Жалоба отклонена');
      if (shouldOpen) navigate(`/moderation?listingId=${listingId}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Ошибка';
      setError(msg);
      pushToast(msg);
    } finally {
      setBusy(false);
    }
  }

  function goToListing(listingId: number) {
    navigate(`/moderation?listingId=${listingId}`);
  }

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Жалобы</h1>
          <p>Сигналы пользователей по объявлениям</p>
        </div>
      </div>
      <div className="toolbar">
        <select value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="open">Открытые</option>
          <option value="reviewed">Просмотренные</option>
          <option value="dismissed">Отклонённые</option>
          <option value="">Все</option>
        </select>
      </div>
      {error && !replyModal && <p className="error">{error}</p>}
      <div className="list">
        {items.map((r) => (
          <article key={r.id} className="row-card">
            <div className="row-main">
              <h3
                className="row-title"
                style={{ cursor: 'pointer' }}
                onClick={() => goToListing(r.listing_id)}
              >
                {r.listing_title || `Объявление #${r.listing_id}`}
              </h3>
              <div className="meta">
                <span className="chip warn">{REPORT_REASON_LABEL[r.reason] || r.reason}</span>
                <span className="chip neutral">{r.reporter_name}</span>
                <span className="chip">{REPORT_STATUS_LABEL[r.status] || r.status}</span>
              </div>
              {r.note && <p className="row-body">{r.note}</p>}
              {r.moderator_reply && <p className="muted">Ответ: {r.moderator_reply}</p>}
              <p className="muted">{formatDate(r.created_at)}</p>
            </div>
            <div className="actions">
              <button className="btn ghost" type="button" onClick={() => goToListing(r.listing_id)}>
                К объявлению
              </button>
              {r.status === 'open' && (
                <>
                  <button className="btn" type="button" onClick={() => openReplyModal(r, 'reviewed')}>
                    Просмотрено
                  </button>
                  <button className="btn secondary" type="button" onClick={() => openReplyModal(r, 'dismissed')}>
                    Отклонить
                  </button>
                </>
              )}
            </div>
          </article>
        ))}
        {!items.length && <div className="empty">Жалоб нет</div>}
      </div>

      {replyModal && (
        <div className="modal-backdrop" onClick={closeReplyModal}>
          <div className="modal modal-compact" onClick={(e) => e.stopPropagation()}>
            <h2>{replyModal.next === 'reviewed' ? 'Просмотреть жалобу' : 'Отклонить жалобу'}</h2>
            <p className="muted" style={{ marginTop: 0 }}>
              {replyModal.report.listing_title || `Объявление #${replyModal.report.listing_id}`}
            </p>
            <label className="field" style={{ display: 'block', marginTop: 12 }}>
              Ответ автору жалобы (необязательно)
              <textarea
                value={moderatorReply}
                onChange={(e) => setModeratorReply(e.target.value)}
                placeholder="Короткий ответ"
                rows={3}
              />
            </label>
            <label className="check-inline" style={{ marginTop: 12 }}>
              <input
                type="checkbox"
                checked={openListingAfter}
                onChange={(e) => setOpenListingAfter(e.target.checked)}
              />
              Перейти к объявлению после
            </label>
            {error && <p className="error">{error}</p>}
            <div className="modal-actions">
              <button
                className={replyModal.next === 'dismissed' ? 'btn secondary' : 'btn'}
                type="button"
                disabled={busy}
                onClick={() => submitReportStatus()}
              >
                {busy ? 'Сохранение…' : replyModal.next === 'reviewed' ? 'Просмотрено' : 'Отклонить'}
              </button>
              <button className="btn ghost" type="button" disabled={busy} onClick={closeReplyModal}>
                Отмена
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function AuditPage() {
  const [items, setItems] = useState<AuditLog[]>([]);
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');

  async function load(q = query) {
    try {
      const qs = q.trim() ? `?q=${encodeURIComponent(q.trim())}` : '';
      setItems(await api<AuditLog[]>(`/admin/audit-log${qs}`));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  useEffect(() => {
    load('').catch(console.error);
  }, []);

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Лог действий</h1>
          <p>Модераторы, админы и редакторы</p>
        </div>
      </div>
      <div className="toolbar">
        <input
          placeholder="Поиск по действию, автору, деталям…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <button className="btn" type="button" onClick={() => load(query)}>
          Найти
        </button>
      </div>
      {error && <p className="error">{error}</p>}
      <div className="list">
        {items.map((row) => (
          <article key={row.id} className="row-card">
            <div className="row-main">
              <h3 className="row-title">{row.action}</h3>
              <div className="meta">
                <span className="chip">{row.actor_name || `user #${row.actor_id}`}</span>
                <span className="chip neutral">
                  {row.entity_type}
                  {row.entity_id != null ? ` #${row.entity_id}` : ''}
                </span>
                <span className="chip neutral">{formatDate(row.created_at)}</span>
              </div>
              {row.details && <p className="row-body">{row.details}</p>}
            </div>
          </article>
        ))}
        {!items.length && <div className="empty">Записей пока нет</div>}
      </div>
    </div>
  );
}

type DirectoryForm = {
  title: string;
  category: string;
  settlement_id: number | '';
  description: string;
  address: string;
  phone: string;
  website: string;
  hours: string;
  lat: string;
  lon: string;
  is_published: boolean;
};

const EMPTY_DIR: DirectoryForm = {
  title: '',
  category: 'shop',
  settlement_id: '',
  description: '',
  address: '',
  phone: '',
  website: '',
  hours: '',
  lat: '',
  lon: '',
  is_published: true,
};

function directoryPayload(form: DirectoryForm) {
  return {
    title: form.title,
    category: form.category,
    settlement_id: form.settlement_id === '' ? null : Number(form.settlement_id),
    description: form.description || null,
    address: form.address || null,
    phone: form.phone || null,
    website: form.website || null,
    hours: form.hours || null,
    lat: form.lat === '' ? null : Number(form.lat),
    lon: form.lon === '' ? null : Number(form.lon),
    is_published: form.is_published,
  };
}

function DirectoryPage() {
  const [items, setItems] = useState<DirectoryItem[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [form, setForm] = useState<DirectoryForm>(EMPTY_DIR);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [publishedFilter, setPublishedFilter] = useState<'all' | 'published' | 'hidden'>('all');
  const [settlementFilter, setSettlementFilter] = useState<number | ''>('');

  async function load() {
    setItems(await api<DirectoryItem[]>('/directory'));
    setSettlements(await api<Settlement[]>('/settlements'));
  }

  useEffect(() => {
    load().catch((err) => setError(err.message));
  }, []);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_DIR);
    setError('');
    setModalOpen(true);
  }

  function startEdit(item: DirectoryItem) {
    setEditingId(item.id);
    setForm({
      title: item.title,
      category: item.category,
      settlement_id: item.settlement_id ?? '',
      description: item.description || '',
      address: item.address || '',
      phone: item.phone || '',
      website: item.website || '',
      hours: item.hours || '',
      lat: item.lat != null ? String(item.lat) : '',
      lon: item.lon != null ? String(item.lon) : '',
      is_published: item.is_published,
    });
    setError('');
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingId(null);
    setForm(EMPTY_DIR);
    setError('');
  }

  async function saveItem(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      if (editingId) {
        await api(`/directory/${editingId}`, {
          method: 'PATCH',
          body: JSON.stringify(directoryPayload(form)),
        });
      } else {
        await api('/directory', {
          method: 'POST',
          body: JSON.stringify(directoryPayload(form)),
        });
      }
      closeModal();
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function remove(id: number) {
    if (!(await confirmAction('Удалить запись из справочника? Это действие нельзя отменить.'))) return;
    await api(`/directory/${id}`, { method: 'DELETE' });
    if (editingId === id) closeModal();
    await load();
  }

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Справочник</h1>
          <p>Школы, больницы, магазины и другие точки района</p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить запись
        </button>
      </div>

      <div className="toolbar">
        <input placeholder="Поиск по справочнику…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)}>
          <option value="">Все категории</option>
          {['school', 'hospital', 'shop', 'pharmacy', 'admin', 'bank', 'post', 'transport', 'culture', 'sport', 'other'].map(
            (c) => (
              <option key={c} value={c}>
                {CATEGORY_LABELS[c]}
              </option>
            ),
          )}
        </select>
        <select
          value={publishedFilter}
          onChange={(e) => setPublishedFilter(e.target.value as 'all' | 'published' | 'hidden')}
        >
          <option value="all">Все статусы</option>
          <option value="published">Опубликованные</option>
          <option value="hidden">Скрытые</option>
        </select>
        <select
          value={settlementFilter === '' ? '' : String(settlementFilter)}
          onChange={(e) => setSettlementFilter(e.target.value ? Number(e.target.value) : '')}
        >
          <option value="">Все населённые пункты</option>
          {settlements.map((s) => (
            <option key={s.id} value={s.id}>
              {s.display_name}
            </option>
          ))}
        </select>
      </div>

      <div className="list">
        {items
          .filter((item) => {
            if (categoryFilter && item.category !== categoryFilter) return false;
            if (publishedFilter === 'published' && !item.is_published) return false;
            if (publishedFilter === 'hidden' && item.is_published) return false;
            if (settlementFilter !== '' && item.settlement_id !== settlementFilter) return false;
            if (!query.trim()) return true;
            const q = query.trim().toLowerCase();
            return (
              item.title.toLowerCase().includes(q) ||
              (item.address || '').toLowerCase().includes(q) ||
              (item.phone || '').toLowerCase().includes(q) ||
              (item.settlement_name || '').toLowerCase().includes(q)
            );
          })
          .map((item) => (
            <article key={item.id} className="row-card">
              <div className="row-main">
                <h3 className="row-title">{item.title}</h3>
                <div className="meta">
                  <span className="chip">{CATEGORY_LABELS[item.category] || item.category}</span>
                  <span className="chip neutral">{item.settlement_name || 'без привязки'}</span>
                  {item.is_published ? <span className="chip ok">Опубликовано</span> : <span className="chip warn">Скрыто</span>}
                </div>
                {item.address && <p className="row-body">{item.address}</p>}
                {item.phone && (
                  <p className="row-body">
                    <a href={`tel:${item.phone}`}>{item.phone}</a>
                  </p>
                )}
              </div>
              <div className="actions">
                <button className="btn" type="button" onClick={() => startEdit(item)}>
                  Изменить
                </button>
                {item.phone && (
                  <a className="btn secondary" href={`tel:${item.phone}`}>
                    Позвонить
                  </a>
                )}
                <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                  Удалить
                </button>
              </div>
            </article>
          ))}
        {!items.length && <div className="empty">Справочник пуст — нажмите «Добавить запись»</div>}
      </div>

      {modalOpen && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(720px, 100%)' }}>
            <h2>{editingId ? 'Редактировать запись' : 'Добавить запись'}</h2>
            <form onSubmit={saveItem}>
              <div className="grid2">
                <label className="field">
                  Название
                  <input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
                </label>
                <label className="field">
                  Категория
                  <select value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
                    {['school', 'hospital', 'shop', 'pharmacy', 'admin', 'bank', 'post', 'transport', 'culture', 'sport', 'other'].map(
                      (c) => (
                        <option key={c} value={c}>
                          {CATEGORY_LABELS[c]}
                        </option>
                      ),
                    )}
                  </select>
                </label>
                <label className="field">
                  Населённый пункт
                  <select
                    value={form.settlement_id}
                    onChange={(e) => setForm({ ...form, settlement_id: e.target.value ? Number(e.target.value) : '' })}
                  >
                    <option value="">— не указан —</option>
                    {settlements.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.display_name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  Телефон
                  <input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
                </label>
                <label className="field full">
                  Адрес
                  <input value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} />
                </label>
                <label className="field">
                  Сайт
                  <input value={form.website} onChange={(e) => setForm({ ...form, website: e.target.value })} />
                </label>
                <label className="field">
                  Часы работы
                  <input
                    value={form.hours}
                    onChange={(e) => setForm({ ...form, hours: e.target.value })}
                    placeholder="пн–пт 9:00–18:00"
                  />
                </label>
                <label className="field">
                  Опубликовано
                  <select
                    value={form.is_published ? '1' : '0'}
                    onChange={(e) => setForm({ ...form, is_published: e.target.value === '1' })}
                  >
                    <option value="1">Да</option>
                    <option value="0">Нет (скрыто)</option>
                  </select>
                </label>
                <label className="field">
                  Широта
                  <input value={form.lat} onChange={(e) => setForm({ ...form, lat: e.target.value })} placeholder="51.98" />
                </label>
                <label className="field">
                  Долгота
                  <input value={form.lon} onChange={(e) => setForm({ ...form, lon: e.target.value })} placeholder="55.33" />
                </label>
                <label className="field full">
                  Описание
                  <textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
                </label>
              </div>
              {error && <p className="error">{error}</p>}
              <div className="modal-actions">
                <button className="btn" type="submit" disabled={busy}>
                  {busy ? 'Сохранение…' : editingId ? 'Сохранить' : 'Добавить'}
                </button>
                <button className="btn secondary" type="button" onClick={closeModal}>
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

function BlacklistPage() {
  const [items, setItems] = useState<BlacklistEntry[]>([]);
  const [kind, setKind] = useState<'phone' | 'word'>('word');
  const [value, setValue] = useState('');
  const [note, setNote] = useState('');
  const [error, setError] = useState('');

  async function load() {
    setItems(await api<BlacklistEntry[]>('/admin/blacklist'));
  }

  useEffect(() => {
    load().catch(console.error);
  }, []);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    try {
      await api('/admin/blacklist', {
        method: 'POST',
        body: JSON.stringify({ kind, value: value.trim(), note: note.trim() || null }),
      });
      setValue('');
      setNote('');
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  async function remove(id: number) {
    if (!(await confirmAction('Удалить запись из чёрного списка?'))) return;
    try {
      await api(`/admin/blacklist/${id}`, { method: 'DELETE' });
      await load();
      pushToast('Удалено из чёрного списка');
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Чёрный список</h1>
          <p>Телефоны и слова — автофлаг на модерацию</p>
        </div>
      </div>
      <form className="toolbar compact" onSubmit={add}>
        <select value={kind} onChange={(e) => setKind(e.target.value as 'phone' | 'word')}>
          <option value="word">Слово</option>
          <option value="phone">Телефон</option>
        </select>
        <input
          required
          placeholder={kind === 'phone' ? '+7900…' : 'запрещённое слово'}
          value={value}
          onChange={(e) => setValue(e.target.value)}
        />
        <input placeholder="Заметка" value={note} onChange={(e) => setNote(e.target.value)} />
        <button className="btn" type="submit">
          Добавить
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      <div className="list compact">
        {items.map((row) => (
          <article key={row.id} className="row-card compact">
            <div className="row-main">
              <h3 className="row-title">{row.value}</h3>
              <div className="meta">
                <span className="chip">{row.kind === 'phone' ? 'Телефон' : 'Слово'}</span>
                {row.note && <span className="chip neutral">{row.note}</span>}
              </div>
            </div>
            <div className="actions inline">
              <button className="btn danger" type="button" onClick={() => remove(row.id)}>
                Удалить
              </button>
            </div>
          </article>
        ))}
        {!items.length && <div className="empty">Список пуст</div>}
      </div>
    </div>
  );
}

function UsersPage() {
  const navigate = useNavigate();
  const [users, setUsers] = useState<User[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [selected, setSelected] = useState<User | null>(null);
  const [form, setForm] = useState({
    full_name: '',
    email: '',
    phone: '',
    settlement_id: 0,
    role: 'user' as User['role'],
    is_active: true,
  });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [suspicious, setSuspicious] = useState(false);

  async function load() {
    const params = new URLSearchParams();
    if (query.trim()) params.set('q', query.trim());
    if (suspicious) params.set('suspicious', '1');
    const qs = params.toString();
    const [u, s] = await Promise.all([
      api<User[]>(`/admin/users${qs ? `?${qs}` : ''}`),
      api<Settlement[]>('/settlements'),
    ]);
    setUsers(u);
    setSettlements(s);
  }

  useEffect(() => {
    load().catch(console.error);
  }, [suspicious]);

  async function exportCsv() {
    const params = new URLSearchParams();
    if (query.trim()) params.set('q', query.trim());
    if (suspicious) params.set('suspicious', '1');
    const qs = params.toString();
    const text = await apiText(`/admin/users/export${qs ? `?${qs}` : ''}`);
    const blob = new Blob([text], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = suspicious ? 'users-suspicious.csv' : 'users.csv';
    a.click();
    URL.revokeObjectURL(url);
  }

  function openEdit(u: User) {
    setSelected(u);
    setForm({
      full_name: u.full_name,
      email: u.email,
      phone: u.phone || '',
      settlement_id: u.settlement_id,
      role: u.role,
      is_active: u.is_active,
    });
    setError('');
  }

  async function saveUser(e: React.FormEvent) {
    e.preventDefault();
    if (!selected || busy) return;
    if (!form.full_name.trim() || !isValidEmail(form.email)) {
      setError('Проверьте имя и email');
      return;
    }
    if (selected.is_active && !form.is_active) {
      if (!(await confirmAction(`Заблокировать пользователя ${selected.full_name}?`))) return;
    }
    if (
      form.role !== selected.role &&
      (form.role === 'moderator' || form.role === 'editor' || form.role === 'admin')
    ) {
      if (
        !(await confirmAction(
          `Назначить роль «${ROLE_LABELS[form.role]}» пользователю ${selected.full_name}? Это даст доступ к админке.`,
        ))
      ) {
        return;
      }
    }
    setBusy(true);
    setError('');
    try {
      const updated = await api<User>(`/admin/users/${selected.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          full_name: form.full_name.trim(),
          email: form.email.trim(),
          phone: form.phone.trim() || null,
          settlement_id: form.settlement_id,
          role: form.role,
          is_active: form.is_active,
        }),
      });
      setUsers((prev) => prev.map((u) => (u.id === updated.id ? updated : u)));
      setSelected(updated);
      pushToast('Пользователь сохранён');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Пользователи</h1>
          <p>Роли, устройство, IP · подозрительные = один IP у нескольких аккаунтов</p>
        </div>
        <div className="toolbar compact" style={{ margin: 0 }}>
          <button className="btn secondary" type="button" onClick={() => load().catch(console.error)}>
            Обновить
          </button>
          <button className="btn secondary" type="button" onClick={() => exportCsv().catch(console.error)}>
            Экспорт CSV
          </button>
        </div>
      </div>

      <div className="toolbar compact">
        <input
          placeholder="Поиск: имя, email, телефон, IP, устройство…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') load().catch(console.error);
          }}
        />
        <button className="btn" type="button" onClick={() => load().catch(console.error)}>
          Найти
        </button>
        <label className="check-inline">
          <input type="checkbox" checked={suspicious} onChange={(e) => setSuspicious(e.target.checked)} />
          Только подозрительные
        </label>
      </div>

      <div className="list compact">
        {users.map((u) => (
          <article key={u.id} className="row-card user-row compact" onClick={() => openEdit(u)}>
            <div className="row-main">
              <h3 className="row-title">{u.full_name}</h3>
              <div className="meta">
                <span className="chip neutral">{u.email}</span>
                <span className="chip">{ROLE_LABELS[u.role]}</span>
                {!u.is_active && <span className="chip danger">Заблокирован</span>}
              </div>
              <div className="device-grid">
                <div>
                  <span className="device-label">IP</span>
                  <strong>{u.last_ip || '—'}</strong>
                </div>
                <div>
                  <span className="device-label">Устройство</span>
                  <strong>{[u.device_brand, u.device_model].filter(Boolean).join(' ') || '—'}</strong>
                </div>
                <div>
                  <span className="device-label">ОС</span>
                  <strong>{u.device_os || '—'}</strong>
                </div>
                <div>
                  <span className="device-label">Приложение</span>
                  <strong>{u.app_version || '—'}</strong>
                </div>
                <div>
                  <span className="device-label">Был(а)</span>
                  <strong>{formatDate(u.last_seen_at)}</strong>
                </div>
              </div>
            </div>
            <div className="actions" onClick={(e) => e.stopPropagation()}>
              <button
                className="btn ghost"
                type="button"
                onClick={() => navigate(`/moderation?authorId=${u.id}`)}
              >
                Объявления
              </button>
              <button className="btn" type="button" onClick={() => openEdit(u)}>
                Изменить
              </button>
            </div>
          </article>
        ))}
        {!users.length && <div className="empty">Пользователи не найдены</div>}
      </div>

      {selected && (
        <div className="modal-backdrop" onClick={() => setSelected(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h2>Редактировать пользователя</h2>
            <form onSubmit={saveUser}>
              <div className="grid2">
                <label className="field">
                  Имя
                  <input
                    required
                    value={form.full_name}
                    onChange={(e) => setForm({ ...form, full_name: e.target.value })}
                  />
                </label>
                <label className="field">
                  Email
                  <input
                    required
                    type="email"
                    value={form.email}
                    onChange={(e) => setForm({ ...form, email: e.target.value })}
                  />
                </label>
                <label className="field">
                  Телефон
                  <input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
                </label>
                <label className="field">
                  Населённый пункт
                  <select
                    value={form.settlement_id}
                    onChange={(e) => setForm({ ...form, settlement_id: Number(e.target.value) })}
                  >
                    {settlements.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.display_name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  Роль
                  <select
                    value={form.role}
                    onChange={(e) => setForm({ ...form, role: e.target.value as User['role'] })}
                  >
                    <option value="user">Пользователь</option>
                    <option value="moderator">Модератор</option>
                    <option value="editor">Редактор</option>
                    <option value="admin">Админ</option>
                  </select>
                </label>
                <label className="field">
                  Статус
                  <select
                    value={form.is_active ? '1' : '0'}
                    onChange={(e) => setForm({ ...form, is_active: e.target.value === '1' })}
                  >
                    <option value="1">Активен</option>
                    <option value="0">Заблокирован</option>
                  </select>
                </label>
              </div>

              <div className="panel" style={{ marginTop: 16, marginBottom: 0, padding: 14 }}>
                <h3 style={{ margin: '0 0 10px', fontSize: 15 }}>Устройство и сеть</h3>
                <p className="muted" style={{ margin: '0 0 6px' }}>
                  IP: <strong>{selected.last_ip || '—'}</strong>
                </p>
                <p className="muted" style={{ margin: '0 0 6px' }}>
                  Устройство:{' '}
                  <strong>
                    {[selected.device_brand, selected.device_model].filter(Boolean).join(' ') || '—'}
                  </strong>
                </p>
                <p className="muted" style={{ margin: '0 0 6px' }}>
                  ОС: <strong>{selected.device_os || '—'}</strong>
                </p>
                <p className="muted" style={{ margin: '0 0 6px' }}>
                  Версия приложения: <strong>{selected.app_version || '—'}</strong>
                </p>
                <p className="muted" style={{ margin: '0 0 6px' }}>
                  Последний визит: <strong>{formatDate(selected.last_seen_at)}</strong>
                </p>
                <p className="muted" style={{ margin: 0 }}>
                  Регистрация: <strong>{formatDate(selected.created_at)}</strong>
                </p>
                {selected.device_info && (
                  <p className="muted" style={{ marginTop: 10, whiteSpace: 'pre-wrap', fontSize: 13 }}>
                    {selected.device_info}
                  </p>
                )}
              </div>

              {error && <p className="error">{error}</p>}
              <div className="modal-actions">
                <button className="btn" type="submit" disabled={busy}>
                  {busy ? 'Сохранение…' : 'Сохранить'}
                </button>
                <button
                  className="btn ghost"
                  type="button"
                  onClick={() => {
                    const id = selected.id;
                    setSelected(null);
                    navigate(`/moderation?authorId=${id}`);
                  }}
                >
                  Объявления
                </button>
                <button className="btn secondary" type="button" onClick={() => setSelected(null)}>
                  Закрыть
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

const EVENT_STATUS_LABELS: Record<string, string> = {
  draft: 'Черновик',
  scheduled: 'Запланировано',
  published: 'Опубликовано',
};

type EventForm = {
  title: string;
  description: string;
  starts_at: string;
  ends_at: string;
  place_text: string;
  settlement_id: number | '';
  address: string;
  is_published: boolean;
  publish_at: string;
};

const EMPTY_EVENT: EventForm = {
  title: '',
  description: '',
  starts_at: '',
  ends_at: '',
  place_text: '',
  settlement_id: '',
  address: '',
  is_published: true,
  publish_at: '',
};

function EventsPage() {
  const [items, setItems] = useState<EventItem[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [form, setForm] = useState<EventForm>(EMPTY_EVENT);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [coverPreview, setCoverPreview] = useState<string | null>(null);
  const [coverFile, setCoverFile] = useState<File | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'draft' | 'scheduled' | 'published'>('all');

  async function load() {
    const qs = statusFilter === 'all' ? '' : `?status=${statusFilter}`;
    const [ev, s] = await Promise.all([
      api<EventItem[]>(`/events${qs}`),
      api<Settlement[]>('/settlements'),
    ]);
    setItems(ev);
    setSettlements(s);
  }

  useEffect(() => {
    load().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [statusFilter]);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_EVENT);
    setCoverPreview(null);
    setCoverFile(null);
    setError('');
    setModalOpen(true);
  }

  function startEdit(item: EventItem) {
    setEditingId(item.id);
    setForm({
      title: item.title,
      description: item.description,
      starts_at: toDatetimeLocal(item.starts_at),
      ends_at: toDatetimeLocal(item.ends_at),
      place_text: item.place_text,
      settlement_id: item.settlement_id ?? '',
      address: item.address || '',
      is_published: item.is_published,
      publish_at: toDatetimeLocal(item.publish_at),
    });
    setCoverPreview(item.cover_url ? mediaUrl(item.cover_url) : null);
    setCoverFile(null);
    setError('');
    setModalOpen(true);
  }

  function closeModal() {
    if (busy) return;
    setModalOpen(false);
    setError('');
    setCoverFile(null);
  }

  async function uploadCover(eventId: number, file: File) {
    const fd = new FormData();
    fd.append('file', file);
    await api(`/events/${eventId}/cover`, { method: 'POST', body: fd });
  }

  async function saveItem(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (!form.title.trim() || !form.description.trim() || !form.place_text.trim() || !form.starts_at) {
      setError('Заполните название, описание, место и дату начала');
      return;
    }
    setBusy(true);
    setError('');
    const body = {
      title: form.title.trim(),
      description: form.description.trim(),
      starts_at: fromDatetimeLocal(form.starts_at),
      ends_at: form.ends_at ? fromDatetimeLocal(form.ends_at) : null,
      place_text: form.place_text.trim(),
      settlement_id: form.settlement_id === '' ? null : Number(form.settlement_id),
      address: form.address.trim() || null,
      is_published: form.is_published,
      publish_at: form.publish_at ? fromDatetimeLocal(form.publish_at) : null,
    };
    try {
      let id = editingId;
      if (editingId) {
        await api(`/events/${editingId}`, { method: 'PATCH', body: JSON.stringify(body) });
      } else {
        const created = await api<EventItem>('/events', { method: 'POST', body: JSON.stringify(body) });
        id = created.id;
      }
      if (id != null && coverFile) {
        await uploadCover(id, coverFile);
      }
      setModalOpen(false);
      setCoverFile(null);
      await load();
      pushToast(editingId ? 'Событие обновлено' : 'Событие создано');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function remove(id: number) {
    if (!(await confirmAction('Удалить событие? Это действие нельзя отменить.'))) return;
    await api(`/events/${id}`, { method: 'DELETE' });
    if (editingId === id) closeModal();
    await load();
    pushToast('Событие удалено');
  }

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Афиша</h1>
          <p>События района для вкладки «Афиша» в приложении</p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить событие
        </button>
      </div>
      <div className="toolbar">
        <input placeholder="Поиск…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as 'all' | 'draft' | 'scheduled' | 'published')}
        >
          <option value="all">Все статусы</option>
          <option value="draft">Черновики</option>
          <option value="scheduled">Запланированные</option>
          <option value="published">Опубликованные</option>
        </select>
      </div>
      {error && !modalOpen && <p className="error">{error}</p>}
      <div className="list">
        {items
          .filter((item) => {
            if (!query.trim()) return true;
            const q = query.trim().toLowerCase();
            return (
              item.title.toLowerCase().includes(q) ||
              item.place_text.toLowerCase().includes(q) ||
              (item.settlement_name || '').toLowerCase().includes(q)
            );
          })
          .map((item) => (
            <article key={item.id} className="row-card">
              {item.cover_url && (
                <img
                  src={mediaUrl(item.cover_url)}
                  alt=""
                  style={{ width: 72, height: 72, objectFit: 'cover', borderRadius: 10, border: '1px solid var(--line)' }}
                />
              )}
              <div className="row-main">
                <h3 className="row-title">{item.title}</h3>
                <div className="meta">
                  <span className="chip">{formatDate(item.starts_at)}</span>
                  <span className="chip neutral">{item.place_text}</span>
                  {item.settlement_name && <span className="chip neutral">{item.settlement_name}</span>}
                  <span
                    className={`chip ${item.status === 'published' ? 'ok' : item.status === 'scheduled' ? 'warn' : 'neutral'}`}
                  >
                    {EVENT_STATUS_LABELS[item.status || ''] || (item.is_published ? 'Опубликовано' : 'Черновик')}
                  </span>
                  {item.view_count != null && (
                    <span className="chip neutral">просмотры: {item.view_count}</span>
                  )}
                </div>
                <p className="row-body">{item.description.length > 160 ? `${item.description.slice(0, 160)}…` : item.description}</p>
              </div>
              <div className="actions">
                <button className="btn" type="button" onClick={() => startEdit(item)}>
                  Изменить
                </button>
                <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                  Удалить
                </button>
              </div>
            </article>
          ))}
        {!items.length && <div className="empty">Событий пока нет</div>}
      </div>

      {modalOpen && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(720px, 100%)' }}>
            <h2>{editingId ? 'Редактировать событие' : 'Новое событие'}</h2>
            <form onSubmit={saveItem}>
              <div className="grid2">
                <label className="field">
                  Название
                  <input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
                </label>
                <label className="field">
                  Место
                  <input
                    required
                    value={form.place_text}
                    onChange={(e) => setForm({ ...form, place_text: e.target.value })}
                  />
                </label>
                <label className="field">
                  Начало
                  <input
                    required
                    type="datetime-local"
                    value={form.starts_at}
                    onChange={(e) => setForm({ ...form, starts_at: e.target.value })}
                  />
                </label>
                <label className="field">
                  Окончание (необяз.)
                  <input
                    type="datetime-local"
                    value={form.ends_at}
                    onChange={(e) => setForm({ ...form, ends_at: e.target.value })}
                  />
                </label>
                <label className="field">
                  Населённый пункт
                  <select
                    value={form.settlement_id === '' ? '' : String(form.settlement_id)}
                    onChange={(e) =>
                      setForm({ ...form, settlement_id: e.target.value ? Number(e.target.value) : '' })
                    }
                  >
                    <option value="">Не указан</option>
                    {settlements.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.display_name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  Адрес
                  <input value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} />
                </label>
                <label className="field">
                  Публикация
                  <select
                    value={form.is_published ? '1' : '0'}
                    onChange={(e) => setForm({ ...form, is_published: e.target.value === '1' })}
                  >
                    <option value="1">Опубликовано</option>
                    <option value="0">Черновик / скрыто</option>
                  </select>
                </label>
                <label className="field">
                  Отложенная публикация
                  <input
                    type="datetime-local"
                    value={form.publish_at}
                    onChange={(e) => setForm({ ...form, publish_at: e.target.value })}
                  />
                </label>
                <label className="field full">
                  Обложка
                  <input
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    onChange={(e) => {
                      const file = e.target.files?.[0] || null;
                      setCoverFile(file);
                      if (file) setCoverPreview(URL.createObjectURL(file));
                    }}
                  />
                </label>
                {coverPreview && (
                  <div className="field full">
                    <img
                      src={coverPreview}
                      alt="Обложка"
                      style={{ width: 160, height: 100, objectFit: 'cover', borderRadius: 10, border: '1px solid var(--line)' }}
                    />
                  </div>
                )}
                <label className="field full">
                  Описание
                  <textarea
                    required
                    rows={6}
                    value={form.description}
                    onChange={(e) => setForm({ ...form, description: e.target.value })}
                  />
                </label>
              </div>
              {error && <p className="error">{error}</p>}
              <div className="modal-actions">
                <button className="btn" type="submit" disabled={busy}>
                  {busy ? 'Сохранение…' : 'Сохранить'}
                </button>
                <button className="btn secondary" type="button" disabled={busy} onClick={closeModal}>
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

const DAYS_MODE_LABELS: Record<string, string> = {
  all: 'Все дни',
  weekdays: 'Будни',
  weekends: 'Выходные',
};

type TransportForm = {
  title: string;
  route_number: string;
  description: string;
  schedule_text: string;
  schedule_weekdays: string;
  schedule_weekends: string;
  stops_text: string;
  days_mode: 'all' | 'weekdays' | 'weekends';
  notes: string;
  fare_text: string;
  phone: string;
  settlement_id: number | '';
  is_published: boolean;
};

const EMPTY_TRANSPORT: TransportForm = {
  title: '',
  route_number: '',
  description: '',
  schedule_text: '',
  schedule_weekdays: '',
  schedule_weekends: '',
  stops_text: '',
  days_mode: 'all',
  notes: '',
  fare_text: '',
  phone: '',
  settlement_id: '',
  is_published: true,
};

function TransportPage() {
  const [items, setItems] = useState<TransportRoute[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [form, setForm] = useState<TransportForm>(EMPTY_TRANSPORT);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [publishedFilter, setPublishedFilter] = useState<'all' | 'published' | 'hidden'>('all');

  async function load() {
    const [routes, s] = await Promise.all([
      api<TransportRoute[]>('/transport'),
      api<Settlement[]>('/settlements'),
    ]);
    setItems(routes);
    setSettlements(s);
  }

  useEffect(() => {
    load().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_TRANSPORT);
    setError('');
    setModalOpen(true);
  }

  function startEdit(item: TransportRoute) {
    setEditingId(item.id);
    setForm({
      title: item.title,
      route_number: item.route_number || '',
      description: item.description || '',
      schedule_text: item.schedule_text,
      schedule_weekdays: item.schedule_weekdays || '',
      schedule_weekends: item.schedule_weekends || '',
      stops_text: item.stops_text || '',
      days_mode: (item.days_mode as TransportForm['days_mode']) || 'all',
      notes: item.notes || '',
      fare_text: item.fare_text || '',
      phone: item.phone || '',
      settlement_id: item.settlement_id ?? '',
      is_published: item.is_published,
    });
    setError('');
    setModalOpen(true);
  }

  function closeModal() {
    if (busy) return;
    setModalOpen(false);
    setError('');
  }

  async function saveItem(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (!form.title.trim() || form.schedule_text.trim().length < 3) {
      setError('Укажите название и расписание');
      return;
    }
    setBusy(true);
    setError('');
    const body = {
      title: form.title.trim(),
      route_number: form.route_number.trim() || null,
      description: form.description.trim() || null,
      schedule_text: form.schedule_text.trim(),
      schedule_weekdays: form.schedule_weekdays.trim() || null,
      schedule_weekends: form.schedule_weekends.trim() || null,
      stops_text: form.stops_text.trim() || null,
      days_mode: form.days_mode,
      notes: form.notes.trim() || null,
      fare_text: form.fare_text.trim() || null,
      phone: form.phone.trim() || null,
      settlement_id: form.settlement_id === '' ? null : Number(form.settlement_id),
      is_published: form.is_published,
    };
    try {
      if (editingId) {
        await api(`/transport/${editingId}`, { method: 'PATCH', body: JSON.stringify(body) });
      } else {
        await api('/transport', { method: 'POST', body: JSON.stringify(body) });
      }
      setModalOpen(false);
      await load();
      pushToast(editingId ? 'Маршрут обновлён' : 'Маршрут создан');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function remove(id: number) {
    if (!(await confirmAction('Удалить маршрут?'))) return;
    await api(`/transport/${id}`, { method: 'DELETE' });
    if (editingId === id) closeModal();
    await load();
    pushToast('Маршрут удалён');
  }

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Транспорт</h1>
          <p>Статические расписания автобусов и маршруток</p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить маршрут
        </button>
      </div>
      <div className="toolbar">
        <input placeholder="Поиск…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select
          value={publishedFilter}
          onChange={(e) => setPublishedFilter(e.target.value as 'all' | 'published' | 'hidden')}
        >
          <option value="all">Все статусы</option>
          <option value="published">Опубликованные</option>
          <option value="hidden">Скрытые</option>
        </select>
      </div>
      {error && !modalOpen && <p className="error">{error}</p>}
      <div className="list">
        {items
          .filter((item) => {
            if (publishedFilter === 'published' && !item.is_published) return false;
            if (publishedFilter === 'hidden' && item.is_published) return false;
            if (!query.trim()) return true;
            const q = query.trim().toLowerCase();
            return (
              item.title.toLowerCase().includes(q) ||
              (item.route_number || '').toLowerCase().includes(q) ||
              (item.settlement_name || '').toLowerCase().includes(q)
            );
          })
          .map((item) => (
            <article key={item.id} className="row-card">
              <div className="row-main">
                <h3 className="row-title">
                  {item.route_number ? `${item.route_number} · ` : ''}
                  {item.title}
                </h3>
                <div className="meta">
                  {item.settlement_name && <span className="chip neutral">{item.settlement_name}</span>}
                  <span className="chip neutral">{DAYS_MODE_LABELS[item.days_mode || 'all'] || item.days_mode}</span>
                  {item.is_published ? <span className="chip ok">Опубликовано</span> : <span className="chip warn">Скрыто</span>}
                  {item.view_count != null && (
                    <span className="chip neutral">просмотры: {item.view_count}</span>
                  )}
                  <span className="chip neutral">обн. {formatDate(item.updated_at)}</span>
                </div>
                <p className="row-body" style={{ whiteSpace: 'pre-wrap' }}>
                  {item.schedule_text.length > 180 ? `${item.schedule_text.slice(0, 180)}…` : item.schedule_text}
                </p>
              </div>
              <div className="actions">
                <button className="btn" type="button" onClick={() => startEdit(item)}>
                  Изменить
                </button>
                <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                  Удалить
                </button>
              </div>
            </article>
          ))}
        {!items.length && <div className="empty">Маршрутов пока нет</div>}
      </div>

      {modalOpen && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(720px, 100%)' }}>
            <h2>{editingId ? 'Редактировать маршрут' : 'Новый маршрут'}</h2>
            <form onSubmit={saveItem}>
              <div className="grid2">
                <label className="field">
                  Название
                  <input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
                </label>
                <label className="field">
                  Номер / тип
                  <input
                    value={form.route_number}
                    onChange={(e) => setForm({ ...form, route_number: e.target.value })}
                    placeholder="112 / м/т"
                  />
                </label>
                <label className="field">
                  Населённый пункт
                  <select
                    value={form.settlement_id === '' ? '' : String(form.settlement_id)}
                    onChange={(e) =>
                      setForm({ ...form, settlement_id: e.target.value ? Number(e.target.value) : '' })
                    }
                  >
                    <option value="">Не указан</option>
                    {settlements.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.display_name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  Дни работы
                  <select
                    value={form.days_mode}
                    onChange={(e) =>
                      setForm({ ...form, days_mode: e.target.value as TransportForm['days_mode'] })
                    }
                  >
                    <option value="all">Все дни</option>
                    <option value="weekdays">Будни</option>
                    <option value="weekends">Выходные</option>
                  </select>
                </label>
                <label className="field">
                  Статус
                  <select
                    value={form.is_published ? '1' : '0'}
                    onChange={(e) => setForm({ ...form, is_published: e.target.value === '1' })}
                  >
                    <option value="1">Опубликовано</option>
                    <option value="0">Скрыто</option>
                  </select>
                </label>
                <label className="field full">
                  Краткое описание
                  <input value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
                </label>
                <label className="field full">
                  Остановки (по одной в строке)
                  <textarea
                    rows={5}
                    value={form.stops_text}
                    onChange={(e) => setForm({ ...form, stops_text: e.target.value })}
                    placeholder={'Сакмара (остановка у ДК)\nТатарская Каргала\nОренбург, автовокзал'}
                  />
                </label>
                <label className="field full">
                  Расписание (общее)
                  <textarea
                    required
                    rows={6}
                    value={form.schedule_text}
                    onChange={(e) => setForm({ ...form, schedule_text: e.target.value })}
                    placeholder="Времена отправления…"
                  />
                </label>
                <label className="field full">
                  Расписание в будни (необяз.)
                  <textarea
                    rows={3}
                    value={form.schedule_weekdays}
                    onChange={(e) => setForm({ ...form, schedule_weekdays: e.target.value })}
                  />
                </label>
                <label className="field full">
                  Расписание в выходные (необяз.)
                  <textarea
                    rows={3}
                    value={form.schedule_weekends}
                    onChange={(e) => setForm({ ...form, schedule_weekends: e.target.value })}
                  />
                </label>
                <label className="field">
                  Цена проезда
                  <input
                    value={form.fare_text}
                    onChange={(e) => setForm({ ...form, fare_text: e.target.value })}
                    placeholder="напр. 45 ₽"
                  />
                </label>
                <label className="field">
                  Телефон перевозчика
                  <input
                    value={form.phone}
                    onChange={(e) => setForm({ ...form, phone: e.target.value })}
                    placeholder="+7…"
                  />
                </label>
                <label className="field full">
                  Заметки
                  <textarea rows={3} value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
                </label>
              </div>
              {error && <p className="error">{error}</p>}
              <div className="modal-actions">
                <button className="btn" type="submit" disabled={busy}>
                  {busy ? 'Сохранение…' : 'Сохранить'}
                </button>
                <button className="btn secondary" type="button" disabled={busy} onClick={closeModal}>
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

type NewsForm = {
  title: string;
  body: string;
  settlement_id: number | '';
  is_published: boolean;
  is_pinned: boolean;
};

const EMPTY_NEWS: NewsForm = {
  title: '',
  body: '',
  settlement_id: '',
  is_published: true,
  is_pinned: false,
};

function NewsPage() {
  const [items, setItems] = useState<NewsItem[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [form, setForm] = useState<NewsForm>(EMPTY_NEWS);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [publishedFilter, setPublishedFilter] = useState<'all' | 'published' | 'hidden'>('all');
  const [coverFile, setCoverFile] = useState<File | null>(null);

  async function load() {
    const [news, s] = await Promise.all([
      api<NewsItem[]>('/news'),
      api<Settlement[]>('/settlements'),
    ]);
    setItems(news);
    setSettlements(s);
  }

  useEffect(() => {
    load().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_NEWS);
    setCoverFile(null);
    setError('');
    setModalOpen(true);
  }

  function startEdit(item: NewsItem) {
    setEditingId(item.id);
    setForm({
      title: item.title,
      body: item.body,
      settlement_id: item.settlement_id ?? '',
      is_published: item.is_published,
      is_pinned: !!item.is_pinned,
    });
    setCoverFile(null);
    setError('');
    setModalOpen(true);
  }

  function closeModal() {
    if (busy) return;
    setModalOpen(false);
    setError('');
  }

  async function saveItem(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (!form.title.trim() || form.body.trim().length < 3) {
      setError('Укажите заголовок и текст новости');
      return;
    }
    setBusy(true);
    setError('');
    const body = {
      title: form.title.trim(),
      body: form.body.trim(),
      settlement_id: form.settlement_id === '' ? null : Number(form.settlement_id),
      is_published: form.is_published,
      is_pinned: form.is_pinned,
    };
    try {
      let id = editingId;
      if (editingId) {
        await api(`/news/${editingId}`, { method: 'PATCH', body: JSON.stringify(body) });
      } else {
        const created = await api<NewsItem>('/news', { method: 'POST', body: JSON.stringify(body) });
        id = created.id;
      }
      if (coverFile && id) {
        const fd = new FormData();
        fd.append('file', coverFile);
        await api(`/news/${id}/cover`, { method: 'POST', body: fd });
      }
      setModalOpen(false);
      await load();
      pushToast(editingId ? 'Новость обновлена' : 'Новость создана');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function remove(id: number) {
    if (!(await confirmAction('Удалить новость?'))) return;
    await api(`/news/${id}`, { method: 'DELETE' });
    if (editingId === id) closeModal();
    await load();
    pushToast('Новость удалена');
  }

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Новости</h1>
          <p>Новости района для приложения</p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить новость
        </button>
      </div>
      <div className="toolbar">
        <input placeholder="Поиск…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select
          value={publishedFilter}
          onChange={(e) => setPublishedFilter(e.target.value as 'all' | 'published' | 'hidden')}
        >
          <option value="all">Все статусы</option>
          <option value="published">Опубликованные</option>
          <option value="hidden">Скрытые</option>
        </select>
      </div>
      {error && !modalOpen && <p className="error">{error}</p>}
      <div className="list">
        {items
          .filter((item) => {
            if (publishedFilter === 'published' && !item.is_published) return false;
            if (publishedFilter === 'hidden' && item.is_published) return false;
            if (!query.trim()) return true;
            const q = query.trim().toLowerCase();
            return (
              item.title.toLowerCase().includes(q) ||
              item.body.toLowerCase().includes(q) ||
              (item.settlement_name || '').toLowerCase().includes(q)
            );
          })
          .map((item) => (
            <article key={item.id} className="row-card">
              <div className="row-main">
                <h3 className="row-title">{item.title}</h3>
                <div className="meta">
                  {item.settlement_name && <span className="chip neutral">{item.settlement_name}</span>}
                  {item.is_published ? (
                    <span className="chip ok">Опубликовано</span>
                  ) : (
                    <span className="chip warn">Скрыто</span>
                  )}
                  <span className="chip neutral">{formatDate(item.published_at || item.created_at)}</span>
                </div>
                <p className="row-body">{item.body.length > 160 ? `${item.body.slice(0, 160)}…` : item.body}</p>
              </div>
              <div className="actions">
                <button className="btn" type="button" onClick={() => startEdit(item)}>
                  Изменить
                </button>
                <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                  Удалить
                </button>
              </div>
            </article>
          ))}
        {!items.length && <div className="empty">Новостей пока нет</div>}
      </div>

      {modalOpen && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(720px, 100%)' }}>
            <h2>{editingId ? 'Редактировать новость' : 'Новая новость'}</h2>
            <form onSubmit={saveItem}>
              <div className="grid2">
                <label className="field">
                  Заголовок
                  <input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
                </label>
                <label className="field">
                  Населённый пункт
                  <select
                    value={form.settlement_id === '' ? '' : String(form.settlement_id)}
                    onChange={(e) =>
                      setForm({ ...form, settlement_id: e.target.value ? Number(e.target.value) : '' })
                    }
                  >
                    <option value="">Весь район</option>
                    {settlements.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.display_name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  Статус
                  <select
                    value={form.is_published ? '1' : '0'}
                    onChange={(e) => setForm({ ...form, is_published: e.target.value === '1' })}
                  >
                    <option value="1">Опубликовано</option>
                    <option value="0">Скрыто</option>
                  </select>
                </label>
                <label className="field">
                  Закрепить
                  <select
                    value={form.is_pinned ? '1' : '0'}
                    onChange={(e) => setForm({ ...form, is_pinned: e.target.value === '1' })}
                  >
                    <option value="0">Нет</option>
                    <option value="1">Да</option>
                  </select>
                </label>
                <label className="field full">
                  Обложка
                  <input type="file" accept="image/*" onChange={(e) => setCoverFile(e.target.files?.[0] || null)} />
                </label>
                <label className="field full">
                  Текст
                  <textarea
                    required
                    rows={8}
                    value={form.body}
                    onChange={(e) => setForm({ ...form, body: e.target.value })}
                  />
                </label>
              </div>
              {error && <p className="error">{error}</p>}
              <div className="modal-actions">
                <button className="btn" type="submit" disabled={busy}>
                  {busy ? 'Сохранение…' : 'Сохранить'}
                </button>
                <button className="btn secondary" type="button" disabled={busy} onClick={closeModal}>
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

const ALERT_KIND_LABELS: Record<string, string> = {
  info: 'Инфо',
  warn: 'Важно',
  danger: 'Срочно',
};

type AlertForm = {
  message: string;
  kind: 'info' | 'warn' | 'danger';
  priority: number;
  is_active: boolean;
  starts_at: string;
  ends_at: string;
};

const EMPTY_ALERT: AlertForm = {
  message: '',
  kind: 'info',
  priority: 0,
  is_active: true,
  starts_at: '',
  ends_at: '',
};

function AlertsPage() {
  const [items, setItems] = useState<DistrictAlert[]>([]);
  const [history, setHistory] = useState<DistrictAlert[]>([]);
  const [tab, setTab] = useState<'active' | 'history'>('active');
  const [form, setForm] = useState<AlertForm>(EMPTY_ALERT);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    const [all, hist] = await Promise.all([
      api<DistrictAlert[]>('/alerts'),
      api<DistrictAlert[]>('/alerts?history=1'),
    ]);
    setItems(all);
    setHistory(hist);
  }

  useEffect(() => {
    load().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_ALERT);
    setError('');
    setModalOpen(true);
  }

  function startEdit(item: DistrictAlert) {
    setEditingId(item.id);
    setForm({
      message: item.message,
      kind: (item.kind as AlertForm['kind']) || 'info',
      priority: item.priority ?? 0,
      is_active: item.is_active,
      starts_at: toDatetimeLocal(item.starts_at),
      ends_at: toDatetimeLocal(item.ends_at),
    });
    setError('');
    setModalOpen(true);
  }

  function closeModal() {
    if (busy) return;
    setModalOpen(false);
    setError('');
  }

  async function saveItem(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (form.message.trim().length < 3) {
      setError('Укажите текст объявления (от 3 символов)');
      return;
    }
    setBusy(true);
    setError('');
    const body = {
      message: form.message.trim(),
      kind: form.kind,
      priority: Number(form.priority) || 0,
      is_active: form.is_active,
      starts_at: form.starts_at ? new Date(form.starts_at).toISOString() : null,
      ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null,
    };
    try {
      if (editingId) {
        await api(`/alerts/${editingId}`, { method: 'PATCH', body: JSON.stringify(body) });
      } else {
        await api('/alerts', { method: 'POST', body: JSON.stringify(body) });
      }
      setModalOpen(false);
      await load();
      pushToast(editingId ? 'Объявление обновлено' : 'Объявление создано');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function remove(id: number) {
    if (!(await confirmAction('Удалить срочное объявление?'))) return;
    await api(`/alerts/${id}`, { method: 'DELETE' });
    if (editingId === id) closeModal();
    await load();
    pushToast('Объявление удалено');
  }

  const shown = tab === 'history' ? history : items;

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Срочное</h1>
          <p>Несколько баннеров по приоритету. Срок действия и история прошлых оповещений.</p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить объявление
        </button>
      </div>
      <div className="toolbar compact">
        <button type="button" className={`btn ${tab === 'active' ? '' : 'secondary'}`} onClick={() => setTab('active')}>
          Все / текущие
        </button>
        <button type="button" className={`btn ${tab === 'history' ? '' : 'secondary'}`} onClick={() => setTab('history')}>
          История
        </button>
      </div>
      {error && !modalOpen && <p className="error">{error}</p>}
      <div className="list">
        {shown.map((item) => (
          <article key={item.id} className="row-card">
            <div className="row-main">
              <h3 className="row-title">{item.message}</h3>
              <div className="meta">
                <span
                  className={`chip ${item.kind === 'danger' ? 'warn' : item.kind === 'warn' ? 'warn' : 'neutral'}`}
                >
                  {ALERT_KIND_LABELS[item.kind] || item.kind}
                </span>
                <span className="chip neutral">приоритет {item.priority ?? 0}</span>
                {item.is_active ? (
                  <span className="chip ok">Активно</span>
                ) : (
                  <span className="chip neutral">Выкл.</span>
                )}
                {item.ends_at && <span className="chip neutral">до {formatDate(item.ends_at)}</span>}
                <span className="chip neutral">{formatDate(item.updated_at)}</span>
              </div>
            </div>
            <div className="actions">
              <button className="btn" type="button" onClick={() => startEdit(item)}>
                Изменить
              </button>
              <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                Удалить
              </button>
            </div>
          </article>
        ))}
        {!shown.length && <div className="empty">{tab === 'history' ? 'История пуста' : 'Срочных объявлений пока нет'}</div>}
      </div>

      {modalOpen && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(560px, 100%)' }}>
            <h2>{editingId ? 'Редактировать объявление' : 'Новое объявление'}</h2>
            <form onSubmit={saveItem}>
              <div className="grid2">
                <label className="field full">
                  Текст
                  <textarea
                    required
                    rows={4}
                    maxLength={280}
                    value={form.message}
                    onChange={(e) => setForm({ ...form, message: e.target.value })}
                  />
                </label>
                <label className="field">
                  Тип
                  <select
                    value={form.kind}
                    onChange={(e) => setForm({ ...form, kind: e.target.value as AlertForm['kind'] })}
                  >
                    <option value="info">Инфо</option>
                    <option value="warn">Важно</option>
                    <option value="danger">Срочно</option>
                  </select>
                </label>
                <label className="field">
                  Статус
                  <select
                    value={form.is_active ? '1' : '0'}
                    onChange={(e) => setForm({ ...form, is_active: e.target.value === '1' })}
                  >
                    <option value="1">Активно</option>
                    <option value="0">Выкл.</option>
                  </select>
                </label>
                <label className="field">
                  Приоритет (выше = важнее)
                  <input
                    type="number"
                    min={0}
                    max={100}
                    value={form.priority}
                    onChange={(e) => setForm({ ...form, priority: Number(e.target.value) || 0 })}
                  />
                </label>
                <label className="field">
                  Начало показа
                  <input
                    type="datetime-local"
                    value={form.starts_at}
                    onChange={(e) => setForm({ ...form, starts_at: e.target.value })}
                  />
                </label>
                <label className="field">
                  Окончание показа
                  <input
                    type="datetime-local"
                    value={form.ends_at}
                    onChange={(e) => setForm({ ...form, ends_at: e.target.value })}
                  />
                </label>
              </div>
              {error && <p className="error">{error}</p>}
              <div className="modal-actions">
                <button className="btn" type="submit" disabled={busy}>
                  {busy ? 'Сохранение…' : 'Сохранить'}
                </button>
                <button className="btn secondary" type="button" disabled={busy} onClick={closeModal}>
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

function EditorialCalendarPage() {
  const [month, setMonth] = useState(() => {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth(), 1);
  });
  const [events, setEvents] = useState<EventItem[]>([]);
  const [news, setNews] = useState<NewsItem[]>([]);
  const [alerts, setAlerts] = useState<DistrictAlert[]>([]);
  const [error, setError] = useState('');

  useEffect(() => {
    Promise.all([
      api<EventItem[]>('/events'),
      api<NewsItem[]>('/news'),
      api<DistrictAlert[]>('/alerts'),
    ])
      .then(([ev, n, a]) => {
        setEvents(ev);
        setNews(n);
        setAlerts(a);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  const year = month.getFullYear();
  const mon = month.getMonth();
  const daysInMonth = new Date(year, mon + 1, 0).getDate();
  const startWeekday = (new Date(year, mon, 1).getDay() + 6) % 7; // пн=0

  function itemsForDay(day: number) {
    const key = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    const dayEvents = events.filter((e) => (e.publish_at || e.starts_at || '').startsWith(key));
    const dayNews = news.filter((n) => (n.published_at || n.created_at || '').startsWith(key));
    const dayAlerts = alerts.filter((a) => (a.starts_at || a.created_at || '').startsWith(key));
    return { dayEvents, dayNews, dayAlerts };
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Редакторский календарь</h1>
          <p>Сетка месяца: события, новости и срочные по дате публикации / старта</p>
        </div>
        <div className="toolbar compact">
          <button
            type="button"
            className="btn secondary"
            onClick={() => setMonth(new Date(year, mon - 1, 1))}
          >
            ←
          </button>
          <strong>
            {month.toLocaleDateString('ru-RU', { month: 'long', year: 'numeric' })}
          </strong>
          <button
            type="button"
            className="btn secondary"
            onClick={() => setMonth(new Date(year, mon + 1, 1))}
          >
            →
          </button>
        </div>
      </div>
      {error && <p className="error">{error}</p>}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(7, 1fr)',
          gap: 6,
        }}
      >
        {['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'].map((d) => (
          <div key={d} className="muted" style={{ textAlign: 'center', fontSize: 12 }}>
            {d}
          </div>
        ))}
        {Array.from({ length: startWeekday }).map((_, i) => (
          <div key={`e-${i}`} />
        ))}
        {Array.from({ length: daysInMonth }).map((_, i) => {
          const day = i + 1;
          const { dayEvents, dayNews, dayAlerts } = itemsForDay(day);
          return (
            <div
              key={day}
              className="panel"
              style={{ minHeight: 88, padding: 8, margin: 0 }}
            >
              <strong style={{ fontSize: 13 }}>{day}</strong>
              <ul style={{ margin: '6px 0 0', padding: 0, listStyle: 'none', fontSize: 11 }}>
                {dayEvents.map((e) => (
                  <li key={`e-${e.id}`} title={e.title}>
                    Аф: {e.title.slice(0, 28)}
                  </li>
                ))}
                {dayNews.map((n) => (
                  <li key={`n-${n.id}`} title={n.title}>
                    Нов: {n.title.slice(0, 28)}
                  </li>
                ))}
                {dayAlerts.map((a) => (
                  <li key={`a-${a.id}`} title={a.message}>
                    Ср: {a.message.slice(0, 28)}
                  </li>
                ))}
              </ul>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function LegalPage() {
  const [items, setItems] = useState<LegalDocument[]>([]);
  const [selected, setSelected] = useState<LegalDocument | null>(null);
  const [form, setForm] = useState({ title: '', body: '', version: '' });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    setItems(await api<LegalDocument[]>('/legal'));
  }

  useEffect(() => {
    load().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  function openEdit(doc: LegalDocument) {
    setSelected(doc);
    setForm({ title: doc.title, body: doc.body, version: doc.version });
    setError('');
  }

  function closeModal() {
    if (busy) return;
    setSelected(null);
    setError('');
  }

  async function saveDoc(e: React.FormEvent) {
    e.preventDefault();
    if (!selected || busy) return;
    if (!form.title.trim() || form.body.trim().length < 10 || !form.version.trim()) {
      setError('Заполните название, текст (от 10 символов) и версию');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const updated = await api<LegalDocument>(`/legal/${selected.slug}`, {
        method: 'PATCH',
        body: JSON.stringify({
          title: form.title.trim(),
          body: form.body.trim(),
          version: form.version.trim(),
        }),
      });
      setItems((prev) => prev.map((d) => (d.slug === updated.slug ? updated : d)));
      setSelected(null);
      pushToast('Документ сохранён');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Правовые документы</h1>
          <p>Политика, условия и другие тексты сервиса</p>
        </div>
      </div>
      {error && !selected && <p className="error">{error}</p>}
      <div className="list compact">
        {items.map((doc) => (
          <article key={doc.slug} className="row-card compact">
            <div className="row-main">
              <h3 className="row-title">{doc.title}</h3>
              <div className="meta">
                <span className="chip neutral">{doc.slug}</span>
                <span className="chip">v{doc.version}</span>
                <span className="chip neutral">{formatDate(doc.updated_at)}</span>
              </div>
              <p className="row-body">
                {doc.body.length > 140 ? `${doc.body.slice(0, 140)}…` : doc.body}
              </p>
            </div>
            <div className="actions inline">
              <button className="btn" type="button" onClick={() => openEdit(doc)}>
                Изменить
              </button>
            </div>
          </article>
        ))}
        {!items.length && <div className="empty">Документов пока нет</div>}
      </div>

      {selected && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(720px, 100%)' }}>
            <h2>Редактировать: {selected.slug}</h2>
            <form onSubmit={saveDoc}>
              <div className="grid2">
                <label className="field">
                  Название
                  <input
                    required
                    value={form.title}
                    onChange={(e) => setForm({ ...form, title: e.target.value })}
                  />
                </label>
                <label className="field">
                  Версия
                  <input
                    required
                    value={form.version}
                    onChange={(e) => setForm({ ...form, version: e.target.value })}
                  />
                </label>
                <label className="field full">
                  Текст
                  <textarea
                    required
                    rows={12}
                    value={form.body}
                    onChange={(e) => setForm({ ...form, body: e.target.value })}
                  />
                </label>
              </div>
              {error && <p className="error">{error}</p>}
              <div className="modal-actions">
                <button className="btn" type="submit" disabled={busy}>
                  {busy ? 'Сохранение…' : 'Сохранить'}
                </button>
                <button className="btn secondary" type="button" disabled={busy} onClick={closeModal}>
                  Отмена
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

function formatBytes(n?: number | null) {
  if (n == null || n <= 0) return '—';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} КБ`;
  return `${(n / (1024 * 1024)).toFixed(1)} МБ`;
}

function AppUpdatePage() {
  const [info, setInfo] = useState<AppUpdateInfo | null>(null);
  const [version, setVersion] = useState('');
  const [build, setBuild] = useState('');
  const [notes, setNotes] = useState('');
  const [force, setForce] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [uploadBusy, setUploadBusy] = useState(false);

  async function load() {
    const data = await api<AppUpdateInfo>('/app/update/admin');
    setInfo(data);
    setVersion(data.version);
    setBuild(String(data.build));
    setNotes(data.notes || '');
    setForce(!!data.force);
  }

  useEffect(() => {
    load().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    const code = Number(build);
    if (!version.trim() || !Number.isFinite(code) || code < 1) {
      setError('Укажите версию и номер сборки (build ≥ 1)');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const updated = await api<AppUpdateInfo>('/app/update', {
        method: 'PATCH',
        body: JSON.stringify({
          version_name: version.trim(),
          version_code: code,
          force_update: force,
          notes: notes.trim() || null,
        }),
      });
      setInfo(updated);
      pushToast('Настройки обновления сохранены');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function uploadApk(file: File | null) {
    if (!file) return;
    if (!file.name.toLowerCase().endsWith('.apk')) {
      setError('Нужен файл .apk');
      return;
    }
    setUploadBusy(true);
    setError('');
    try {
      const fd = new FormData();
      fd.append('file', file);
      const updated = await api<AppUpdateInfo>('/app/apk', { method: 'POST', body: fd });
      setInfo(updated);
      pushToast('APK загружен на сервер');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка загрузки');
    } finally {
      setUploadBusy(false);
    }
  }

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Обновления приложения</h1>
          <p>
            Приложение при запуске сравнивает свой build с этим номером. Если на сервере выше — предложит
            скачать и установить APK.
          </p>
        </div>
      </div>

      <div className="panel" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Сейчас на сервере</h3>
        {!info ? (
          <p className="muted">Загрузка…</p>
        ) : (
          <>
            <p className="muted" style={{ margin: '0 0 6px' }}>
              Версия: <strong>{info.version}+{info.build}</strong>
              {info.force ? ' · принудительное' : ''}
            </p>
            <p className="muted" style={{ margin: '0 0 6px' }}>
              APK: <strong>{info.has_apk ? `${info.apk_filename || 'есть'} (${formatBytes(info.apk_size)})` : 'не загружен'}</strong>
            </p>
            <p className="muted" style={{ margin: 0 }}>
              Обновлено: <strong>{formatDate(info.published_at)}</strong>
            </p>
          </>
        )}
      </div>

      <form onSubmit={save} className="panel" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Параметры версии</h3>
        <div className="grid2">
          <label className="field">
            Версия (например 0.12.0)
            <input required value={version} onChange={(e) => setVersion(e.target.value)} />
          </label>
          <label className="field">
            Build number (versionCode)
            <input required type="number" min={1} value={build} onChange={(e) => setBuild(e.target.value)} />
          </label>
          <label className="field full">
            Что нового
            <textarea rows={4} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Кратко для пользователей" />
          </label>
        </div>
        <label className="check-inline" style={{ marginTop: 12 }}>
          <input type="checkbox" checked={force} onChange={(e) => setForce(e.target.checked)} />
          Принудительное обновление (нельзя закрыть «Позже»)
        </label>
        {error && <p className="error">{error}</p>}
        <div className="modal-actions" style={{ marginTop: 16 }}>
          <button className="btn" type="submit" disabled={busy}>
            {busy ? 'Сохранение…' : 'Сохранить'}
          </button>
        </div>
      </form>

      <div className="panel">
        <h3 style={{ marginTop: 0 }}>Загрузить APK</h3>
        <p className="muted">После сборки APK загрузите файл сюда. Телефоны скачают его с вашего API.</p>
        <input
          type="file"
          accept=".apk,application/vnd.android.package-archive"
          disabled={uploadBusy}
          onChange={(e) => uploadApk(e.target.files?.[0] || null)}
        />
        {uploadBusy && <p className="muted">Загрузка APK…</p>}
      </div>
    </div>
  );
}

export default function App() {
  const { user, setUser, loading } = useAuth();
  const navigate = useNavigate();
  const { theme, toggle } = useTheme();

  const authed = useMemo(() => !!user && ['admin', 'moderator', 'editor'].includes(user.role), [user]);

  if (loading) {
    return (
      <div className="login-wrap">
        <div className="login-card">
          <p className="brand">Рядом56</p>
          <h1>Загрузка…</h1>
        </div>
      </div>
    );
  }

  if (!authed) {
    return (
      <LoginPage
        onLogin={(u) => {
          setUser(u);
          navigate('/');
        }}
      />
    );
  }

  return (
    <Shell
      user={user!}
      theme={theme}
      onToggleTheme={toggle}
      onLogout={() => {
        setToken(null);
        setUser(null);
      }}
    >
      <Routes>
        <Route path="/" element={<Dashboard isAdmin={user!.role === 'admin'} />} />
        {canModerate(user!.role) && <Route path="/moderation" element={<ModerationPage />} />}
        {canModerate(user!.role) && <Route path="/reports" element={<ReportsPage />} />}
        <Route path="/audit" element={<AuditPage />} />
        {canEditDirectory(user!.role) && <Route path="/directory" element={<DirectoryPage />} />}
        {canEditDirectory(user!.role) && <Route path="/events" element={<EventsPage />} />}
        {canEditDirectory(user!.role) && <Route path="/calendar" element={<EditorialCalendarPage />} />}
        {canEditDirectory(user!.role) && <Route path="/transport" element={<TransportPage />} />}
        {canEditDirectory(user!.role) && <Route path="/news" element={<NewsPage />} />}
        {canEditDirectory(user!.role) && <Route path="/alerts" element={<AlertsPage />} />}
        {canModerate(user!.role) && <Route path="/blacklist" element={<BlacklistPage />} />}
        {user!.role === 'admin' && <Route path="/users" element={<UsersPage />} />}
        {user!.role === 'admin' && <Route path="/legal" element={<LegalPage />} />}
        {user!.role === 'admin' && <Route path="/app-update" element={<AppUpdatePage />} />}
        <Route
          path="*"
          element={
            <Navigate
              to={user!.role === 'editor' ? '/directory' : user!.role === 'moderator' ? '/moderation' : '/'}
              replace
            />
          }
        />
      </Routes>
    </Shell>
  );
}
