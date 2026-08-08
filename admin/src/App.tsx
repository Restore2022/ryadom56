import { useEffect, useMemo, useState } from 'react';
import { Navigate, NavLink, Route, Routes, useNavigate, useSearchParams } from 'react-router-dom';
import { api, apiText, mediaUrl, setToken } from './api';
import type {
  AuditLog,
  BlacklistEntry,
  DirectoryItem,
  Listing,
  ListingReport,
  Settlement,
  Stats,
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
    setBusy(true);
    setError('');
    try {
      const token = await api<{ access_token: string }>('/auth/login', {
        method: 'POST',
        body: JSON.stringify({ email, password }),
      });
      setToken(token.access_token);
      const me = await api<User>('/auth/me');
      if (!['admin', 'moderator', 'editor'].includes(me.role)) {
        setToken(null);
        throw new Error('Нет доступа в админку');
      }
      onLogin(me);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка входа');
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
    </div>
  );
}

function Dashboard() {
  const [stats, setStats] = useState<Stats | null>(null);
  useEffect(() => {
    api<Stats>('/admin/stats').then(setStats).catch(console.error);
  }, []);

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
      </div>
    </div>
  );
}

function ModerationPage() {
  const [searchParams] = useSearchParams();
  const listingIdParam = searchParams.get('listingId');
  const [items, setItems] = useState<Listing[]>([]);
  const [filter, setFilter] = useState(() => (listingIdParam ? '' : 'pending'));
  const [closedOnly, setClosedOnly] = useState(false);
  const [category, setCategory] = useState('');
  const [query, setQuery] = useState('');
  const [serverQuery, setServerQuery] = useState('');
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<number | null>(null);
  const [selected, setSelected] = useState<Listing | null>(null);
  const [checked, setChecked] = useState<number[]>([]);
  const [bulkBusy, setBulkBusy] = useState(false);
  const [moderationNote, setModerationNote] = useState('');

  function closeModal() {
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
      if (filter === 'pending' || !filter) params.set('sort', 'sla');
      const qs = params.toString();
      setItems(await api<Listing[]>(`/listings/admin/all${qs ? `?${qs}` : ''}`));
      setChecked([]);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  useEffect(() => {
    load();
  }, [filter, closedOnly, serverQuery]);

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
    if (status === 'rejected') {
      if (!(noteOverride ?? moderationNote).trim()) {
        setError('Укажите причину отклонения');
        return;
      }
    }
    setBusyId(id);
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
    } finally {
      setBusyId(null);
    }
  }

  async function bulkModerate(status: 'approved' | 'rejected') {
    const ids = checked.filter((id) => items.some((x) => x.id === id && needsModeration(x)));
    if (!ids.length) return;
    let moderation_note: string | null = null;
    if (status === 'rejected') {
      const note = window.prompt('Причина отклонения для автора');
      if (note === null) return;
      if (!note.trim()) {
        alert('Укажите причину отклонения');
        return;
      }
      moderation_note = note.trim();
    }
    setBulkBusy(true);
    try {
      await api('/admin/listings/bulk-moderate', {
        method: 'POST',
        body: JSON.stringify({ ids, status, moderation_note }),
      });
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
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

  return (
    <div className="moderation-page">
      <div className="page-head compact">
        <div>
          <h1>Модерация</h1>
          <p>
            Очередь по SLA (дольше ждут сверху)
            {over24 > 0 ? ` · старше 24 ч: ${over24}` : ''}
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
      </div>

      {pendingChecked.length > 0 && (
        <div className="toolbar compact">
          <span className="muted">Выбрано: {pendingChecked.length}</span>
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
        <div className="modal-backdrop" onClick={closeModal}>
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

  async function setReportStatus(id: number, next: 'reviewed' | 'dismissed') {
    const reply = window.prompt('Короткий ответ автору жалобы (необязательно)');
    await api(`/admin/reports/${id}`, {
      method: 'PATCH',
      body: JSON.stringify({ status: next, moderator_reply: reply?.trim() || null }),
    });
    await load();
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
      {error && <p className="error">{error}</p>}
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
                <span className="chip">{r.status}</span>
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
                  <button className="btn" type="button" onClick={() => setReportStatus(r.id, 'reviewed')}>
                    Просмотрено
                  </button>
                  <button className="btn secondary" type="button" onClick={() => setReportStatus(r.id, 'dismissed')}>
                    Отклонить
                  </button>
                </>
              )}
            </div>
          </article>
        ))}
        {!items.length && <div className="empty">Жалоб нет</div>}
      </div>
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
    if (!confirm('Удалить запись из справочника?')) return;
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
      </div>

      <div className="list">
        {items
          .filter((item) => {
            if (categoryFilter && item.category !== categoryFilter) return false;
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
    await api(`/admin/blacklist/${id}`, { method: 'DELETE' });
    await load();
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
    if (!selected) return;
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
        <Route path="/" element={<Dashboard />} />
        {canModerate(user!.role) && <Route path="/moderation" element={<ModerationPage />} />}
        {canModerate(user!.role) && <Route path="/reports" element={<ReportsPage />} />}
        <Route path="/audit" element={<AuditPage />} />
        {canEditDirectory(user!.role) && <Route path="/directory" element={<DirectoryPage />} />}
        {canModerate(user!.role) && <Route path="/blacklist" element={<BlacklistPage />} />}
        {user!.role === 'admin' && <Route path="/users" element={<UsersPage />} />}
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
