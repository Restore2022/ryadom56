import { useEffect, useMemo, useState } from 'react';
import { Navigate, NavLink, Route, Routes, useNavigate } from 'react-router-dom';
import { api, setToken } from './api';
import type { DirectoryItem, Listing, Settlement, Stats, User } from './api';
import './App.css';

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
  archived: 'В архиве',
};

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
          <NavLink to="/moderation">
            <span className="nav-ico">☰</span> Модерация
          </NavLink>
          <NavLink to="/directory">
            <span className="nav-ico">◎</span> Справочник
          </NavLink>
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

  return (
    <div>
      <div className="page-head">
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
          <div className="label">Населённых пунктов</div>
          <div className="value">{stats.settlements}</div>
        </div>
      </div>
    </div>
  );
}

function ModerationPage() {
  const [items, setItems] = useState<Listing[]>([]);
  const [filter, setFilter] = useState('pending');
  const [category, setCategory] = useState('');
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<number | null>(null);
  const [selected, setSelected] = useState<Listing | null>(null);

  async function load() {
    try {
      const q = filter ? `?status=${filter}` : '';
      setItems(await api<Listing[]>(`/listings/admin/all${q}`));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  useEffect(() => {
    load();
  }, [filter]);

  const visible = useMemo(() => {
    return items.filter((item) => {
      if (category && item.category !== category) return false;
      if (query.trim()) {
        const q = query.trim().toLowerCase();
        return (
          item.title.toLowerCase().includes(q) ||
          item.description.toLowerCase().includes(q) ||
          (item.author_name || '').toLowerCase().includes(q) ||
          (item.settlement_name || '').toLowerCase().includes(q)
        );
      }
      return true;
    });
  }, [items, category, query]);

  async function moderate(id: number, status: 'approved' | 'rejected') {
    setBusyId(id);
    try {
      await api(`/listings/${id}/moderate`, {
        method: 'POST',
        body: JSON.stringify({ status }),
      });
      setSelected(null);
      await load();
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Модерация</h1>
          <p>Проверка и просмотр объявлений</p>
        </div>
      </div>

      <div className="toolbar">
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="pending">На проверке</option>
          <option value="approved">Одобренные</option>
          <option value="rejected">Отклонённые</option>
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
          placeholder="Поиск…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          style={{ maxWidth: 280 }}
        />
      </div>

      {error && <p className="error">{error}</p>}

      <div className="list">
        {visible.map((item) => (
          <article key={item.id} className="row-card" onClick={() => setSelected(item)}>
            <div>
              <h3 className="row-title">{item.title}</h3>
              <div className="meta">
                <span className={STATUS_CHIP[item.status] || 'chip'}>{STATUS_LABEL[item.status] || item.status}</span>
                <span className="chip">{CATEGORY_LABELS[item.category] || item.category}</span>
                <span className="chip neutral">{item.settlement_name}</span>
                <span className="chip neutral">{item.author_name}</span>
              </div>
              <p className="row-body">
                {item.description.length > 160 ? `${item.description.slice(0, 160)}…` : item.description}
              </p>
              {item.price != null && <div className="price">{item.price.toLocaleString('ru-RU')} ₽</div>}
            </div>
            <div className="actions" onClick={(e) => e.stopPropagation()}>
              <button className="btn" disabled={busyId === item.id} onClick={() => moderate(item.id, 'approved')}>
                Одобрить
              </button>
              <button className="btn danger" disabled={busyId === item.id} onClick={() => moderate(item.id, 'rejected')}>
                Отклонить
              </button>
              <button className="btn ghost" onClick={() => setSelected(item)}>
                Открыть
              </button>
            </div>
          </article>
        ))}
        {!visible.length && <div className="empty">Пока нет объявлений в этом фильтре</div>}
      </div>

      {selected && (
        <div className="modal-backdrop" onClick={() => setSelected(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="meta">
              <span className={STATUS_CHIP[selected.status] || 'chip'}>{STATUS_LABEL[selected.status]}</span>
              <span className="chip">{CATEGORY_LABELS[selected.category]}</span>
              <span className="chip neutral">{selected.settlement_name}</span>
            </div>
            <h2>{selected.title}</h2>
            {selected.price != null && <div className="price">{selected.price.toLocaleString('ru-RU')} ₽</div>}
            <p className="row-body" style={{ marginTop: 14, whiteSpace: 'pre-wrap' }}>
              {selected.description}
            </p>
            <p className="muted" style={{ marginTop: 14 }}>
              Автор: {selected.author_name || '—'}
            </p>
            <div className="modal-actions">
              <button className="btn" disabled={busyId === selected.id} onClick={() => moderate(selected.id, 'approved')}>
                Одобрить
              </button>
              <button className="btn danger" disabled={busyId === selected.id} onClick={() => moderate(selected.id, 'rejected')}>
                Отклонить
              </button>
              <button className="btn secondary" onClick={() => setSelected(null)}>
                Закрыть
              </button>
            </div>
          </div>
        </div>
      )}
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
      lat: item.lat != null ? String(item.lat) : '',
      lon: item.lon != null ? String(item.lon) : '',
      is_published: item.is_published,
    });
    setError('');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function cancelEdit() {
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
      cancelEdit();
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
    if (editingId === id) cancelEdit();
    await load();
  }

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Справочник</h1>
          <p>Школы, больницы, магазины и другие точки района</p>
        </div>
      </div>

      <form className="panel" onSubmit={saveItem}>
        <h2>{editingId ? 'Редактировать запись' : 'Добавить запись'}</h2>
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
        <div className="actions" style={{ marginTop: 12 }}>
          <button className="btn" type="submit" disabled={busy}>
            {busy ? 'Сохранение…' : editingId ? 'Сохранить изменения' : 'Добавить'}
          </button>
          {editingId && (
            <button className="btn secondary" type="button" onClick={cancelEdit}>
              Отмена
            </button>
          )}
        </div>
      </form>

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
              <div>
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
        {!items.length && <div className="empty">Справочник пуст — добавьте первую запись выше</div>}
      </div>
    </div>
  );
}

function formatDate(value?: string | null) {
  if (!value) return '—';
  try {
    return new Date(value).toLocaleString('ru-RU');
  } catch {
    return value;
  }
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

  async function load() {
    const [u, s] = await Promise.all([api<User[]>('/admin/users'), api<Settlement[]>('/settlements')]);
    setUsers(u);
    setSettlements(s);
  }

  useEffect(() => {
    load().catch(console.error);
  }, []);

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

  const visible = users.filter((u) => {
    if (!query.trim()) return true;
    const q = query.trim().toLowerCase();
    return (
      u.full_name.toLowerCase().includes(q) ||
      u.email.toLowerCase().includes(q) ||
      (u.phone || '').toLowerCase().includes(q) ||
      (u.last_ip || '').toLowerCase().includes(q) ||
      (u.device_brand || '').toLowerCase().includes(q) ||
      (u.device_model || '').toLowerCase().includes(q)
    );
  });

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>Пользователи</h1>
          <p>Редактирование профиля, роли, устройство и IP</p>
        </div>
      </div>

      <div className="toolbar">
        <input
          placeholder="Поиск: имя, email, телефон, IP, устройство…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </div>

      <div className="list">
        {visible.map((u) => (
          <article key={u.id} className="row-card user-row" onClick={() => openEdit(u)}>
            <div>
              <h3 className="row-title">{u.full_name}</h3>
              <div className="meta">
                <span className="chip neutral">{u.email}</span>
                <span className="chip">{ROLE_LABELS[u.role]}</span>
                {!u.is_active && <span className="chip danger">Заблокирован</span>}
                {u.last_ip && <span className="chip neutral">IP {u.last_ip}</span>}
              </div>
              <p className="row-body muted">
                {[u.device_brand, u.device_model].filter(Boolean).join(' ') || 'Устройство не передано'}
                {u.device_os ? ` · ${u.device_os}` : ''}
                {u.last_seen_at ? ` · был(а) ${formatDate(u.last_seen_at)}` : ''}
              </p>
            </div>
            <div className="actions" onClick={(e) => e.stopPropagation()}>
              <button className="btn" type="button" onClick={() => openEdit(u)}>
                Изменить
              </button>
            </div>
          </article>
        ))}
        {!visible.length && <div className="empty">Пользователи не найдены</div>}
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
        <Route path="/moderation" element={<ModerationPage />} />
        <Route path="/directory" element={<DirectoryPage />} />
        {user!.role === 'admin' && <Route path="/users" element={<UsersPage />} />}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Shell>
  );
}
