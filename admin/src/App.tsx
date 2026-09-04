import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { Navigate, NavLink, Route, Routes, Link, useNavigate, useSearchParams } from 'react-router-dom';
import { api, apiDownload, apiText, mediaUrl, setToken } from './api';
import type {
  AdminChatMessage,
  AdminConversation,
  AuditLog,
  BackupList,
  HostMetrics,
  ClientErrorLog,
  BlacklistEntry,
  DirectoryItem,
  DirectoryReport,
  AppUpdateInfo,
  DistrictAlert,
  EventItem,
  LegalDocument,
  Listing,
  ListingReport,
  NewsItem,
  Ride,
  Settlement,
  SiteContact,
  Stats,
  TransportRoute,
  TransportStop,
  User,
  UserReport,
  AppCall,
  VkNewsRun,
  PromoLink,
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

function safeHttpUrl(value?: string | null) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  if (/^(javascript|data|vbscript):/i.test(raw)) return '';
  if (/^https?:\/\//i.test(raw)) return raw;
  if (raw.startsWith('//')) return `https:${raw}`;
  if (raw.includes('.') && !/\s/.test(raw)) return `https://${raw.replace(/^\/+/, '')}`;
  return '';
}

function hoursWaiting(iso: string) {
  const d = parseApiDate(iso);
  if (!d) return 0;
  return Math.max(0, Math.floor((Date.now() - d.getTime()) / 3600000));
}

function asItems<T>(data: T[] | { items?: T[] } | null | undefined): T[] {
  if (!data) return [];
  if (Array.isArray(data)) return data;
  return data.items ?? [];
}

function WaitDots({ text = 'Загружаем' }: { text?: string }) {
  return (
    <span className="wait-line">
      <span className="wait-dots" aria-hidden="true">
        <i />
        <i />
        <i />
      </span>
      {text}
    </span>
  );
}

function WaitRow({ cols }: { cols: number }) {
  return (
    <tr>
      <td colSpan={cols} className="empty">
        <WaitDots />
      </td>
    </tr>
  );
}

function CountValue({ value }: { value: number }) {
  const [shown, setShown] = useState(0);
  const fromRef = useRef(0);

  useEffect(() => {
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduce) {
      setShown(value);
      fromRef.current = value;
      return;
    }
    const from = fromRef.current;
    const to = value;
    const start = performance.now();
    const dur = Math.min(900, 280 + Math.abs(to - from) * 8);
    let raf = 0;
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / dur);
      const eased = 1 - (1 - t) * (1 - t);
      setShown(Math.round(from + (to - from) * eased));
      if (t < 1) raf = requestAnimationFrame(tick);
      else fromRef.current = to;
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value]);

  return <>{shown}</>;
}

function canModerate(role: User['role']) {
  return role === 'admin' || role === 'moderator';
}

function canEditDirectory(role: User['role']) {
  return role === 'admin' || role === 'editor';
}

function canSeeInbox(role: User['role']) {
  return canModerate(role) || canEditDirectory(role);
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

function ListingThumb({ item }: { item: Listing }) {
  const url = mediaUrl(item.images?.[0]?.url);
  if (!url) return <div className="list-thumb is-empty" aria-hidden />;
  return <img className="list-thumb" src={url} alt="" />;
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
  wanted: 'Куплю',
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

const LISTING_CATEGORIES = ['goods', 'wanted', 'services', 'jobs', 'rent', 'free', 'lost_found'];
const LISTING_PAGE_SIZE = 25;

const ROLE_LABELS: Record<User['role'], string> = {
  user: 'Пользователь',
  moderator: 'Модератор',
  editor: 'Редактор',
  admin: 'Админ',
};

const BADGE_LABELS: Record<string, string> = {
  '': 'Без метки',
  new: 'Новичок',
  trusted: 'Надёжный',
  verified: 'Проверенный',
  caution: 'Осторожно',
  feed: 'Для ленты',
};

const STATUS_CHIP: Record<string, string> = {
  pending: 'chip warn',
  approved: 'chip ok',
  rejected: 'chip danger',
  archived: 'chip neutral',
  draft: 'chip',
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
  expired: 'Истёк срок',
  other: 'Другое',
};

const REPORT_REASON_LABEL: Record<string, string> = {
  spam: 'Спам',
  fraud: 'Мошенничество',
  prohibited: 'Запрещённый контент',
  abuse: 'Оскорбления',
  other: 'Другое',
  wrong_phone: 'Неверный телефон',
  wrong_address: 'Неверный адрес',
  closed: 'Закрыто / не работает',
};

const REPORT_STATUS_LABEL: Record<string, string> = {
  open: 'Открыта',
  reviewed: 'Просмотрена',
  dismissed: 'Отклонена',
};

function parseApiDate(value?: string | null): Date | null {
  if (!value) return null;
  let s = value.trim();
  if (!s) return null;
  s = s.replace(' ', 'T');
  if (!/[zZ]|[+-]\d{2}:?\d{2}$/.test(s)) s = `${s}Z`;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

function localDateKey(value?: string | null) {
  const d = parseApiDate(value ?? null);
  if (!d) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function toDatetimeLocal(value?: string | null) {
  const d = parseApiDate(value ?? null);
  if (!d) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromDatetimeLocal(value: string): string {
  return new Date(value).toISOString();
}

function formatDate(value?: string | null) {
  const d = parseApiDate(value ?? null);
  if (!d) return value ? value : '—';
  return d.toLocaleString('ru-RU');
}

const MONTHS_GEN = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

function pad2(n: number) {
  return String(n).padStart(2, '0');
}

function formatEventWhen(startIso?: string | null, endIso?: string | null) {
  const start = parseApiDate(startIso ?? null);
  if (!start) return '—';
  const date = `${start.getDate()} ${MONTHS_GEN[start.getMonth()]}`;
  const t1 = `${pad2(start.getHours())}:${pad2(start.getMinutes())}`;
  const end = parseApiDate(endIso ?? null);
  if (!end) return `${date}, ${t1}`;
  const t2 = `${pad2(end.getHours())}:${pad2(end.getMinutes())}`;
  const same =
    start.getFullYear() === end.getFullYear() &&
    start.getMonth() === end.getMonth() &&
    start.getDate() === end.getDate();
  if (same) return `${date}, ${t1}–${t2}`;
  return `${date}, ${t1} — ${end.getDate()} ${MONTHS_GEN[end.getMonth()]}, ${t2}`;
}

function eventPreview(description: string) {
  let t = description.replace(/\r\n/g, '\n').trim();
  t = t.replace(/^Когда:\s*/i, '').trimStart();
  t = t.replace(/^(?:\d{1,2} [а-яё]+, \d{2}:\d{2}[^\n]*(?:\n|$))+/, '');
  t = t.replace(/^…[^\n]*\n?/, '');
  t = t.replace(/\n?Источник:[\s\S]*$/i, '');
  t = t.replace(/\s+/g, ' ').trim();
  if (!t) return '';
  return t.length > 140 ? `${t.slice(0, 140)}…` : t;
}

function extraSeanceCount(description: string) {
  const matches = description.match(/^\d{1,2} [а-яё]+, \d{2}:\d{2}/gim);
  return matches ? Math.max(0, matches.length - 1) : 0;
}

function Pager({
  page,
  pageCount,
  total,
  onPage,
}: {
  page: number;
  pageCount: number;
  total: number;
  onPage: (p: number) => void;
}) {
  if (total === 0) return null;
  if (pageCount <= 1) {
    return (
      <div className="pager">
        {total} {total === 1 ? 'запись' : total < 5 ? 'записи' : 'записей'}
      </div>
    );
  }
  const windowSize = 7;
  let from = Math.max(1, page - 3);
  let to = Math.min(pageCount, from + windowSize - 1);
  from = Math.max(1, to - windowSize + 1);
  const pages: number[] = [];
  for (let p = from; p <= to; p += 1) pages.push(p);
  return (
    <div className="pager">
      <button type="button" className="btn ghost" disabled={page <= 1} onClick={() => onPage(page - 1)}>
        Назад
      </button>
      <div className="pager-pages">
        {from > 1 && (
          <>
            <button type="button" className="pager-num" onClick={() => onPage(1)}>
              1
            </button>
            {from > 2 && <span className="pager-gap">…</span>}
          </>
        )}
        {pages.map((p) => (
          <button
            key={p}
            type="button"
            className={`pager-num${p === page ? ' is-on' : ''}`}
            onClick={() => onPage(p)}
          >
            {p}
          </button>
        ))}
        {to < pageCount && (
          <>
            {to < pageCount - 1 && <span className="pager-gap">…</span>}
            <button type="button" className="pager-num" onClick={() => onPage(pageCount)}>
              {pageCount}
            </button>
          </>
        )}
      </div>
      <span className="pager-total">
        {page} / {pageCount} · {total}
      </span>
      <button type="button" className="btn ghost" disabled={page >= pageCount} onClick={() => onPage(page + 1)}>
        Вперёд
      </button>
    </div>
  );
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
  const [mode, setMode] = useState<'login' | 'forgot' | 'reset'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [password2, setPassword2] = useState('');
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    try {
      const msg = sessionStorage.getItem('ryadom56.loginMsg');
      if (msg) {
        sessionStorage.removeItem('ryadom56.loginMsg');
        setError(msg);
      }
    } catch {
      /* ignore */
    }
  }, []);

  async function submitLogin(e: React.FormEvent) {
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

  async function sendCode() {
    if (!isValidEmail(email)) {
      setError('Введите корректный email');
      return;
    }
    setBusy(true);
    setError('');
    setInfo('');
    try {
      const res = await api<{ ok: boolean; message: string }>('/auth/forgot-password', {
        method: 'POST',
        body: JSON.stringify({ email: email.trim() }),
      });
      setInfo(res.message || 'Если такой email есть, мы отправили код на почту');
      setMode('reset');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Не удалось отправить код');
    } finally {
      setBusy(false);
    }
  }

  async function submitForgot(e: React.FormEvent) {
    e.preventDefault();
    await sendCode();
  }

  async function submitReset(e: React.FormEvent) {
    e.preventDefault();
    if (!/^\d{6}$/.test(code.trim())) {
      setError('Введите 6-значный код из письма');
      return;
    }
    if (password.length < 6) {
      setError('Пароль не короче 6 символов');
      return;
    }
    if (password !== password2) {
      setError('Пароли не совпадают');
      return;
    }
    setBusy(true);
    setError('');
    try {
      await api('/auth/reset-password', {
        method: 'POST',
        body: JSON.stringify({ email: email.trim(), code: code.trim(), password }),
      });
      setMode('login');
      setPassword('');
      setPassword2('');
      setCode('');
      setInfo('Пароль обновлён. Войдите с новым паролем');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Не удалось сменить пароль');
    } finally {
      setBusy(false);
    }
  }

  const title = mode === 'login' ? 'Панель управления' : 'Восстановление пароля';
  const onSubmit = mode === 'login' ? submitLogin : mode === 'forgot' ? submitForgot : submitReset;

  return (
    <div className="login-wrap">
      <form className="login-card" onSubmit={onSubmit}>
        <p className="brand">Рядом56</p>
        <h1>{title}</h1>
        <p className="login-sub">
          {mode === 'login'
            ? 'Модерация объявлений и справочник района'
            : mode === 'forgot'
              ? 'Отправим 6-значный код на почту'
              : 'Введите код из письма и новый пароль'}
        </p>
        <label>
          Email
          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            type="email"
            required
            disabled={busy || mode === 'reset'}
          />
        </label>
        {mode === 'login' && (
          <label>
            Пароль
            <input value={password} onChange={(e) => setPassword(e.target.value)} type="password" required />
          </label>
        )}
        {mode === 'reset' && (
          <>
            <label>
              Код из письма
              <input
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                inputMode="numeric"
                autoComplete="one-time-code"
                required
              />
            </label>
            <label>
              Новый пароль
              <input value={password} onChange={(e) => setPassword(e.target.value)} type="password" required />
            </label>
            <label>
              Повторите пароль
              <input value={password2} onChange={(e) => setPassword2(e.target.value)} type="password" required />
            </label>
          </>
        )}
        {info && <p className="login-info">{info}</p>}
        {error && <p className="error">{error}</p>}
        <button disabled={busy}>
          {busy
            ? 'Отправка…'
            : mode === 'login'
              ? 'Войти'
              : mode === 'forgot'
                ? 'Отправить код'
                : 'Сохранить пароль'}
        </button>
        {mode === 'login' ? (
          <button
            type="button"
            className="text-link"
            disabled={busy}
            onClick={() => {
              setError('');
              setInfo('');
              setMode('forgot');
            }}
          >
            Забыли пароль?
          </button>
        ) : (
          <button
            type="button"
            className="text-link"
            disabled={busy}
            onClick={() => {
              setError('');
              setInfo('');
              setMode('login');
            }}
          >
            Назад ко входу
          </button>
        )}
        {mode === 'reset' && (
          <button type="button" className="ghost" disabled={busy} onClick={() => void sendCode()}>
            Отправить код ещё раз
          </button>
        )}
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
  const inbox = canSeeInbox(user.role);
  const [toast, setToast] = useState('');
  const [inboxNew, setInboxNew] = useState(0);
  const [errorsNew, setErrorsNew] = useState(0);

  useEffect(() => {
    function onUnauthorized() {
      try {
        sessionStorage.setItem('ryadom56.loginMsg', 'Сессия истекла. Войдите снова');
      } catch {
        /* ignore */
      }
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
    function onErrorsUnread(e: Event) {
      setErrorsNew(Number((e as CustomEvent<number>).detail) || 0);
    }
    window.addEventListener('ryadom56:errors-unread', onErrorsUnread as EventListener);
    return () => window.removeEventListener('ryadom56:errors-unread', onErrorsUnread as EventListener);
  }, []);

  useEffect(() => {
    if (!inbox && !mod) return;
    let lastPending = -1;
    let stopped = false;

    async function tick() {
      try {
        const alerts = await api<{
          pending: number;
          pending_over_24h: number;
          open_reports: number;
          open_contacts?: number;
          unread_client_errors?: number;
        }>('/admin/alerts');
        if (stopped) return;
        setInboxNew(alerts.open_contacts || 0);
        if (mod) setErrorsNew(alerts.unread_client_errors || 0);
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
  }, [inbox, mod]);

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
            <NavLink to="/listings">
              <span className="nav-ico">▣</span> Объявления
            </NavLink>
          )}
          {(mod || directory) && (
            <NavLink to="/reports">
              <span className="nav-ico">!</span> Жалобы
            </NavLink>
          )}
          {inbox && (
            <NavLink to="/inbox">
              <span className="nav-ico">✉</span> С сайта{inboxNew > 0 ? ` (${inboxNew})` : ''}
            </NavLink>
          )}
          <NavLink to="/audit">
            <span className="nav-ico">≡</span> Лог действий
          </NavLink>
          {mod && (
            <NavLink to="/errors">
              <span className="nav-ico">⚠</span> Сбои приложения{errorsNew > 0 ? ` (${errorsNew})` : ''}
            </NavLink>
          )}
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
          {mod && (
            <NavLink to="/rides">
              <span className="nav-ico">→</span> Попутки
            </NavLink>
          )}
          {directory && (
            <NavLink to="/news">
              <span className="nav-ico">✉</span> Новости
            </NavLink>
          )}
          {directory && (
            <NavLink to="/news-vk">
              <span className="nav-ico">↓</span> Новости из ВК
            </NavLink>
          )}
          {directory && (
            <NavLink to="/broadcast">
              <span className="nav-ico">◉</span> На телефоны
            </NavLink>
          )}
          {directory && (
            <NavLink to="/alerts">
              <span className="nav-ico">⚡</span> Срочное
            </NavLink>
          )}
          {canSeeInbox(user.role) && (
            <NavLink to="/promo">
              <span className="nav-ico">↗</span> Реклама
            </NavLink>
          )}
          {mod && (
            <NavLink to="/chats">
              <span className="nav-ico">⇄</span> Чаты
            </NavLink>
          )}
          {mod && (
            <NavLink to="/calls">
              <span className="nav-ico">☎</span> Звонки
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

function formatBytes(n?: number | null) {
  if (n == null || n <= 0) return '—';
  if (n < 1024) return `${n} Б`;
  if (n < 1024 * 1024) return `${Math.round(n / 1024)} КБ`;
  return `${(n / (1024 * 1024)).toFixed(1)} МБ`;
}

function StatCard({
  to,
  tone,
  label,
  value,
}: {
  to?: string;
  tone?: string;
  label: string;
  value: React.ReactNode;
}) {
  const cls = `stat${tone ? ` ${tone}` : ''}`;
  const inner = (
    <>
      <div className="label">{label}</div>
      <div className="value">{typeof value === 'number' ? <CountValue value={value} /> : value}</div>
    </>
  );
  if (to) return <Link className={cls} to={to}>{inner}</Link>;
  return <div className={cls}>{inner}</div>;
}

function fmtPct(n: number) {
  const rounded = Math.round(n * 10) / 10;
  const text = Number.isInteger(rounded) ? String(rounded) : String(rounded).replace('.', ',');
  return `${text}%`;
}

function coresWord(n: number) {
  const n10 = n % 10;
  const n100 = n % 100;
  if (n100 >= 11 && n100 <= 14) return `${n} ядер`;
  if (n10 === 1) return `${n} ядро`;
  if (n10 >= 2 && n10 <= 4) return `${n} ядра`;
  return `${n} ядер`;
}

function formatRam(usedMb: number, totalMb: number) {
  const used = usedMb >= 1024 ? `${(usedMb / 1024).toFixed(1).replace('.', ',')} ГБ` : `${usedMb} МБ`;
  let total: string;
  if (totalMb >= 950) {
    const gb = totalMb / 1024;
    const shown = Math.abs(gb - Math.round(gb)) < 0.08 ? String(Math.round(gb)) : gb.toFixed(1).replace('.', ',');
    total = `${shown} ГБ`;
  } else {
    total = `${totalMb} МБ`;
  }
  return `${used} / ${total}`;
}

function formatDisk(used: number, total: number) {
  const gb = 1024 ** 3;
  const usedGb = used / gb;
  const totalGb = total / gb;
  const usedStr = (usedGb >= 10 ? usedGb.toFixed(0) : usedGb.toFixed(1)).replace('.', ',');
  const totalStr = (totalGb >= 10 ? totalGb.toFixed(0) : totalGb.toFixed(1)).replace('.', ',');
  return `${usedStr} / ${totalStr} ГБ`;
}

function HostMeter({
  label,
  percent,
  detail,
  warn,
}: {
  label: string;
  percent: number;
  detail: string;
  warn: boolean;
}) {
  const width = Math.max(0, Math.min(100, percent));
  return (
    <div className={`host-meter${warn ? ' warn' : ''}`}>
      <div className="label">{label}</div>
      <div className="value">{fmtPct(percent)}</div>
      <div className="detail">{detail}</div>
      <div className="bar" aria-hidden="true">
        <i style={{ width: `${width}%` }} />
      </div>
    </div>
  );
}

function Dashboard({ role }: { role: User['role'] }) {
  const isAdmin = role === 'admin';
  const mod = canModerate(role);
  const directory = canEditDirectory(role);
  const [stats, setStats] = useState<Stats | null>(null);
  const [statsError, setStatsError] = useState('');
  const [backups, setBackups] = useState<BackupList | null>(null);
  const [host, setHost] = useState<HostMetrics | null>(null);
  const [backupBusy, setBackupBusy] = useState(false);
  const [snapshotBusy, setSnapshotBusy] = useState(false);

  function loadStats() {
    setStatsError('');
    api<Stats>('/admin/stats')
      .then(setStats)
      .catch((err) => setStatsError(err instanceof Error ? err.message : 'Не удалось загрузить сводку'));
    if (isAdmin) {
      api<BackupList>('/admin/backups').then(setBackups).catch(console.error);
    }
  }

  useEffect(() => {
    loadStats();
    const tick = window.setInterval(() => {
      api<Stats>('/admin/stats')
        .then(setStats)
        .catch(() => {});
    }, 30000);
    if (!isAdmin) {
      return () => window.clearInterval(tick);
    }
    const loadHost = () => {
      api<HostMetrics>('/admin/host')
        .then(setHost)
        .catch(() => {});
    };
    loadHost();
    const hostTick = window.setInterval(loadHost, 4000);
    return () => {
      window.clearInterval(tick);
      window.clearInterval(hostTick);
    };
  }, [isAdmin]);

  async function downloadLive() {
    if (backupBusy) return;
    setBackupBusy(true);
    try {
      await apiDownload('/admin/backup', 'ryadom56-backup.db');
      pushToast('Живая база скачана');
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Ошибка скачивания');
    } finally {
      setBackupBusy(false);
    }
  }

  async function makeSnapshot() {
    if (snapshotBusy) return;
    setSnapshotBusy(true);
    try {
      setBackups(await api<BackupList>('/admin/backups', { method: 'POST' }));
      pushToast('Копия создана');
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Ошибка копии');
    } finally {
      setSnapshotBusy(false);
    }
  }

  async function downloadSnapshot(name: string) {
    try {
      await apiDownload(`/admin/backups/${encodeURIComponent(name)}`, name);
      pushToast('Копия скачана');
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Ошибка скачивания');
    }
  }

  if (!stats) {
    return (
      <div className="page-head">
        <div>
          <h1>Сводка</h1>
          <p>{statsError || <WaitDots text="Загружаем сводку" />}</p>
          {statsError ? (
            <button className="btn" type="button" onClick={() => loadStats()}>
              Повторить
            </button>
          ) : null}
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
          <p>
            Состояние сервиса Рядом56 прямо сейчас. Карточка открывает раздел. Онлайн обновляется каждые 30 секунд
            {isAdmin ? ', нагрузка сервера — каждые 4 секунды' : ''}.
          </p>
        </div>
      </div>
      {isAdmin && (
        <>
          <h2 className="dash-kicker">Сервер</h2>
          {host ? (
            <div className="host-meters">
              <HostMeter
                label="Процессор"
                percent={host.cpu_percent}
                detail={coresWord(host.cpu_count)}
                warn={host.cpu_warn}
              />
              <HostMeter
                label="Память"
                percent={host.ram_percent}
                detail={formatRam(host.ram_used_mb, host.ram_total_mb)}
                warn={host.ram_warn}
              />
              <HostMeter
                label="Диск"
                percent={host.disk_percent}
                detail={formatDisk(host.disk_used_bytes, host.disk_total_bytes)}
                warn={host.disk_warn}
              />
            </div>
          ) : (
            <p className="muted">
              <WaitDots text="Смотрим нагрузку сервера" />
            </p>
          )}
        </>
      )}
      <h2 className="dash-kicker">Сейчас онлайн</h2>
      <div className="cards">
        <StatCard tone="brand" label="На сайте" value={stats.online_site ?? 0} />
        <StatCard tone="ok" label="В приложении" value={stats.online_app ?? 0} />
        <StatCard label="Приложение, без входа" value={stats.online_app_guests ?? 0} />
        <StatCard to="/users" label="Приложение, вошли" value={stats.online_app_users ?? 0} />
        <StatCard label="На звонке" value={stats.online_calls ?? 0} />
      </div>
      <h2 className="dash-kicker">Люди</h2>
      <div className="cards">
        {isAdmin && <StatCard to="/users" label="Всего аккаунтов" value={stats.users} />}
        {isAdmin && <StatCard tone="ok" label="Новые сегодня" value={stats.users_new_today ?? 0} />}
        {isAdmin && <StatCard tone="ok" label="Новые за 7 дней" value={stats.users_new_7d ?? 0} />}
        {isAdmin && <StatCard label="Раньше 7 дней" value={stats.users_older ?? 0} />}
        {isAdmin && <StatCard label="Заходили за 30 дней" value={stats.users_active_30d ?? 0} />}
        <StatCard tone="brand" label="Сайт сегодня" value={stats.site_today ?? 0} />
        <StatCard label="Гости приложения сегодня" value={stats.app_guests_today ?? 0} />
        {isAdmin && (
          <StatCard tone="brand" label="Скачали приложение" value={stats.apk_downloads_total ?? 0} />
        )}
        {isAdmin && (
          <StatCard tone="ok" label="Скачали, уникальных" value={stats.apk_downloads_unique ?? 0} />
        )}
        {isAdmin && (
          <StatCard label="Скачали сегодня" value={stats.apk_downloads_today ?? 0} />
        )}
        <StatCard to="/promo" tone="brand" label="С рекламы, зашли" value={stats.promo_visits_today ?? 0} />
        <StatCard to="/promo" tone="ok" label="С рекламы, скачали" value={stats.promo_downloads_today ?? 0} />
      </div>
      <h2 className="dash-kicker">Сервис</h2>
      <div className="cards">
        <StatCard
          to="/inbox"
          tone={(stats.open_contacts || 0) > 0 ? 'warn' : ''}
          label="С сайта, новые"
          value={stats.open_contacts ?? 0}
        />
        {mod && (
          <StatCard to="/moderation" tone="warn" label="На модерации" value={stats.listings_pending} />
        )}
        {mod && (
          <StatCard
            to="/moderation?over24=1"
            tone="warn"
            label="Старше 24 ч"
            value={stats.pending_over_24h ?? 0}
          />
        )}
        <StatCard to="/reports" tone="warn" label="Открытые жалобы" value={stats.open_reports ?? 0} />
        {mod && (
          <StatCard to="/listings?status=approved" tone="ok" label="Опубликовано" value={stats.listings_approved} />
        )}
        {directory && (
          <StatCard to="/directory" tone="brand" label="В справочнике" value={stats.directory_items} />
        )}
        {directory && (
          <StatCard to="/events" tone="brand" label="События (всего)" value={stats.events_total ?? 0} />
        )}
        {directory && (
          <StatCard to="/events?upcoming=1" tone="ok" label="Скоро в афише" value={stats.events_upcoming ?? 0} />
        )}
        {mod && <StatCard to="/rides" label="Попутки сейчас" value={stats.rides_open ?? 0} />}
        {directory && <StatCard to="/transport" label="Маршруты" value={stats.transport_routes ?? 0} />}
        {directory && (
          <StatCard to="/news" tone="brand" label="Новости" value={stats.news_total ?? 0} />
        )}
        {directory && (
          <StatCard to="/alerts" tone="warn" label="Активные срочные" value={stats.active_alerts ?? 0} />
        )}
        <StatCard
          to="/audit"
          label="Одобр. / откл. (30 дн.)"
          value={
            <span style={{ fontSize: 22 }}>
              {stats.moderated_approved_30d ?? 0} / {stats.moderated_rejected_30d ?? 0}
            </span>
          }
        />
        <StatCard
          to="/audit"
          tone="ok"
          label="Конверсия модерации"
          value={<span style={{ fontSize: 26 }}>{conv}</span>}
        />
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
        <div className="panel" style={{ gridColumn: '1 / -1' }}>
          <h2>По посёлкам, сёлам и городам: объявления / открытия справочника</h2>
          <p className="muted" style={{ marginTop: 0 }}>
            <Link to="/reports?tab=directory">Жалобы на контакты справочника (открытые): {stats.open_directory_reports ?? 0}</Link>
          </p>
          <ul className="cat-list">
            {(stats.by_settlement || []).slice(0, 40).map((s) => (
              <li key={s.settlement_id ?? 'none'}>
                <span>{s.settlement_name}</span>
                <strong>
                  {s.listings_count} объяв. / {s.directory_opens} откр.
                </strong>
              </li>
            ))}
            {!stats.by_settlement?.length && <li className="muted">Пока нет данных по местам</li>}
          </ul>
        </div>
        {isAdmin && (
          <div className="panel" style={{ gridColumn: '1 / -1' }}>
            <h2>Копии базы</h2>
            <p className="muted" style={{ marginTop: 0 }}>
              Раз в сутки ночью, последние 7 файлов.
              {backups
                ? ` Диск свободно ${backups.disk_free_mb ?? '—'} из ${backups.disk_total_mb ?? '—'} МБ · данные ${backups.data_dir_mb ?? '—'} МБ.`
                : ''}
            </p>
            <div className="toolbar compact">
              <button className="btn" type="button" disabled={snapshotBusy} onClick={() => makeSnapshot()}>
                {snapshotBusy ? 'Копирование…' : 'Сделать копию сейчас'}
              </button>
              <button className="btn secondary" type="button" disabled={backupBusy} onClick={() => downloadLive()}>
                {backupBusy ? 'Скачивание…' : 'Скачать живую базу'}
              </button>
            </div>
            <div className="table-wrap">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Файл</th>
                    <th>Когда</th>
                    <th>Размер</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {(backups?.items || []).map((row) => (
                    <tr key={row.name}>
                      <td className="audit-who">{row.name}</td>
                      <td className="audit-when">{formatAuditWhen(row.created_at)}</td>
                      <td className="audit-obj">{formatBytes(row.size)}</td>
                      <td>
                        <div className="actions inline">
                          <button className="btn" type="button" onClick={() => downloadSnapshot(row.name)}>
                            Скачать
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                  {!backups?.items?.length && (
                    <tr>
                      <td colSpan={4} className="empty">
                        Копий пока нет — нажмите «Сделать копию сейчас»
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function ModerationPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const listingIdParam = searchParams.get('listingId');
  const authorIdParam = searchParams.get('authorId');
  const qParam = searchParams.get('q');
  const statusParam = searchParams.get('status');
  const over24Param = searchParams.get('over24') === '1';
  const [items, setItems] = useState<Listing[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [filter, setFilter] = useState(() => {
    if (listingIdParam || authorIdParam) return '';
    if (statusParam === 'closed') return 'archived';
    if (statusParam != null && statusParam !== '') return statusParam;
    return 'pending';
  });
  const [closedOnly, setClosedOnly] = useState(() => statusParam === 'closed');
  const [over24Only, setOver24Only] = useState(over24Param);
  const [category, setCategory] = useState('');
  const [query, setQuery] = useState('');
  const [serverQuery, setServerQuery] = useState(() => qParam || '');
  const [autoFlaggedOnly, setAutoFlaggedOnly] = useState(false);
  const [authorKind, setAuthorKind] = useState<'all' | 'feed' | 'real'>('all');
  const [settlementId, setSettlementId] = useState<number | ''>('');
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<number | null>(null);
  const [selected, setSelected] = useState<Listing | null>(null);
  const [checked, setChecked] = useState<number[]>([]);
  const [page, setPage] = useState(1);
  const [bulkBusy, setBulkBusy] = useState(false);
  const [bulkRejectNote, setBulkRejectNote] = useState('');
  const [moderationNote, setModerationNote] = useState('');
  const [listTotal, setListTotal] = useState(0);
  const [listLoading, setListLoading] = useState(true);
  const [focusId, setFocusId] = useState<number | null>(null);
  const [wantNoteFocus, setWantNoteFocus] = useState(false);
  const noteRef = useRef<HTMLTextAreaElement | null>(null);

  function patchModerationUrl(next: { status?: string | null; over24?: boolean; authorId?: string | null }) {
    const p = new URLSearchParams(searchParams);
    if (next.status !== undefined) {
      if (next.status) p.set('status', next.status);
      else p.delete('status');
    }
    if (next.over24 !== undefined) {
      if (next.over24) p.set('over24', '1');
      else p.delete('over24');
    }
    if (next.authorId !== undefined) {
      if (next.authorId) p.set('authorId', next.authorId);
      else p.delete('authorId');
    }
    setSearchParams(p, { replace: true });
  }

  function closeModal() {
    if (busyId != null) return;
    setSelected(null);
    setModerationNote('');
  }

  async function load() {
    setListLoading(true);
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
      if (over24Only) params.set('over24', '1');
      if (authorKind === 'feed' || authorKind === 'real') params.set('author_kind', authorKind);
      if (filter === 'pending' || !filter) params.set('sort', 'sla');
      const qs = params.toString();
      const data = await api<Listing[] | { items: Listing[]; total?: number }>(`/listings/admin/all${qs ? `?${qs}` : ''}`);
      const rows = asItems(data);
      setItems(rows);
      setListTotal(!Array.isArray(data) && data?.total != null ? data.total : rows.length);
      setChecked([]);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setListLoading(false);
    }
  }

  useEffect(() => {
    api<Settlement[]>('/settlements').then(setSettlements).catch(console.error);
  }, []);

  useEffect(() => {
    if (qParam != null) setServerQuery(qParam);
  }, [qParam]);

  useEffect(() => {
    if (listingIdParam || authorIdParam) {
      setFilter('');
      setClosedOnly(false);
      return;
    }
    if (statusParam === 'closed') {
      setClosedOnly(true);
      setFilter('archived');
      return;
    }
    if (statusParam != null && statusParam !== '') {
      setClosedOnly(false);
      setFilter(statusParam);
    }
  }, [statusParam, listingIdParam, authorIdParam]);

  useEffect(() => {
    setOver24Only(over24Param);
  }, [over24Param]);

  useEffect(() => {
    load();
  }, [filter, closedOnly, serverQuery, autoFlaggedOnly, settlementId, authorIdParam, over24Only, authorKind]);

  async function togglePin(item: Listing) {
    setBusyId(item.id);
    try {
      await api(`/listings/${item.id}/pin`, {
        method: 'POST',
        body: JSON.stringify({ pinned: !item.is_pinned }),
      });
      await load();
      if (selected?.id === item.id) {
        const next = await api<Listing[] | { items: Listing[] }>(`/listings/admin/all?status=approved`);
        const found = asItems(next).find((x) => x.id === item.id);
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

  const MOD_PAGE = 25;
  const pageCount = Math.max(1, Math.ceil(visible.length / MOD_PAGE));
  const safePage = Math.min(page, pageCount);
  const pageItems = visible.slice((safePage - 1) * MOD_PAGE, safePage * MOD_PAGE);

  useEffect(() => {
    setPage(1);
  }, [filter, closedOnly, serverQuery, autoFlaggedOnly, settlementId, category, query, authorIdParam, over24Only, authorKind]);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

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
      const pendingNow = pageItems.filter((x) => needsModeration(x));
      const idx = pendingNow.findIndex((x) => x.id === id);
      const next = pendingNow[idx + 1] || pendingNow[idx - 1] || null;
      setFocusId(next?.id ?? null);
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
  const pagePendingIds = pageItems.filter(needsModeration).map((x) => x.id);
  const allPendingIds = visible.filter(needsModeration).map((x) => x.id);
  const pageAllChecked = pagePendingIds.length > 0 && pagePendingIds.every((id) => checked.includes(id));
  const pageSomeChecked = pagePendingIds.some((id) => checked.includes(id));
  const headerCheckRef = useRef<HTMLInputElement | null>(null);
  const over24 = items.filter((i) => needsModeration(i) && hoursWaiting(i.created_at) >= 24).length;

  useEffect(() => {
    if (headerCheckRef.current) {
      headerCheckRef.current.indeterminate = pageSomeChecked && !pageAllChecked;
    }
  }, [pageSomeChecked, pageAllChecked]);

  function togglePageAll() {
    setChecked((prev) => {
      if (pageAllChecked) return prev.filter((id) => !pagePendingIds.includes(id));
      return [...new Set([...prev, ...pagePendingIds])];
    });
  }

  useEffect(() => {
    const pending = pageItems.filter(needsModeration);
    if (!pending.length) return;
    if (focusId != null && pending.some((x) => x.id === focusId)) return;
    setFocusId(pending[0].id);
  }, [pageItems, focusId]);

  useEffect(() => {
    if (focusId == null) return;
    document.querySelector('.moderation-page tr.is-focus')?.scrollIntoView({ block: 'nearest' });
  }, [focusId]);

  useEffect(() => {
    if (!wantNoteFocus) return;
    noteRef.current?.focus();
    setWantNoteFocus(false);
  }, [selected, wantNoteFocus]);

  useEffect(() => {
    function typingInField(el: EventTarget | null) {
      const node = el as HTMLElement | null;
      const tag = node?.tagName?.toLowerCase();
      return tag === 'input' || tag === 'textarea' || tag === 'select' || Boolean(node?.isContentEditable);
    }
    function onKey(e: KeyboardEvent) {
      if (typingInField(e.target)) return;
      const pending = pageItems.filter(needsModeration);
      const focused = pending.find((x) => x.id === focusId) || pending[0];
      const target = selected && needsModeration(selected) ? selected : focused;
      if (e.key === 'Escape' && selected) {
        e.preventDefault();
        closeModal();
        return;
      }
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        if (!pending.length) return;
        e.preventDefault();
        const idx = Math.max(0, pending.findIndex((x) => x.id === (focusId ?? pending[0].id)));
        const next = pending[Math.min(pending.length - 1, Math.max(0, idx + (e.key === 'ArrowDown' ? 1 : -1)))];
        setFocusId(next.id);
        if (selected) openListing(next);
        return;
      }
      if (e.key === 'Enter' && focused && !selected) {
        e.preventDefault();
        openListing(focused);
        return;
      }
      if (!target || busyId != null) return;
      if (e.key === 'a' || e.key === 'A' || e.key === 'ф' || e.key === 'Ф') {
        if (!needsModeration(target)) return;
        e.preventDefault();
        void moderate(target.id, 'approved');
      }
      if (e.key === 'r' || e.key === 'R' || e.key === 'к' || e.key === 'К') {
        if (!needsModeration(target)) return;
        e.preventDefault();
        if (!selected || selected.id !== target.id) {
          openListing(target);
          setWantNoteFocus(true);
          return;
        }
        if (!moderationNote.trim()) {
          setError('Укажите причину отклонения');
          pushToast('Укажите причину — шаблон или свой текст');
          noteRef.current?.focus();
          return;
        }
        void moderate(target.id, 'rejected');
      }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [selected, busyId, moderationNote, focusId, pageItems]);

  return (
    <div className="moderation-page">
      <div className="page-head compact">
        <div>
          <h1>Модерация</h1>
          <p>
            Очередь по SLA (дольше ждут сверху)
            {over24 > 0 ? ` · старше 24 ч: ${over24}` : ''}
            {listTotal > items.length ? ` · показаны ${items.length} из ${listTotal}` : ''}
            {' · '}
            <Link to="/listings">все объявления</Link>
            {' · '}
            <span className="muted">↑↓ выбрать · A одобрить · R отклонить</span>
          </p>
        </div>
      </div>

      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setServerQuery(query);
        }}
      >
        <select
          value={closedOnly ? 'closed' : filter}
          onChange={(e) => {
            const value = e.target.value;
            if (value === 'closed') {
              setClosedOnly(true);
              setFilter('archived');
              patchModerationUrl({ status: 'closed' });
            } else {
              setClosedOnly(false);
              setFilter(value);
              patchModerationUrl({ status: value || null });
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
          placeholder="Название, автор, телефон…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <select
          value={settlementId === '' ? '' : String(settlementId)}
          onChange={(e) => setSettlementId(e.target.value ? Number(e.target.value) : '')}
        >
          <option value="">Все посёлки, сёла и города</option>
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
          Автофлаг
        </label>
        <label className="check-inline">
          <input
            type="checkbox"
            checked={over24Only}
            onChange={(e) => {
              setOver24Only(e.target.checked);
              patchModerationUrl({ over24: e.target.checked });
            }}
          />
          Старше 24 ч
        </label>
        <select
          value={authorKind}
          onChange={(e) => setAuthorKind(e.target.value as 'all' | 'feed' | 'real')}
        >
          <option value="all">Все объявления</option>
          <option value="feed">Фейковые (для ленты)</option>
          <option value="real">Живые</option>
        </select>
        {authorIdParam ? (
          <button
            type="button"
            className="chip warn"
            onClick={() => patchModerationUrl({ authorId: null })}
          >
            Автор #{authorIdParam} ×
          </button>
        ) : null}
        <button className="btn" type="submit">
          Найти
        </button>
        {allPendingIds.length > 0 && (
          <button
            className="btn"
            type="button"
            onClick={() =>
              setChecked(pendingChecked.length === allPendingIds.length ? [] : allPendingIds)
            }
          >
            {pendingChecked.length === allPendingIds.length
              ? 'Снять выбор'
              : `Выбрать все (${allPendingIds.length})`}
          </button>
        )}
      </form>

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

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th className="check">
                {pagePendingIds.length > 0 ? (
                  <input
                    ref={headerCheckRef}
                    type="checkbox"
                    checked={pageAllChecked}
                    onChange={togglePageAll}
                    title="Выбрать все на странице"
                    aria-label="Выбрать все на странице"
                  />
                ) : null}
              </th>
              <th>Объявление</th>
              <th>Категория</th>
              <th>Автор / место</th>
              <th>Ожидание</th>
              <th>Статус</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {pageItems.map((item) => {
              const pending = needsModeration(item);
              const waitH = hoursWaiting(item.created_at);
              return (
                <tr
                  key={item.id}
                  className={`dir-row${checked.includes(item.id) ? ' is-checked' : ''}${item.id === focusId ? ' is-focus' : ''}${selected?.id === item.id ? ' is-open' : ''}`}
                  onClick={() => openListing(item)}
                >
                  <td className="check" onClick={(e) => e.stopPropagation()}>
                    {pending ? (
                      <input
                        type="checkbox"
                        checked={checked.includes(item.id)}
                        onChange={() => toggleCheck(item.id)}
                        aria-label={`Выбрать ${item.title}`}
                      />
                    ) : null}
                  </td>
                  <td>
                    <div className="listing-cell">
                      <ListingThumb item={item} />
                      <div>
                        <div className="audit-who">{item.title}</div>
                        <div className="audit-sub">
                          {item.price != null ? `${item.price.toLocaleString('ru-RU')} ₽` : 'без цены'}
                          {item.is_urgent ? ' · срочно' : ''}
                          {item.auto_flagged ? ' · автофлаг' : ''}
                          {item.is_pinned ? ' · закреплено' : ''}
                          {item.previous_snapshot ? ' · правка' : ''}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td className="cell-plain">{CATEGORY_LABELS[item.category] || item.category}</td>
                  <td>
                    <div className="author-cell">
                      <span className="audit-who">{item.author_name || '—'}</span>
                      {item.author_badge === 'feed' ? <span className="tag-feed">лента</span> : null}
                    </div>
                    <div className="audit-sub">
                      {item.settlement_name || 'без села'}
                      {item.contact_phone ? ` · ${item.contact_phone}` : ''}
                    </div>
                  </td>
                  <td className="audit-when">
                    {pending ? (
                      <span className={waitH >= 24 ? 'wait-h late' : 'wait-h'}>{waitH} ч</span>
                    ) : (
                      <span className="audit-sub">{formatAuditWhen(item.created_at)}</span>
                    )}
                  </td>
                  <td>
                    <span className={`status-text is-${item.status}`}>{STATUS_LABEL[item.status] || item.status}</span>
                    {item.close_reason ? (
                      <div className="audit-sub">{CLOSE_REASON_LABEL[item.close_reason] || item.close_reason}</div>
                    ) : null}
                  </td>
                  <td className="acts" onClick={(e) => e.stopPropagation()}>
                    {pending ? (
                      <>
                        <button className="row-act ok" type="button" disabled={busyId === item.id} onClick={() => moderate(item.id, 'approved')}>
                          Одобрить
                        </button>
                        <button className="row-act bad" type="button" disabled={busyId === item.id} onClick={() => openListing(item)}>
                          Отклонить
                        </button>
                      </>
                    ) : null}
                    {item.status === 'approved' ? (
                      <button className="row-act" type="button" disabled={busyId === item.id} onClick={() => togglePin(item)}>
                        {item.is_pinned ? 'Открепить' : 'Закрепить'}
                      </button>
                    ) : null}
                  </td>
                </tr>
              );
            })}
            {listLoading && !pageItems.length && <WaitRow cols={7} />}
            {!listLoading && !visible.length && (
              <tr>
                <td colSpan={7} className="empty">
                  Пока нет объявлений в этом фильтре
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={visible.length} onPage={setPage} />

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
              Автор: {selected.author_name || '—'}
              {selected.author_badge === 'feed' ? ' · для ленты' : ''} · Тел: {selected.contact_phone || '—'} · ждёт{' '}
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
                  ref={noteRef}
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

function ListingsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const idParam = searchParams.get('id');
  const authorIdParam = searchParams.get('authorId');
  const statusParam = searchParams.get('status');
  const qParam = searchParams.get('q');
  const openedFromUrl = useRef<string | null>(null);

  const [items, setItems] = useState<Listing[]>([]);
  const [total, setTotal] = useState(0);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [filter, setFilter] = useState(() => {
    if (statusParam && statusParam !== 'all') return statusParam;
    return '';
  });
  const [category, setCategory] = useState('');
  const [settlementId, setSettlementId] = useState<number | ''>('');
  const [authorKind, setAuthorKind] = useState<'all' | 'feed' | 'real'>('all');
  const [query, setQuery] = useState(qParam || '');
  const [appliedQ, setAppliedQ] = useState(qParam || '');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [listLoading, setListLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Listing | null>(null);
  const [form, setForm] = useState({
    title: '',
    description: '',
    category: 'goods',
    settlement_id: '' as number | '',
    price: '',
    contact_phone: '',
    is_urgent: false,
    lifetime_days: 30,
  });
  const [statusNote, setStatusNote] = useState('');

  const pageCount = Math.max(1, Math.ceil(total / LISTING_PAGE_SIZE));
  const safePage = Math.min(page, pageCount);

  function patchUrl(next: { status?: string | null; authorId?: string | null; id?: string | null }) {
    const p = new URLSearchParams(searchParams);
    if (next.status !== undefined) {
      if (next.status) p.set('status', next.status);
      else p.delete('status');
    }
    if (next.authorId !== undefined) {
      if (next.authorId) p.set('authorId', next.authorId);
      else p.delete('authorId');
    }
    if (next.id !== undefined) {
      if (next.id) p.set('id', next.id);
      else p.delete('id');
    }
    setSearchParams(p, { replace: true });
  }

  async function load(nextPage = safePage) {
    const params = new URLSearchParams();
    params.set('limit', String(LISTING_PAGE_SIZE));
    params.set('offset', String((nextPage - 1) * LISTING_PAGE_SIZE));
    if (filter) params.set('status', filter);
    if (appliedQ.trim()) params.set('q', appliedQ.trim());
    if (category) params.set('category', category);
    if (settlementId !== '') params.set('settlement_id', String(settlementId));
    if (authorIdParam) params.set('author_id', authorIdParam);
    if (authorKind === 'feed' || authorKind === 'real') params.set('author_kind', authorKind);
    setListLoading(true);
    try {
      const data = await api<{ items: Listing[]; total?: number } | Listing[]>(`/listings/admin/all?${params}`);
      const rows = asItems(data);
      setItems(rows);
      setTotal(!Array.isArray(data) && data?.total != null ? data.total : rows.length);
    } finally {
      setListLoading(false);
    }
  }

  useEffect(() => {
    api<Settlement[]>('/settlements').then(setSettlements).catch(console.error);
  }, []);

  useEffect(() => {
    if (statusParam && statusParam !== 'all') setFilter(statusParam);
    else if (statusParam === 'all' || statusParam === '') setFilter('');
  }, [statusParam]);

  useEffect(() => {
    load(safePage).catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [safePage, filter, appliedQ, category, settlementId, authorIdParam, authorKind]);

  useEffect(() => {
    setPage(1);
  }, [filter, appliedQ, category, settlementId, authorIdParam, authorKind]);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

  function fillForm(item: Listing) {
    setForm({
      title: item.title,
      description: item.description,
      category: item.category || 'goods',
      settlement_id: item.settlement_id ?? '',
      price: item.price != null ? String(item.price) : '',
      contact_phone: item.contact_phone || '',
      is_urgent: Boolean(item.is_urgent),
      lifetime_days: item.lifetime_days === 60 ? 60 : 30,
    });
    setStatusNote(item.moderation_note || '');
  }

  function openItem(item: Listing) {
    setSelected(item);
    fillForm(item);
    setError('');
    patchUrl({ id: String(item.id) });
  }

  function closeModal() {
    if (busy) return;
    setSelected(null);
    setError('');
    openedFromUrl.current = null;
    patchUrl({ id: null });
  }

  useEffect(() => {
    if (!idParam) return;
    if (openedFromUrl.current === idParam) return;
    const id = Number(idParam);
    if (!Number.isFinite(id)) return;
    const local = items.find((x) => x.id === id);
    if (local) {
      openedFromUrl.current = idParam;
      openItem(local);
      return;
    }
    api<Listing>(`/listings/${id}`)
      .then((item) => {
        openedFromUrl.current = idParam;
        openItem(item);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [idParam, items]);

  async function refreshSelected(id: number) {
    const item = await api<Listing>(`/listings/${id}`);
    setSelected(item);
    fillForm(item);
    await load();
    return item;
  }

  async function saveItem(e: React.FormEvent) {
    e.preventDefault();
    if (!selected || busy) return;
    const title = form.title.trim();
    const description = form.description.trim();
    if (title.length < 2 || description.length < 3) {
      setError('Заполните заголовок и описание');
      return;
    }
    if (form.settlement_id === '') {
      setError('Укажите посёлок, село или город');
      return;
    }
    const priceRaw = form.price.trim().replace(',', '.');
    const price = priceRaw === '' ? null : Number(priceRaw);
    if (price != null && (!Number.isFinite(price) || price < 0)) {
      setError('Цена должна быть числом');
      return;
    }
    setBusy(true);
    setError('');
    try {
      await api(`/listings/${selected.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          title,
          description,
          category: form.category,
          settlement_id: Number(form.settlement_id),
          price,
          contact_phone: form.contact_phone.trim() || null,
          is_urgent: form.is_urgent,
          lifetime_days: form.lifetime_days === 60 ? 60 : 30,
        }),
      });
      await refreshSelected(selected.id);
      pushToast('Объявление сохранено');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function setStatus(status: string) {
    if (!selected || busy) return;
    if (status === 'rejected' && !statusNote.trim()) {
      setError('Укажите причину отклонения');
      return;
    }
    const labels: Record<string, string> = {
      approved: 'опубликовать',
      rejected: 'отклонить',
      archived: 'снять',
      pending: 'вернуть на проверку',
      draft: 'сделать черновиком',
    };
    if (!(await confirmAction(`Точно ${labels[status] || 'изменить'} это объявление?`))) return;
    setBusy(true);
    setError('');
    try {
      await api(`/listings/${selected.id}/admin-status`, {
        method: 'POST',
        body: JSON.stringify({
          status,
          moderation_note: statusNote.trim() || null,
          close_reason: status === 'archived' ? 'other' : null,
          close_note: status === 'archived' ? 'Снято модератором' : null,
        }),
      });
      await refreshSelected(selected.id);
      pushToast('Статус обновлён');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function togglePin(item: Listing) {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await api(`/listings/${item.id}/pin`, {
        method: 'POST',
        body: JSON.stringify({ pinned: !item.is_pinned }),
      });
      const next = await refreshSelected(item.id);
      pushToast(next.is_pinned ? 'Закреплено в ленте' : 'Снято с закрепления');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function extendListing(item: Listing) {
    if (busy) return;
    if (!(await confirmAction('Продлить объявление на 30 дней?'))) return;
    setBusy(true);
    setError('');
    try {
      await api(`/listings/${item.id}/extend`, {
        method: 'POST',
        body: JSON.stringify({ days: 30 }),
      });
      await refreshSelected(item.id);
      pushToast('Срок продлён');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function removeListing(id: number) {
    if (busy) return;
    if (!(await confirmAction('Удалить объявление навсегда? Это нельзя отменить.'))) return;
    setBusy(true);
    setError('');
    try {
      await api(`/listings/${id}`, { method: 'DELETE' });
      if (selected?.id === id) {
        setSelected(null);
        openedFromUrl.current = null;
        patchUrl({ id: null });
      }
      await load();
      pushToast('Объявление удалено');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function deletePhoto(imageId: number) {
    if (!selected || busy) return;
    if (!(await confirmAction('Удалить это фото?'))) return;
    setBusy(true);
    setError('');
    try {
      await api(`/listings/${selected.id}/images/${imageId}`, { method: 'DELETE' });
      await refreshSelected(selected.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function uploadPhotos(files: FileList | null) {
    if (!selected || !files?.length || busy) return;
    const fd = new FormData();
    Array.from(files).forEach((f) => fd.append('files', f));
    setBusy(true);
    setError('');
    try {
      await api(`/listings/${selected.id}/images`, { method: 'POST', body: fd });
      await refreshSelected(selected.id);
      pushToast('Фото добавлено');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  const canExtend =
    selected &&
    (selected.status === 'approved' || (selected.status === 'archived' && selected.close_reason === 'expired'));

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Объявления</h1>
          <p>
            Все объявления: править, снять, удалить, сменить статус
            {authorIdParam ? ` · автор #${authorIdParam}` : ''}
            {' · '}
            <Link to="/moderation">очередь модерации</Link>
          </p>
        </div>
      </div>

      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setAppliedQ(query);
        }}
      >
        <select
          value={filter}
          onChange={(e) => {
            const value = e.target.value;
            setFilter(value);
            patchUrl({ status: value || null });
          }}
        >
          <option value="">Все статусы</option>
          <option value="pending">На проверке</option>
          <option value="approved">Опубликованные</option>
          <option value="rejected">Отклонённые</option>
          <option value="archived">Снятые</option>
          <option value="draft">Черновики</option>
        </select>
        <select value={category} onChange={(e) => setCategory(e.target.value)}>
          <option value="">Все категории</option>
          {LISTING_CATEGORIES.map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABELS[c]}
            </option>
          ))}
        </select>
        <input
          placeholder="Название, автор, телефон…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <select
          value={settlementId === '' ? '' : String(settlementId)}
          onChange={(e) => setSettlementId(e.target.value ? Number(e.target.value) : '')}
        >
          <option value="">Все посёлки, сёла и города</option>
          {settlements.map((s) => (
            <option key={s.id} value={s.id}>
              {s.display_name}
            </option>
          ))}
        </select>
        <select
          value={authorKind}
          onChange={(e) => setAuthorKind(e.target.value as 'all' | 'feed' | 'real')}
        >
          <option value="all">Все объявления</option>
          <option value="feed">Фейковые (для ленты)</option>
          <option value="real">Живые</option>
        </select>
        {authorIdParam ? (
          <button type="button" className="chip warn" onClick={() => patchUrl({ authorId: null })}>
            Автор #{authorIdParam} ×
          </button>
        ) : null}
        <button className="btn" type="submit">
          Найти
        </button>
      </form>

      {error && !selected && <p className="error">{error}</p>}

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Объявление</th>
              <th>Категория</th>
              <th>Автор / место</th>
              <th>Статус</th>
              <th>Обновлено</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id} className="dir-row" onClick={() => openItem(item)}>
                <td>
                  <div className="listing-cell">
                    <ListingThumb item={item} />
                    <div>
                      <div className="audit-who">{item.title}</div>
                      <div className="audit-sub">
                        {item.price != null ? `${item.price.toLocaleString('ru-RU')} ₽` : 'без цены'}
                        {item.is_urgent ? ' · срочно' : ''}
                        {item.is_pinned ? ' · закреплено' : ''}
                        {item.auto_flagged ? ' · автофлаг' : ''}
                      </div>
                    </div>
                  </div>
                </td>
                <td>
                  <span className="chip">{CATEGORY_LABELS[item.category] || item.category}</span>
                </td>
                <td className="audit-obj">
                  {item.author_name || '—'}
                  {item.author_badge === 'feed' ? <div className="audit-sub">для ленты</div> : null}
                  <div className="audit-sub">{item.settlement_name || 'без села'}</div>
                  {item.contact_phone ? <div className="audit-sub">{item.contact_phone}</div> : null}
                </td>
                <td>
                  <span className={STATUS_CHIP[item.status] || 'chip'}>{STATUS_LABEL[item.status] || item.status}</span>
                  {item.close_reason ? (
                    <div className="audit-sub">{CLOSE_REASON_LABEL[item.close_reason] || item.close_reason}</div>
                  ) : null}
                </td>
                <td className="audit-when">{formatAuditWhen(item.updated_at || item.created_at)}</td>
                <td onClick={(e) => e.stopPropagation()}>
                  <div className="actions inline">
                    <button className="btn" type="button" onClick={() => openItem(item)}>
                      Изменить
                    </button>
                    <button className="btn danger" type="button" onClick={() => removeListing(item.id)}>
                      Удалить
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {listLoading && !items.length && <WaitRow cols={6} />}
            {!listLoading && !items.length && (
              <tr>
                <td colSpan={6} className="empty">
                  {appliedQ || filter || category || settlementId !== '' || authorIdParam
                    ? 'Ничего не найдено'
                    : 'Объявлений пока нет'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={total} onPage={setPage} />

      {selected && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(760px, 100%)' }}>
            <div className="meta">
              <span className={STATUS_CHIP[selected.status] || 'chip'}>{STATUS_LABEL[selected.status]}</span>
              {selected.is_pinned && <span className="chip warn">Закреплено</span>}
              {selected.auto_flagged && <span className="chip danger">Автофлаг</span>}
              {selected.expires_at && selected.status === 'approved' ? (
                <span className="chip neutral">до {formatDate(selected.expires_at)}</span>
              ) : null}
            </div>
            <h2>Объявление #{selected.id}</h2>
            <p className="muted">
              Автор: {selected.author_name || '—'}
              {selected.author_id ? (
                <>
                  {' · '}
                  <Link to={`/listings?authorId=${selected.author_id}`} onClick={closeModal}>
                    все от автора
                  </Link>
                </>
              ) : null}
              {selected.status === 'pending' ? (
                <>
                  {' · '}
                  <Link to={`/moderation?listingId=${selected.id}`}>в модерацию</Link>
                </>
              ) : null}
            </p>
            {error && <p className="error">{error}</p>}
            <form onSubmit={saveItem}>
              <div className="grid2">
                <label className="field">
                  Заголовок
                  <input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
                </label>
                <label className="field">
                  Категория
                  <select value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
                    {LISTING_CATEGORIES.map((c) => (
                      <option key={c} value={c}>
                        {CATEGORY_LABELS[c]}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  Посёлок, село или город
                  <select
                    required
                    value={form.settlement_id}
                    onChange={(e) => setForm({ ...form, settlement_id: e.target.value ? Number(e.target.value) : '' })}
                  >
                    <option value="">— выберите —</option>
                    {settlements.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.display_name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  Цена, ₽
                  <input
                    value={form.price}
                    onChange={(e) => setForm({ ...form, price: e.target.value })}
                    placeholder="пусто — без цены"
                  />
                </label>
                <label className="field">
                  Телефон
                  <input
                    value={form.contact_phone}
                    onChange={(e) => setForm({ ...form, contact_phone: e.target.value })}
                  />
                </label>
                <label className="field">
                  Срок
                  <select
                    value={form.lifetime_days}
                    onChange={(e) => setForm({ ...form, lifetime_days: Number(e.target.value) })}
                  >
                    <option value={30}>30 дней</option>
                    <option value={60}>60 дней</option>
                  </select>
                </label>
                <label className="field full">
                  Описание
                  <textarea
                    required
                    rows={5}
                    value={form.description}
                    onChange={(e) => setForm({ ...form, description: e.target.value })}
                  />
                </label>
                <label className="check-inline">
                  <input
                    type="checkbox"
                    checked={form.is_urgent}
                    onChange={(e) => setForm({ ...form, is_urgent: e.target.checked })}
                  />
                  Срочно
                </label>
              </div>

              <div style={{ marginTop: 12 }}>
                <div className="muted" style={{ marginBottom: 6 }}>
                  Фото {selected.images?.length || 0}/5
                </div>
                {!!selected.images?.length && <PhotoGallery images={selected.images} />}
                {!!selected.images?.length && (
                  <div className="actions inline" style={{ marginTop: 8 }}>
                    {selected.images.map((img, i) => (
                      <button key={img.id} type="button" className="btn ghost" onClick={() => deletePhoto(img.id)}>
                        Удалить фото {i + 1}
                      </button>
                    ))}
                  </div>
                )}
                {(selected.images?.length || 0) < 5 && (
                  <label className="field" style={{ marginTop: 8 }}>
                    Добавить фото
                    <input
                      type="file"
                      accept="image/jpeg,image/png,image/webp"
                      multiple
                      onChange={(e) => {
                        void uploadPhotos(e.target.files);
                        e.target.value = '';
                      }}
                    />
                  </label>
                )}
              </div>

              <label className="field" style={{ display: 'block', marginTop: 12 }}>
                Причина отклонения / заметка
                <div className="template-row">
                  {REJECTION_TEMPLATES.map((t) => (
                    <button key={t} type="button" className="btn ghost" onClick={() => setStatusNote(t)}>
                      {t}
                    </button>
                  ))}
                </div>
                <textarea
                  rows={2}
                  value={statusNote}
                  onChange={(e) => setStatusNote(e.target.value)}
                  placeholder="Нужна, если отклоняете"
                />
              </label>

              <div className="modal-actions">
                <button className="btn" type="submit" disabled={busy}>
                  Сохранить
                </button>
                {selected.status !== 'approved' && (
                  <button className="btn" type="button" disabled={busy} onClick={() => setStatus('approved')}>
                    Опубликовать
                  </button>
                )}
                {selected.status !== 'pending' && (
                  <button className="btn secondary" type="button" disabled={busy} onClick={() => setStatus('pending')}>
                    На проверку
                  </button>
                )}
                {selected.status !== 'rejected' && (
                  <button className="btn danger" type="button" disabled={busy} onClick={() => setStatus('rejected')}>
                    Отклонить
                  </button>
                )}
                {selected.status !== 'archived' && (
                  <button className="btn secondary" type="button" disabled={busy} onClick={() => setStatus('archived')}>
                    Снять
                  </button>
                )}
                {selected.status === 'approved' && (
                  <button className="btn secondary" type="button" disabled={busy} onClick={() => togglePin(selected)}>
                    {selected.is_pinned ? 'Открепить' : 'Закрепить'}
                  </button>
                )}
                {canExtend && (
                  <button className="btn secondary" type="button" disabled={busy} onClick={() => extendListing(selected)}>
                    +30 дней
                  </button>
                )}
                <button className="btn danger" type="button" disabled={busy} onClick={() => removeListing(selected.id)}>
                  Удалить
                </button>
                <button className="btn secondary" type="button" disabled={busy} onClick={closeModal}>
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

function ReportsPage({ canListings }: { canListings: boolean }) {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const tabParam = searchParams.get('tab');
  const [tab, setTab] = useState<'listings' | 'directory' | 'users'>(() => {
    if (tabParam === 'directory') return 'directory';
    if (tabParam === 'users' && canListings) return 'users';
    return canListings ? 'listings' : 'directory';
  });
  const [items, setItems] = useState<ListingReport[]>([]);
  const [dirItems, setDirItems] = useState<DirectoryReport[]>([]);
  const [userItems, setUserItems] = useState<UserReport[]>([]);
  const [status, setStatus] = useState('open');
  const [error, setError] = useState('');
  const [replyModal, setReplyModal] = useState<{
    kind: 'listing' | 'directory' | 'user';
    report: ListingReport | DirectoryReport | UserReport;
    next: 'reviewed' | 'dismissed';
  } | null>(null);
  const [moderatorReply, setModeratorReply] = useState('');
  const [openListingAfter, setOpenListingAfter] = useState(false);
  const [busy, setBusy] = useState(false);
  const [listLoading, setListLoading] = useState(true);
  const [page, setPage] = useState(1);

  useEffect(() => {
    if (tabParam === 'directory') setTab('directory');
    else if (tabParam === 'users' && canListings) setTab('users');
    else if (tabParam === 'listings' && canListings) setTab('listings');
  }, [tabParam, canListings]);

  async function load() {
    setListLoading(true);
    try {
      const qs = `?status=${encodeURIComponent(status || 'all')}`;
      if (tab === 'listings') {
        if (!canListings) return;
        setItems(await api<ListingReport[]>(`/admin/reports${qs}`));
      } else if (tab === 'users') {
        if (!canListings) return;
        setUserItems(await api<UserReport[]>(`/admin/user-reports${qs}`));
      } else {
        setDirItems(await api<DirectoryReport[]>(`/admin/directory-reports${qs}`));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setListLoading(false);
    }
  }

  useEffect(() => {
    load().catch(console.error);
  }, [status, tab, canListings]);

  function openReplyModal(
    kind: 'listing' | 'directory' | 'user',
    report: ListingReport | DirectoryReport | UserReport,
    next: 'reviewed' | 'dismissed',
  ) {
    setReplyModal({ kind, report, next });
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
    const listingId =
      replyModal.kind === 'listing'
        ? (replyModal.report as ListingReport).listing_id
        : replyModal.kind === 'user'
          ? (replyModal.report as UserReport).listing_id ?? null
          : null;
    const shouldOpen = openListingAfter && listingId != null;
    setBusy(true);
    setError('');
    try {
      const path =
        replyModal.kind === 'listing'
          ? `/admin/reports/${replyModal.report.id}`
          : replyModal.kind === 'user'
            ? `/admin/user-reports/${replyModal.report.id}`
            : `/admin/directory-reports/${replyModal.report.id}`;
      await api(path, {
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
      if (shouldOpen && listingId != null) navigate(`/listings?id=${listingId}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Ошибка';
      setError(msg);
      pushToast(msg);
    } finally {
      setBusy(false);
    }
  }

  function goToListing(listingId: number) {
    navigate(`/listings?id=${listingId}`);
  }

  const titleOf = (r: ListingReport | DirectoryReport | UserReport) => {
    if ('target_id' in r) return r.target_name || `Пользователь #${r.target_id}`;
    if ('listing_id' in r) return r.listing_title || `Объявление #${r.listing_id}`;
    return r.directory_title || `Контакт #${r.directory_id}`;
  };

  const current =
    tab === 'listings' ? items : tab === 'directory' ? dirItems : userItems;
  const REPORT_PAGE = 25;
  const reportPageCount = Math.max(1, Math.ceil(current.length / REPORT_PAGE));
  const reportSafePage = Math.min(page, reportPageCount);
  const reportPageItems = current.slice((reportSafePage - 1) * REPORT_PAGE, reportSafePage * REPORT_PAGE);

  useEffect(() => {
    setPage(1);
  }, [tab, status]);

  function reportKind(r: ListingReport | DirectoryReport | UserReport): 'listing' | 'directory' | 'user' {
    if ('target_id' in r) return 'user';
    if ('listing_id' in r && !('directory_id' in r)) return 'listing';
    return 'directory';
  }

  function reportStatusChip(s: string) {
    if (s === 'open') return 'chip warn';
    if (s === 'reviewed') return 'chip ok';
    return 'chip neutral';
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Жалобы</h1>
          <p>Объявления, люди и неверные контакты справочника</p>
        </div>
      </div>
      <div className="toolbar compact">
        {canListings && (
          <button
            className={tab === 'listings' ? 'btn' : 'btn ghost'}
            type="button"
            onClick={() => {
              setTab('listings');
              const p = new URLSearchParams(searchParams);
              p.set('tab', 'listings');
              setSearchParams(p, { replace: true });
            }}
          >
            Объявления
          </button>
        )}
        <button
          className={tab === 'directory' ? 'btn' : 'btn ghost'}
          type="button"
            onClick={() => {
              setTab('directory');
              const p = new URLSearchParams(searchParams);
              p.set('tab', 'directory');
              setSearchParams(p, { replace: true });
            }}
        >
          Справочник
        </button>
        {canListings && (
          <button
            className={tab === 'users' ? 'btn' : 'btn ghost'}
            type="button"
            onClick={() => {
              setTab('users');
              const p = new URLSearchParams(searchParams);
              p.set('tab', 'users');
              setSearchParams(p, { replace: true });
            }}
          >
            Люди
          </button>
        )}
        <select value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="open">Открытые</option>
          <option value="reviewed">Просмотренные</option>
          <option value="dismissed">Отклонённые</option>
          <option value="">Все</option>
        </select>
      </div>
      {error && !replyModal && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Когда</th>
              <th>На что</th>
              <th>Причина</th>
              <th>Кто пожаловался</th>
              <th>Комментарий</th>
              <th>Статус</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {reportPageItems.map((r) => {
              const kind = reportKind(r);
              const listingId =
                kind === 'listing'
                  ? (r as ListingReport).listing_id
                  : kind === 'user'
                    ? (r as UserReport).listing_id ?? null
                    : null;
              return (
                <tr
                  key={`${kind}-${r.id}`}
                  className="dir-row"
                  onClick={() => {
                    if (listingId) goToListing(listingId);
                  }}
                >
                  <td className="audit-when" title={formatDate(r.created_at)}>
                    {formatAuditWhen(r.created_at)}
                  </td>
                  <td>
                    <div className="audit-who">{titleOf(r)}</div>
                    <div className="audit-sub">
                      {kind === 'listing' ? 'объявление' : kind === 'directory' ? 'справочник' : 'человек'}
                      {kind === 'user' && (r as UserReport).listing_title
                        ? ` · ${(r as UserReport).listing_title}`
                        : ''}
                    </div>
                  </td>
                  <td>
                    <span className="chip warn">{REPORT_REASON_LABEL[r.reason] || r.reason}</span>
                  </td>
                  <td className="audit-obj">{r.reporter_name || '—'}</td>
                  <td className="audit-details">
                    {r.note || '—'}
                    {r.moderator_reply ? <div className="audit-sub">ответ: {r.moderator_reply}</div> : null}
                  </td>
                  <td>
                    <span className={reportStatusChip(r.status)}>{REPORT_STATUS_LABEL[r.status] || r.status}</span>
                  </td>
                  <td onClick={(e) => e.stopPropagation()}>
                    <div className="actions inline">
                      {kind === 'listing' && (
                        <button className="btn ghost" type="button" onClick={() => goToListing((r as ListingReport).listing_id)}>
                          К объявлению
                        </button>
                      )}
                      {kind === 'directory' && (
                        <button className="btn ghost" type="button" onClick={() => navigate('/directory')}>
                          К справочнику
                        </button>
                      )}
                      {kind === 'user' && (
                        <button className="btn ghost" type="button" onClick={() => navigate('/users')}>
                          К людям
                        </button>
                      )}
                      {r.status === 'open' && (
                        <>
                          <button className="btn" type="button" onClick={() => openReplyModal(kind, r, 'reviewed')}>
                            Просмотрено
                          </button>
                          <button className="btn secondary" type="button" onClick={() => openReplyModal(kind, r, 'dismissed')}>
                            Отклонить
                          </button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
            {listLoading && !current.length && <WaitRow cols={7} />}
            {!listLoading && !current.length && (
              <tr>
                <td colSpan={7} className="empty">
                  Жалоб нет
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={reportSafePage} pageCount={reportPageCount} total={current.length} onPage={setPage} />

      {replyModal && (
        <div className="modal-backdrop" onClick={closeReplyModal}>
          <div className="modal modal-compact" onClick={(e) => e.stopPropagation()}>
            <h2>{replyModal.next === 'reviewed' ? 'Просмотреть жалобу' : 'Отклонить жалобу'}</h2>
            <p className="muted" style={{ marginTop: 0 }}>
              {titleOf(replyModal.report)}
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
            {replyModal.kind !== 'directory' && (replyModal.kind === 'listing' || (replyModal.report as UserReport).listing_id) && (
              <label className="check-inline" style={{ marginTop: 12 }}>
                <input
                  type="checkbox"
                  checked={openListingAfter}
                  onChange={(e) => setOpenListingAfter(e.target.checked)}
                />
                Перейти к объявлению после
              </label>
            )}
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

const AUDIT_PAGE_SIZE = 25;

const ENTITY_LABELS: Record<string, string> = {
  listing: 'Объявление',
  event: 'Событие',
  news: 'Новость',
  transport: 'Маршрут',
  ride: 'Попутка',
  user: 'Пользователь',
  broadcast: 'На телефоны',
  alert: 'Срочное',
  legal: 'Юр. документ',
  blacklist: 'Чёрный список',
  chat: 'Чат',
  listing_chat: 'Чат',
  report: 'Жалоба на объявление',
  directory_report: 'Жалоба на место',
  user_report: 'Жалоба на человека',
  app_update: 'Обновление приложения',
  directory: 'Справочник',
};

const ACTION_LABELS: Record<string, string> = {
  'event.create': 'Создал событие',
  'event.update': 'Изменил событие',
  'event.cover': 'Обновил обложку события',
  'event.delete': 'Удалил событие',
  'news.create': 'Создал новость',
  'news.update': 'Изменил новость',
  'news.cover': 'Обновил обложку новости',
  'news.photos': 'Добавил фото к новости',
  'news.photo_delete': 'Удалил фото новости',
  'vk_news.sync': 'Забрал новости из ВК',
  'news.delete': 'Удалил новость',
  'transport.create': 'Добавил маршрут',
  'transport.update': 'Изменил маршрут',
  'transport.delete': 'Удалил маршрут',
  'ride.hide': 'Скрыл попутку',
  'ride.delete': 'Удалил попутку',
  'alert.create': 'Включил срочное',
  'alert.update': 'Изменил срочное',
  'alert.delete': 'Снял срочное',
  'user.create': 'Создал пользователя',
  'user.update': 'Изменил пользователя',
  'user.revoke_sessions': 'Сбросил сессии',
  'user.push': 'Отправил пуш',
  'broadcast.push': 'Отправил всем на телефон',
  'listing.update': 'Изменил объявление',
  'listing.delete': 'Удалил объявление',
  'listing.pin': 'Закрепил объявление',
  'listing.unpin': 'Открепил объявление',
  'listing.status:approved': 'Опубликовал объявление',
  'listing.status:rejected': 'Отклонил объявление',
  'listing.status:archived': 'Снял объявление',
  'listing.status:pending': 'Вернул объявление на проверку',
  'listing.status:draft': 'Сделал черновик объявления',
  'legal.update': 'Обновил юр. текст',
  'blacklist.add': 'Добавил в чёрный список',
  'blacklist.delete': 'Убрал из чёрного списка',
  'chat.message_delete': 'Удалил сообщение чата',
  'chat.thread_delete': 'Удалил переписку',
  'app_update.patch': 'Настроил обновление',
  'app_update.apk_upload': 'Залил APK',
  'promo.create': 'Сделал рекламную ссылку',
  'promo.patch': 'Изменил рекламную ссылку',
  'moderate:approved': 'Одобрил объявление',
  'moderate:rejected': 'Отклонил объявление',
  'moderate:archived': 'Снял объявление',
  'bulk_moderate:approved': 'Массово одобрил',
  'bulk_moderate:rejected': 'Массово отклонил',
  'bulk_moderate:archived': 'Массово снял',
  'report.reviewed': 'Разобрал жалобу на объявление',
  'report.rejected': 'Отклонил жалобу на объявление',
  'directory_report.reviewed': 'Разобрал жалобу на место',
  'directory_report.rejected': 'Отклонил жалобу на место',
  'user_report.reviewed': 'Разобрал жалобу на человека',
  'user_report.rejected': 'Отклонил жалобу на человека',
};

function auditActionLabel(action: string) {
  if (ACTION_LABELS[action]) return ACTION_LABELS[action];
  const [head, tail] = action.split(/:(.+)/);
  if (tail) {
    const verb = ACTION_LABELS[`${head}:${tail}`];
    if (verb) return verb;
  }
  return action.replace(/[._]/g, ' ');
}

function auditActionTone(action: string) {
  if (/delete|rejected|revoke|unpin/.test(action)) return 'danger';
  if (/approved|create|add|pin$|cover|apk/.test(action)) return 'ok';
  if (/moderate|report|push|archived/.test(action)) return 'warn';
  return '';
}

function auditEntityLabel(type: string, id?: number | null) {
  const name = ENTITY_LABELS[type] || type;
  return id != null ? `${name} №${id}` : name;
}

function formatAuditWhen(value?: string | null) {
  const d = parseApiDate(value ?? null);
  if (!d) return '—';
  const now = new Date();
  const sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
  const yday = new Date(now);
  yday.setDate(now.getDate() - 1);
  const isYday =
    d.getFullYear() === yday.getFullYear() && d.getMonth() === yday.getMonth() && d.getDate() === yday.getDate();
  const clock = `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  if (sameDay) return `сегодня ${clock}`;
  if (isYday) return `вчера ${clock}`;
  const months = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
  if (d.getFullYear() === now.getFullYear()) return `${d.getDate()} ${months[d.getMonth()]} ${clock}`;
  return `${pad2(d.getDate())}.${pad2(d.getMonth() + 1)}.${d.getFullYear()} ${clock}`;
}

function AuditPage() {
  const [items, setItems] = useState<AuditLog[]>([]);
  const [total, setTotal] = useState(0);
  const [query, setQuery] = useState('');
  const [appliedQ, setAppliedQ] = useState('');
  const [entity, setEntity] = useState('');
  const [page, setPage] = useState(1);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const pageCount = Math.max(1, Math.ceil(total / AUDIT_PAGE_SIZE));
  const safePage = Math.min(page, pageCount);

  async function load(nextPage = safePage, q = appliedQ, kind = entity) {
    setBusy(true);
    try {
      const params = new URLSearchParams();
      params.set('limit', String(AUDIT_PAGE_SIZE));
      params.set('offset', String((nextPage - 1) * AUDIT_PAGE_SIZE));
      if (q.trim()) params.set('q', q.trim());
      if (kind) params.set('entity_type', kind);
      const data = await api<{ items: AuditLog[]; total: number }>(`/admin/audit-log?${params}`);
      setItems(data.items || []);
      setTotal(data.total || 0);
      setError('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    load(safePage, appliedQ, entity).catch(console.error);
  }, [safePage, appliedQ, entity]);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

  function search(e?: React.FormEvent) {
    e?.preventDefault();
    setPage(1);
    setAppliedQ(query);
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Лог действий</h1>
          <p>Кто что сделал в админке: модерация, правки, удаления</p>
        </div>
      </div>
      <form className="toolbar compact" onSubmit={search}>
        <input
          placeholder="Имя, email, действие, текст…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <select
          value={entity}
          onChange={(e) => {
            setPage(1);
            setEntity(e.target.value);
          }}
        >
          <option value="">Все разделы</option>
          <option value="listing">Объявления</option>
          <option value="user">Пользователи</option>
          <option value="event">Афиша</option>
          <option value="news">Новости</option>
          <option value="transport">Транспорт</option>
          <option value="alert">Срочные</option>
          <option value="broadcast">На телефоны</option>
          <option value="report">Жалобы</option>
          <option value="chat">Чаты</option>
          <option value="legal">Юр. тексты</option>
          <option value="blacklist">Чёрный список</option>
          <option value="app_update">Приложение</option>
        </select>
        <button className="btn" type="submit" disabled={busy}>
          Найти
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Когда</th>
              <th>Кто</th>
              <th>Действие</th>
              <th>Объект</th>
              <th>Подробности</th>
            </tr>
          </thead>
          <tbody>
            {items.map((row) => {
              const tone = auditActionTone(row.action);
              return (
              <tr key={row.id}>
                <td className="audit-when" title={formatDate(row.created_at)}>
                  {formatAuditWhen(row.created_at)}
                </td>
                <td>
                  <div className="audit-who">{row.actor_name || `user #${row.actor_id}`}</div>
                  <div className="audit-sub">
                    {row.actor_role ? ROLE_LABELS[row.actor_role as User['role']] || row.actor_role : ''}
                    {row.actor_role ? ' · ' : ''}№{row.actor_id}
                  </div>
                </td>
                <td>
                  <span className={tone ? `chip ${tone}` : 'chip neutral'}>{auditActionLabel(row.action)}</span>
                </td>
                <td className="audit-obj">{auditEntityLabel(row.entity_type, row.entity_id)}</td>
                <td className="audit-details">{row.details || '—'}</td>
              </tr>
              );
            })}
            {!items.length && (
              <tr>
                <td colSpan={5} className="empty">
                  {appliedQ || entity ? 'Ничего не найдено' : 'Записей пока нет'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={total} onPage={setPage} />
    </div>
  );
}

const ERROR_PAGE_SIZE = 25;

const SCREEN_LABELS: Record<string, string> = {
  flutter: 'Сбой Flutter',
  zone: 'Необработанная ошибка',
};

function errorScreenLabel(screen?: string | null) {
  if (!screen) return '—';
  return SCREEN_LABELS[screen] || screen;
}

function errorDevice(row: ClientErrorLog) {
  const name = [row.device_brand, row.device_model].filter(Boolean).join(' ').trim();
  return { name: name || 'неизвестно', os: row.device_os || '' };
}

function ErrorsPage() {
  const [items, setItems] = useState<ClientErrorLog[]>([]);
  const [total, setTotal] = useState(0);
  const [unreadCount, setUnreadCount] = useState(0);
  const [query, setQuery] = useState('');
  const [appliedQ, setAppliedQ] = useState('');
  const [page, setPage] = useState(1);
  const [openId, setOpenId] = useState<number | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const pageCount = Math.max(1, Math.ceil(total / ERROR_PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const readCount = Math.max(0, total - unreadCount);

  function tellUnread(n: number) {
    window.dispatchEvent(new CustomEvent('ryadom56:errors-unread', { detail: n }));
  }

  async function load(nextPage = safePage, q = appliedQ) {
    setBusy(true);
    try {
      const params = new URLSearchParams();
      params.set('limit', String(ERROR_PAGE_SIZE));
      params.set('offset', String((nextPage - 1) * ERROR_PAGE_SIZE));
      if (q.trim()) params.set('q', q.trim());
      const data = await api<{ items: ClientErrorLog[]; total: number; unread_count?: number }>(
        `/admin/client-errors?${params}`,
      );
      setItems(data.items || []);
      setTotal(data.total || 0);
      const unread = data.unread_count ?? (data.items || []).filter((r) => !r.is_read).length;
      setUnreadCount(unread);
      tellUnread(unread);
      setError('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    load(safePage, appliedQ).catch(console.error);
  }, [safePage, appliedQ]);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

  function search(e?: React.FormEvent) {
    e?.preventDefault();
    setPage(1);
    setOpenId(null);
    setAppliedQ(query);
  }

  async function openRow(row: ClientErrorLog) {
    const open = openId === row.id;
    setOpenId(open ? null : row.id);
    if (open || row.is_read) return;
    setItems((prev) => prev.map((x) => (x.id === row.id ? { ...x, is_read: true } : x)));
    const nextUnread = Math.max(0, unreadCount - 1);
    setUnreadCount(nextUnread);
    tellUnread(nextUnread);
    try {
      await api(`/admin/client-errors/${row.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ is_read: true }),
      });
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Не удалось отметить прочитанным');
      load().catch(console.error);
    }
  }

  async function removeOne(row: ClientErrorLog) {
    if (!(await confirmAction('Удалить этот сбой?'))) return;
    try {
      await api(`/admin/client-errors/${row.id}`, { method: 'DELETE' });
      if (openId === row.id) setOpenId(null);
      pushToast('Сбой удалён');
      await load();
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Не удалось удалить');
    }
  }

  async function markAllRead() {
    if (!unreadCount) return;
    try {
      await api('/admin/client-errors/mark-read', { method: 'POST' });
      pushToast('Все сбои отмечены прочитанными');
      await load();
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Не удалось отметить');
    }
  }

  async function removeRead() {
    if (!readCount) return;
    if (!(await confirmAction(`Удалить прочитанные сбои (${readCount})?`))) return;
    try {
      const data = await api<{ deleted?: number }>('/admin/client-errors?read=true', { method: 'DELETE' });
      pushToast(data.deleted ? `Удалено: ${data.deleted}` : 'Прочитанных нет');
      setPage(1);
      await load(1, appliedQ);
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Не удалось удалить');
    }
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Сбои приложения</h1>
          <p>
            Сначала новые, они с меткой. Нажмите строку — станет прочитанной.
            {unreadCount ? ` Новых: ${unreadCount}.` : ''}
          </p>
        </div>
      </div>
      <form className="toolbar compact" onSubmit={search}>
        <input
          placeholder="Текст, модель, версия, экран, IP…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <button className="btn" type="submit" disabled={busy}>
          Найти
        </button>
        <button className="btn ghost" type="button" disabled={busy || !unreadCount} onClick={markAllRead}>
          Прочитано все
        </button>
        <button className="btn danger" type="button" disabled={busy || !readCount} onClick={removeRead}>
          Удалить прочитанные
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Когда</th>
              <th>Ошибка</th>
              <th>Где</th>
              <th>Телефон</th>
              <th>Версия</th>
              <th>Кто</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {items.map((row) => {
              const device = errorDevice(row);
              const open = openId === row.id;
              const unread = !row.is_read;
              return (
                <Fragment key={row.id}>
                  <tr
                    className={`error-row${open ? ' is-open' : ''}${unread ? ' unread' : ' is-read'}`}
                    onClick={() => openRow(row)}
                  >
                    <td className="audit-when" title={formatDate(row.created_at)}>
                      {formatAuditWhen(row.created_at)}
                    </td>
                    <td className="error-msg" title={row.message}>
                      {unread ? <span className="chip warn">новая</span> : null} {row.message}
                      {row.stack ? <div className="audit-sub">{open ? 'скрыть стек' : 'есть стек'}</div> : null}
                    </td>
                    <td>{errorScreenLabel(row.screen)}</td>
                    <td>
                      <div className="audit-who">{device.name}</div>
                      {device.os ? <div className="audit-sub">{device.os}</div> : null}
                    </td>
                    <td className="audit-obj">{row.app_version || '—'}</td>
                    <td>
                      <div className="audit-who">
                        {row.user_name || (row.user_id ? `user #${row.user_id}` : 'гость')}
                      </div>
                      <div className="audit-sub">
                        {row.user_id ? `№${row.user_id}` : ''}
                        {row.user_id && row.client_ip ? ' · ' : ''}
                        {row.client_ip || ''}
                      </div>
                    </td>
                    <td className="actions inline">
                      <button
                        className="btn danger"
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          removeOne(row);
                        }}
                      >
                        Удалить
                      </button>
                    </td>
                  </tr>
                  {open && (
                    <tr className="stack-row">
                      <td colSpan={7}>
                        <pre className="stack-pre">{row.stack || 'Стека нет'}</pre>
                      </td>
                    </tr>
                  )}
                </Fragment>
              );
            })}
            {!items.length && (
              <tr>
                <td colSpan={7} className="empty">
                  {appliedQ ? 'Ничего не найдено' : 'Сбоев пока нет'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={total} onPage={setPage} />
    </div>
  );
}

const CALL_STATUS_LABEL: Record<string, string> = {
  ringing: 'гудки',
  active: 'идёт',
  ended: 'завершён',
  missed: 'пропущен',
  declined: 'сброшен',
  cancelled: 'отменён',
  failed: 'сбой',
  busy: 'занято',
};

function formatDuration(sec: number) {
  const n = Math.max(0, Math.floor(sec || 0));
  const m = Math.floor(n / 60);
  const s = n % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function CallsPage() {
  const [items, setItems] = useState<AppCall[]>([]);
  const [total, setTotal] = useState(0);
  const [query, setQuery] = useState('');
  const [appliedQ, setAppliedQ] = useState('');
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const [error, setError] = useState('');
  const CALL_PAGE = 25;
  const pageCount = Math.max(1, Math.ceil(total / CALL_PAGE));
  const safePage = Math.min(page, pageCount);

  async function load(nextPage = safePage) {
    try {
      const params = new URLSearchParams();
      if (appliedQ.trim()) params.set('q', appliedQ.trim());
      if (status) params.set('status', status);
      params.set('limit', String(CALL_PAGE));
      params.set('offset', String((nextPage - 1) * CALL_PAGE));
      const data = await api<{ items: AppCall[]; total: number }>(`/admin/calls?${params}`);
      setItems(data.items || []);
      setTotal(data.total || 0);
      setError('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  useEffect(() => {
    load(safePage).catch(console.error);
    const id = window.setInterval(() => {
      load(safePage).catch(() => undefined);
    }, 15000);
    return () => window.clearInterval(id);
  }, [safePage, appliedQ, status]);

  useEffect(() => {
    setPage(1);
  }, [appliedQ, status]);

  function callTone(s: string) {
    if (s === 'active' || s === 'ringing') return 'chip warn';
    if (s === 'ended') return 'chip ok';
    if (s === 'missed' || s === 'declined' || s === 'failed') return 'chip danger';
    return 'chip neutral';
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Звонки</h1>
          <p>Журнал интернет-звонков. Без записи разговора.</p>
        </div>
      </div>
      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setAppliedQ(query);
        }}
      >
        <input
          placeholder="Имя, объявление, номер звонка…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <select
          value={status}
          onChange={(e) => {
            setPage(1);
            setStatus(e.target.value);
          }}
        >
          <option value="">Все статусы</option>
          {Object.entries(CALL_STATUS_LABEL).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
        </select>
        <button className="btn" type="submit">
          Найти
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Когда</th>
              <th>Кто → кому</th>
              <th>Объявление</th>
              <th>Статус</th>
              <th>Длительность</th>
              <th>Завершил</th>
            </tr>
          </thead>
          <tbody>
            {items.map((row) => (
              <tr key={row.id}>
                <td className="audit-when" title={formatDate(row.created_at)}>
                  {formatAuditWhen(row.created_at)}
                </td>
                <td>
                  <div className="audit-who">{row.caller_name || `#${row.caller_id}`}</div>
                  <div className="audit-sub">→ {row.callee_name || `#${row.callee_id}`}</div>
                </td>
                <td className="audit-obj">{row.listing_title || '—'}</td>
                <td>
                  <span className={callTone(row.status)}>{CALL_STATUS_LABEL[row.status] || row.status}</span>
                  {row.end_reason ? <div className="audit-sub">{row.end_reason}</div> : null}
                </td>
                <td className="audit-when">
                  {row.status === 'ended' || row.duration_sec ? formatDuration(row.duration_sec) : '—'}
                </td>
                <td className="audit-obj">{row.ended_by_name || '—'}</td>
              </tr>
            ))}
            {!items.length && (
              <tr>
                <td colSpan={6} className="empty">
                  {appliedQ || status ? 'Ничего не найдено' : 'Звонков пока нет'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={total} onPage={setPage} />
    </div>
  );
}

const DIR_DAYS = [
  { id: 'mon', short: 'Пн' },
  { id: 'tue', short: 'Вт' },
  { id: 'wed', short: 'Ср' },
  { id: 'thu', short: 'Чт' },
  { id: 'fri', short: 'Пт' },
  { id: 'sat', short: 'Сб' },
  { id: 'sun', short: 'Вс' },
] as const;
const DIR_ALL_DAYS = DIR_DAYS.map((d) => d.id);
const DIR_WEEKDAYS = DIR_ALL_DAYS.slice(0, 5);
const DIR_WEEKENDS = DIR_ALL_DAYS.slice(5);

function sameIdList(a: string[], b: string[]) {
  return a.length === b.length && a.every((id) => b.includes(id));
}

function padClock(hour: string, minute = '00') {
  return `${String(Number(hour)).padStart(2, '0')}:${minute}`;
}

function parseDirHours(text: string) {
  const raw = (text || '').toLowerCase().replaceAll('ё', 'е');
  const allDay = /круглосуточ|24\/7|24 часа/.test(raw);
  const withMin = text.match(/(\d{1,2}):(\d{2})\s*[-–—]\s*(\d{1,2}):(\d{2})/);
  const bare = text.match(/(\d{1,2})\s*[-–—]\s*(\d{1,2})(?!\d)/);
  let from = '09:00';
  let to = '18:00';
  if (withMin) {
    from = padClock(withMin[1], withMin[2]);
    to = padClock(withMin[3], withMin[4]);
  } else if (bare) {
    from = padClock(bare[1]);
    to = padClock(bare[2]);
  }
  let days = [...DIR_ALL_DAYS];
  if (/будн|пн\s*[–-]\s*пт/.test(raw)) days = [...DIR_WEEKDAYS];
  else if (/выходн|сб\s*[–-]\s*вс/.test(raw)) days = [...DIR_WEEKENDS];
  return { allDay, from, to, days };
}

function formatDirHours(allDay: boolean, from: string, to: string, days: string[]) {
  if (allDay) return 'круглосуточно';
  if (!from || !to) return '';
  let label = 'ежедневно';
  if (sameIdList(days, DIR_WEEKDAYS)) label = 'пн–пт';
  else if (sameIdList(days, DIR_WEEKENDS)) label = 'сб–вс';
  else if (!sameIdList(days, DIR_ALL_DAYS)) {
    label = DIR_DAYS.filter((d) => days.includes(d.id))
      .map((d) => d.short.toLowerCase())
      .join(', ');
  }
  if (!days.length) return `${from}–${to}`;
  return `${label} ${from}–${to}`;
}

type DirectoryForm = {
  title: string;
  category: string;
  settlement_id: number | '';
  description: string;
  address: string;
  phone: string;
  website: string;
  hoursAllDay: boolean;
  hoursFrom: string;
  hoursTo: string;
  hoursDays: string[];
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
  hoursAllDay: false,
  hoursFrom: '09:00',
  hoursTo: '18:00',
  hoursDays: [...DIR_WEEKDAYS],
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
    hours: formatDirHours(form.hoursAllDay, form.hoursFrom, form.hoursTo, form.hoursDays) || null,
    lat: form.lat === '' ? null : Number(form.lat),
    lon: form.lon === '' ? null : Number(form.lon),
    is_published: form.is_published,
  };
}

const DIR_PAGE_SIZE = 25;
const DIR_CATEGORIES = [
  'school',
  'hospital',
  'shop',
  'pharmacy',
  'admin',
  'bank',
  'post',
  'transport',
  'culture',
  'sport',
  'other',
];

function DirectoryPage() {
  const [items, setItems] = useState<DirectoryItem[]>([]);
  const [total, setTotal] = useState(0);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [form, setForm] = useState<DirectoryForm>(EMPTY_DIR);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [appliedQ, setAppliedQ] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [publishedFilter, setPublishedFilter] = useState<'all' | 'published' | 'hidden'>('all');
  const [settlementFilter, setSettlementFilter] = useState<number | ''>('');
  const [page, setPage] = useState(1);
  const [listLoading, setListLoading] = useState(true);

  const pageCount = Math.max(1, Math.ceil(total / DIR_PAGE_SIZE));
  const safePage = Math.min(page, pageCount);

  async function loadSettlements() {
    setSettlements(await api<Settlement[]>('/settlements'));
  }

  async function load(nextPage = safePage) {
    const params = new URLSearchParams();
    params.set('limit', String(DIR_PAGE_SIZE));
    params.set('offset', String((nextPage - 1) * DIR_PAGE_SIZE));
    if (appliedQ.trim()) params.set('q', appliedQ.trim());
    if (categoryFilter) params.set('category', categoryFilter);
    if (settlementFilter !== '') params.set('settlement_id', String(settlementFilter));
    if (publishedFilter === 'published') params.set('published', 'true');
    if (publishedFilter === 'hidden') params.set('published', 'false');
    setListLoading(true);
    try {
      const data = await api<{ items: DirectoryItem[]; total: number }>(`/directory?${params}`);
      setItems(data.items || []);
      setTotal(data.total || 0);
    } finally {
      setListLoading(false);
    }
  }

  useEffect(() => {
    loadSettlements().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  useEffect(() => {
    load(safePage).catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [safePage, appliedQ, categoryFilter, publishedFilter, settlementFilter]);

  useEffect(() => {
    setPage(1);
  }, [appliedQ, categoryFilter, publishedFilter, settlementFilter]);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_DIR);
    setError('');
    setModalOpen(true);
  }

  function startEdit(item: DirectoryItem) {
    const hours = parseDirHours(item.hours || '');
    setEditingId(item.id);
    setForm({
      title: item.title,
      category: item.category,
      settlement_id: item.settlement_id ?? '',
      description: item.description || '',
      address: item.address || '',
      phone: item.phone || '',
      website: item.website || '',
      hoursAllDay: hours.allDay,
      hoursFrom: hours.from,
      hoursTo: hours.to,
      hoursDays: hours.days,
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
    try {
      await api(`/directory/${id}`, { method: 'DELETE' });
      if (editingId === id) closeModal();
      await load();
      pushToast('Запись удалена');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Справочник</h1>
          <p>Школы, больницы, магазины и другие точки района</p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить запись
        </button>
      </div>

      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setAppliedQ(query);
        }}
      >
        <input placeholder="Название, адрес, телефон…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select
          value={categoryFilter}
          onChange={(e) => {
            setPage(1);
            setCategoryFilter(e.target.value);
          }}
        >
          <option value="">Все категории</option>
          {DIR_CATEGORIES.map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABELS[c]}
            </option>
          ))}
        </select>
        <select
          value={publishedFilter}
          onChange={(e) => {
            setPage(1);
            setPublishedFilter(e.target.value as 'all' | 'published' | 'hidden');
          }}
        >
          <option value="all">Все статусы</option>
          <option value="published">Опубликованные</option>
          <option value="hidden">Скрытые</option>
        </select>
        <select
          value={settlementFilter === '' ? '' : String(settlementFilter)}
          onChange={(e) => {
            setPage(1);
            setSettlementFilter(e.target.value ? Number(e.target.value) : '');
          }}
        >
          <option value="">Все посёлки, сёла и города</option>
          {settlements.map((s) => (
            <option key={s.id} value={s.id}>
              {s.display_name}
            </option>
          ))}
        </select>
        <button className="btn" type="submit">
          Найти
        </button>
      </form>
      {error && !modalOpen && <p className="error">{error}</p>}

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Место</th>
              <th>Категория</th>
              <th>Посёлок, село, город</th>
              <th>Телефон</th>
              <th>Адрес / часы</th>
              <th>Статус</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id} className="dir-row" onClick={() => startEdit(item)}>
                <td>
                  <div className="audit-who">{item.title}</div>
                  {item.view_count ? <div className="audit-sub">{item.view_count} откр.</div> : null}
                </td>
                <td>
                  <span className="chip">{CATEGORY_LABELS[item.category] || item.category}</span>
                </td>
                <td className="audit-obj">{item.settlement_name || 'без села'}</td>
                <td onClick={(e) => e.stopPropagation()}>
                  {item.phone ? (
                    <a href={`tel:${item.phone}`}>{item.phone}</a>
                  ) : (
                    <span className="audit-sub">нет</span>
                  )}
                </td>
                <td className="audit-details">
                  {item.address || '—'}
                  {item.hours ? <div className="audit-sub">{item.hours}</div> : null}
                  {safeHttpUrl(item.website) ? (
                    <div className="audit-sub">
                      <a href={safeHttpUrl(item.website)} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>
                        сайт
                      </a>
                    </div>
                  ) : null}
                </td>
                <td>
                  {item.is_published ? <span className="chip ok">В приложении</span> : <span className="chip warn">Скрыто</span>}
                </td>
                <td onClick={(e) => e.stopPropagation()}>
                  <div className="actions inline">
                    <button className="btn" type="button" onClick={() => startEdit(item)}>
                      Изменить
                    </button>
                    <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                      Удалить
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {listLoading && !items.length && <WaitRow cols={7} />}
            {!listLoading && !items.length && (
              <tr>
                <td colSpan={7} className="empty">
                  {appliedQ || categoryFilter || publishedFilter !== 'all' || settlementFilter !== ''
                    ? 'Ничего не найдено'
                    : 'Справочник пуст — нажмите «Добавить запись»'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={total} onPage={setPage} />

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
                    {DIR_CATEGORIES.map((c) => (
                      <option key={c} value={c}>
                        {CATEGORY_LABELS[c]}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  Посёлок, село или город
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
                <div className="field full">
                  <span>Часы работы</span>
                  <div className="day-presets">
                    <button
                      type="button"
                      className={`day-pick${form.hoursAllDay ? ' is-on' : ''}`}
                      onClick={() => setForm({ ...form, hoursAllDay: !form.hoursAllDay })}
                    >
                      Круглосуточно
                    </button>
                    <button
                      type="button"
                      className={`day-pick${sameIdList(form.hoursDays, DIR_ALL_DAYS) ? ' is-on' : ''}`}
                      onClick={() => setForm({ ...form, hoursDays: [...DIR_ALL_DAYS] })}
                    >
                      Все дни
                    </button>
                    <button
                      type="button"
                      className={`day-pick${sameIdList(form.hoursDays, DIR_WEEKDAYS) ? ' is-on' : ''}`}
                      onClick={() => setForm({ ...form, hoursDays: [...DIR_WEEKDAYS] })}
                    >
                      Будни
                    </button>
                    <button
                      type="button"
                      className={`day-pick${sameIdList(form.hoursDays, DIR_WEEKENDS) ? ' is-on' : ''}`}
                      onClick={() => setForm({ ...form, hoursDays: [...DIR_WEEKENDS] })}
                    >
                      Выходные
                    </button>
                  </div>
                  <div className="day-picks">
                    {DIR_DAYS.map((day) => (
                      <button
                        key={day.id}
                        type="button"
                        className={`day-pick${form.hoursDays.includes(day.id) ? ' is-on' : ''}`}
                        onClick={() =>
                          setForm({
                            ...form,
                            hoursDays: form.hoursDays.includes(day.id)
                              ? form.hoursDays.filter((id) => id !== day.id)
                              : [...form.hoursDays, day.id],
                          })
                        }
                      >
                        {day.short}
                      </button>
                    ))}
                  </div>
                  {!form.hoursAllDay && (
                    <>
                      <div className="hours-times">
                        <label className="field">
                          Открывается
                          <input
                            type="time"
                            step={60}
                            value={form.hoursFrom}
                            onChange={(e) => setForm({ ...form, hoursFrom: e.target.value })}
                          />
                        </label>
                        <label className="field">
                          Закрывается
                          <input
                            type="time"
                            step={60}
                            value={form.hoursTo}
                            onChange={(e) => setForm({ ...form, hoursTo: e.target.value })}
                          />
                        </label>
                      </div>
                      <p className="field-hint">
                        {formatDirHours(false, form.hoursFrom, form.hoursTo, form.hoursDays) || 'Выберите время'}
                      </p>
                    </>
                  )}
                  {form.hoursAllDay && <p className="field-hint">Работает круглосуточно, без выходных</p>}
                </div>
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

function ChatsModerationPage() {
  const [items, setItems] = useState<AdminConversation[]>([]);
  const [query, setQuery] = useState('');
  const [flaggedOnly, setFlaggedOnly] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [selected, setSelected] = useState<AdminConversation | null>(null);
  const [messages, setMessages] = useState<AdminChatMessage[]>([]);
  const [page, setPage] = useState(1);
  const CHAT_PAGE = 25;

  async function loadList() {
    const params = new URLSearchParams();
    if (query.trim()) params.set('q', query.trim());
    if (flaggedOnly) params.set('flagged_only', 'true');
    const qs = params.toString();
    setItems(await api<AdminConversation[]>(`/admin/chats${qs ? `?${qs}` : ''}`));
  }

  async function openThread(row: AdminConversation) {
    setSelected(row);
    setMessages(await api<AdminChatMessage[]>(`/admin/chats/${row.listing_id}/${row.buyer_id}`));
  }

  useEffect(() => {
    setBusy(true);
    loadList()
      .catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'))
      .finally(() => setBusy(false));
  }, [flaggedOnly]);

  async function refresh() {
    setBusy(true);
    setError('');
    try {
      await loadList();
      if (selected) {
        await openThread(selected);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function deleteMessage(id: number) {
    if (!(await confirmAction('Удалить это сообщение?'))) return;
    try {
      await api(`/admin/chat-messages/${id}`, { method: 'DELETE' });
      pushToast('Сообщение удалено');
      await refresh();
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  async function deleteThread(row: AdminConversation) {
    if (!(await confirmAction(`Удалить всю переписку по «${row.listing_title}» (${row.message_count} сообщ.)?`))) {
      return;
    }
    try {
      await api(`/admin/chats/${row.listing_id}/${row.buyer_id}`, { method: 'DELETE' });
      pushToast('Переписка удалена');
      if (selected?.listing_id === row.listing_id && selected?.buyer_id === row.buyer_id) {
        setSelected(null);
        setMessages([]);
      }
      await loadList();
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  const chatPageCount = Math.max(1, Math.ceil(items.length / CHAT_PAGE));
  const chatSafePage = Math.min(page, chatPageCount);
  const chatPageItems = items.slice((chatSafePage - 1) * CHAT_PAGE, chatSafePage * CHAT_PAGE);

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Чаты</h1>
          <p>Переписки по объявлениям: спам, ссылки, чёрный список</p>
        </div>
      </div>
      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          refresh();
        }}
      >
        <input
          placeholder="Объявление, имена, текст…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <label className="check-inline">
          <input type="checkbox" checked={flaggedOnly} onChange={(e) => setFlaggedOnly(e.target.checked)} />
          Только подозрительные
        </label>
        <button className="btn" type="submit" disabled={busy}>
          {busy ? '…' : 'Найти'}
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      <div className="chat-layout">
        <div>
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Объявление</th>
                  <th>Участники</th>
                  <th>Последнее</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {chatPageItems.map((row) => {
                  const on = selected?.listing_id === row.listing_id && selected?.buyer_id === row.buyer_id;
                  return (
                    <tr
                      key={`${row.listing_id}-${row.buyer_id}`}
                      className={`dir-row${on ? ' is-open' : ''}`}
                      onClick={() => openThread(row).catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'))}
                    >
                      <td>
                        <div className="audit-who">{row.listing_title}</div>
                        <div className="audit-sub">
                          {row.message_count} сообщ.
                          {row.flagged ? ' · подозрительно' : ''}
                        </div>
                      </td>
                      <td className="audit-obj">
                        {row.seller_name || `#${row.seller_id}`}
                        <div className="audit-sub">{row.buyer_name || `#${row.buyer_id}`}</div>
                      </td>
                      <td className="audit-details">
                        {row.last_message || '—'}
                        {row.last_message_at ? (
                          <div className="audit-sub">{formatAuditWhen(row.last_message_at)}</div>
                        ) : null}
                        {!!row.flag_reasons?.length && (
                          <div className="audit-sub">{row.flag_reasons.join(', ')}</div>
                        )}
                      </td>
                      <td onClick={(e) => e.stopPropagation()}>
                        <div className="actions inline">
                          <button
                            className="btn danger"
                            type="button"
                            onClick={() => deleteThread(row)}
                          >
                            Удалить
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
                {!items.length && !busy && (
                  <tr>
                    <td colSpan={4} className="empty">
                      Переписок нет
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
          <Pager page={chatSafePage} pageCount={chatPageCount} total={items.length} onPage={setPage} />
        </div>
        {selected && (
          <div className="table-wrap chat-thread">
            <div className="page-head compact" style={{ padding: '12px 14px 0' }}>
              <div>
                <h2 style={{ margin: 0, fontSize: 16 }}>{selected.listing_title}</h2>
                <p className="muted" style={{ margin: '4px 0 8px' }}>
                  {selected.seller_name} ↔ {selected.buyer_name}
                </p>
              </div>
              <button
                className="btn ghost"
                type="button"
                onClick={() => {
                  setSelected(null);
                  setMessages([]);
                }}
              >
                Закрыть
              </button>
            </div>
            <div>
              {messages.map((m) => (
                <div key={m.id} className={`chat-msg${m.flagged ? ' is-flag' : ''}`}>
                  <div className="meta">
                    <strong>{m.kind === 'call' ? 'Звонок' : m.sender_name || `#${m.sender_id}`}</strong>
                    <span className="chip neutral">{formatAuditWhen(m.created_at)}</span>
                    {m.kind === 'call' && <span className="chip">звонок</span>}
                    {m.is_read ? <span className="chip ok">прочитано</span> : <span className="chip neutral">не прочитано</span>}
                    {m.flagged && <span className="chip danger">флаг</span>}
                  </div>
                  <p style={{ margin: '6px 0 8px', whiteSpace: 'pre-wrap' }}>{m.body}</p>
                  {!!m.flag_reasons?.length && <div className="audit-sub">{m.flag_reasons.join(', ')}</div>}
                  <button className="btn danger" type="button" onClick={() => deleteMessage(m.id)}>
                    Удалить
                  </button>
                </div>
              ))}
              {!messages.length && <div className="empty">Сообщений нет</div>}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function ContactsPage() {
  const [items, setItems] = useState<SiteContact[]>([]);
  const [total, setTotal] = useState(0);
  const [status, setStatus] = useState('new');
  const [query, setQuery] = useState('');
  const [appliedQ, setAppliedQ] = useState('');
  const [page, setPage] = useState(1);
  const [error, setError] = useState('');
  const [selected, setSelected] = useState<SiteContact | null>(null);
  const PAGE = 25;
  const pageCount = Math.max(1, Math.ceil(total / PAGE));
  const safePage = Math.min(page, pageCount);

  async function load(nextPage = safePage) {
    const params = new URLSearchParams();
    params.set('limit', String(PAGE));
    params.set('offset', String((nextPage - 1) * PAGE));
    if (status) params.set('status', status);
    if (appliedQ.trim()) params.set('q', appliedQ.trim());
    const data = await api<{ items: SiteContact[]; total: number }>(`/admin/contacts?${params}`);
    setItems(data.items || []);
    setTotal(data.total || 0);
  }

  useEffect(() => {
    load(safePage).catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [safePage, status, appliedQ]);

  useEffect(() => {
    setPage(1);
  }, [status, appliedQ]);

  async function setStatusOf(row: SiteContact, next: 'new' | 'read' | 'done', quiet = false) {
    try {
      const updated = await api<SiteContact>(`/admin/contacts/${row.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ status: next }),
      });
      setItems((prev) => prev.map((x) => (x.id === updated.id ? updated : x)));
      if (selected?.id === updated.id) setSelected(updated);
      if (!quiet && status && updated.status !== status) {
        await load();
      }
      if (!quiet) {
        pushToast(next === 'done' ? 'Обращение закрыто' : next === 'read' ? 'Прочитано' : 'Снова новое');
      }
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  async function openRow(row: SiteContact) {
    setSelected(row);
    if (row.status === 'new') {
      await setStatusOf(row, 'read', true);
    }
  }

  function statusChip(s: string) {
    if (s === 'new') return 'chip warn';
    if (s === 'done') return 'chip ok';
    return 'chip';
  }

  function statusLabel(s: string) {
    if (s === 'new') return 'Новое';
    if (s === 'read') return 'Прочитано';
    if (s === 'done') return 'Закрыто';
    return s;
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>С сайта</h1>
          <p>Письма с формы на legac.ru. Почта на info@legac.ru дублируется, если SMTP живой.</p>
        </div>
      </div>
      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setAppliedQ(query);
        }}
      >
        <select value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="new">Новые</option>
          <option value="read">Прочитанные</option>
          <option value="done">Закрытые</option>
          <option value="">Все</option>
        </select>
        <input
          placeholder="Имя, место, телефон, текст…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <button className="btn" type="submit">
          Найти
        </button>
      </form>
      {error ? <p className="error">{error}</p> : null}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Когда</th>
              <th>Кто</th>
              <th>Посёлок, село, город</th>
              <th>Текст</th>
              <th>Статус</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((row) => (
              <tr key={row.id} className="dir-row" onClick={() => openRow(row)}>
                <td className="audit-when">{formatAuditWhen(row.created_at)}</td>
                <td>
                  <div className="audit-who">{row.name}</div>
                  {row.phone ? <div className="audit-sub">{row.phone}</div> : null}
                </td>
                <td className="audit-obj">{row.settlement || '—'}</td>
                <td className="audit-details">
                  {row.message.length > 90 ? `${row.message.slice(0, 90)}…` : row.message}
                </td>
                <td>
                  <span className={statusChip(row.status)}>{statusLabel(row.status)}</span>
                  <div className="audit-sub">№ {row.id}</div>
                </td>
                <td onClick={(e) => e.stopPropagation()}>
                  <div className="actions inline">
                    {row.status !== 'done' && (
                      <button className="btn" type="button" onClick={() => setStatusOf(row, 'done')}>
                        Закрыть
                      </button>
                    )}
                    {row.status === 'done' && (
                      <button className="btn ghost" type="button" onClick={() => setStatusOf(row, 'new')}>
                        Снова новое
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
            {!items.length && (
              <tr>
                <td colSpan={6} className="empty">
                  {appliedQ || status ? 'Ничего не найдено' : 'Писем с сайта пока нет'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={total} onPage={setPage} />

      {selected && (
        <div className="modal-backdrop" onClick={() => setSelected(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(560px, 100%)' }}>
            <h2>Обращение № {selected.id}</h2>
            <p className="muted" style={{ marginTop: 0 }}>
              {formatAuditWhen(selected.created_at)} · {selected.settlement || 'место не указано'}
              {selected.ip ? ` · IP ${selected.ip}` : ''}
            </p>
            <p>
              <strong>{selected.name}</strong>
              {selected.phone ? (
                <>
                  {' · '}
                  <a href={`tel:${selected.phone}`}>{selected.phone}</a>
                </>
              ) : null}
            </p>
            <p style={{ whiteSpace: 'pre-wrap' }}>{selected.message}</p>
            <div className="modal-actions">
              {selected.status !== 'done' && (
                <button className="btn" type="button" onClick={() => setStatusOf(selected, 'done')}>
                  Закрыть обращение
                </button>
              )}
              {selected.status === 'done' && (
                <button className="btn ghost" type="button" onClick={() => setStatusOf(selected, 'new')}>
                  Снова новое
                </button>
              )}
              <button className="btn secondary" type="button" onClick={() => setSelected(null)}>
                Закрыть окно
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function BlacklistPage() {
  const [items, setItems] = useState<BlacklistEntry[]>([]);
  const [kind, setKind] = useState<'phone' | 'word'>('word');
  const [kindFilter, setKindFilter] = useState<'all' | 'phone' | 'word'>('all');
  const [value, setValue] = useState('');
  const [note, setNote] = useState('');
  const [error, setError] = useState('');
  const [page, setPage] = useState(1);
  const BL_PAGE = 25;

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
      pushToast('Добавлено в чёрный список');
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

  const visible = kindFilter === 'all' ? items : items.filter((row) => row.kind === kindFilter);
  const pageCount = Math.max(1, Math.ceil(visible.length / BL_PAGE));
  const safePage = Math.min(page, pageCount);
  const pageItems = visible.slice((safePage - 1) * BL_PAGE, safePage * BL_PAGE);

  useEffect(() => {
    setPage(1);
  }, [kindFilter]);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

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
        <select
          value={kindFilter}
          onChange={(e) => setKindFilter(e.target.value as 'all' | 'phone' | 'word')}
        >
          <option value="all">Все записи</option>
          <option value="word">Только слова</option>
          <option value="phone">Только телефоны</option>
        </select>
      </form>
      {error && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Значение</th>
              <th>Тип</th>
              <th>Заметка</th>
              <th>Добавлено</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {pageItems.map((row) => (
              <tr key={row.id}>
                <td>
                  <div className="audit-who">{row.value}</div>
                </td>
                <td>
                  <span className={row.kind === 'phone' ? 'chip warn' : 'chip'}>
                    {row.kind === 'phone' ? 'Телефон' : 'Слово'}
                  </span>
                </td>
                <td className="audit-details">{row.note || '—'}</td>
                <td className="audit-when">{formatAuditWhen(row.created_at)}</td>
                <td>
                  <div className="actions inline">
                    <button className="btn danger" type="button" onClick={() => remove(row.id)}>
                      Удалить
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {!visible.length && (
              <tr>
                <td colSpan={5} className="empty">
                  {kindFilter !== 'all' ? 'Нет записей этого типа' : 'Список пуст — добавьте слово или телефон'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={visible.length} onPage={setPage} />
    </div>
  );
}

function UsersPage() {
  const navigate = useNavigate();
  const emptyForm = {
    full_name: '',
    email: '',
    phone: '',
    settlement_id: 0,
    role: 'user' as User['role'],
    is_active: true,
    password: '',
    password2: '',
    badge: '',
  };
  const [users, setUsers] = useState<User[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [selected, setSelected] = useState<User | null>(null);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [pushBusy, setPushBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [appliedQ, setAppliedQ] = useState('');
  const [suspicious, setSuspicious] = useState(false);
  const [userKind, setUserKind] = useState<'all' | 'feed' | 'real'>('real');
  const [pushTitle, setPushTitle] = useState('Рядом56');
  const [pushBody, setPushBody] = useState('');
  const [page, setPage] = useState(1);
  const USER_PAGE = 25;

  async function loadSettlements() {
    const s = await api<Settlement[]>('/settlements');
    setSettlements(s);
    setForm((prev) => (prev.settlement_id ? prev : { ...prev, settlement_id: s[0]?.id || 0 }));
  }

  async function load() {
    const params = new URLSearchParams();
    if (appliedQ.trim()) params.set('q', appliedQ.trim());
    if (suspicious) params.set('suspicious', '1');
    if (userKind === 'feed' || userKind === 'real') params.set('kind', userKind);
    const qs = params.toString();
    setUsers(await api<User[]>(`/admin/users${qs ? `?${qs}` : ''}`));
  }

  useEffect(() => {
    loadSettlements().catch(console.error);
  }, []);

  useEffect(() => {
    load().catch(console.error);
  }, [appliedQ, suspicious, userKind]);

  useEffect(() => {
    setPage(1);
  }, [appliedQ, suspicious, userKind]);

  async function exportCsv() {
    try {
      const params = new URLSearchParams();
      if (appliedQ.trim()) params.set('q', appliedQ.trim());
      if (suspicious) params.set('suspicious', '1');
      if (userKind === 'feed' || userKind === 'real') params.set('kind', userKind);
      const qs = params.toString();
      const text = await apiText(`/admin/users/export${qs ? `?${qs}` : ''}`);
      const blob = new Blob([text], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = suspicious ? 'users-suspicious.csv' : 'users.csv';
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Не удалось скачать CSV');
    }
  }

  function openCreate() {
    setSelected(null);
    setCreating(true);
    setForm({
      ...emptyForm,
      settlement_id: settlements[0]?.id || 0,
    });
    setPushTitle('Рядом56');
    setPushBody('');
    setError('');
  }

  function closeEditor() {
    setSelected(null);
    setCreating(false);
    setError('');
  }

  function openEdit(u: User) {
    setCreating(false);
    setSelected(u);
    setForm({
      full_name: u.full_name,
      email: u.email,
      phone: u.phone || '',
      settlement_id: u.settlement_id,
      role: u.role,
      is_active: u.is_active,
      password: '',
      password2: '',
      badge: u.badge || '',
    });
    setPushTitle('Рядом56');
    setPushBody('');
    setError('');
  }

  async function saveUser(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (!form.full_name.trim() || !isValidEmail(form.email)) {
      setError('Проверьте имя и email');
      return;
    }
    if (!form.settlement_id) {
      setError('Выберите посёлок, село или город');
      return;
    }
    if (creating && form.password.length < 6) {
      setError('Пароль не короче 6 символов');
      return;
    }
    if (form.password && form.password !== form.password2) {
      setError('Пароли не совпадают');
      return;
    }
    if (form.password && form.password.length < 6) {
      setError('Пароль не короче 6 символов');
      return;
    }
    if (!creating && selected?.is_active && !form.is_active) {
      if (!(await confirmAction(`Заблокировать пользователя ${selected.full_name}?`))) return;
    }
    if (
      form.role !== (creating ? 'user' : selected?.role) &&
      (form.role === 'moderator' || form.role === 'editor' || form.role === 'admin')
    ) {
      const who = creating ? form.full_name.trim() : selected?.full_name || '';
      if (
        !(await confirmAction(
          `Назначить роль «${ROLE_LABELS[form.role]}» пользователю ${who}? Это даст доступ к админке.`,
        ))
      ) {
        return;
      }
    }
    setBusy(true);
    setError('');
    const body: Record<string, unknown> = {
      full_name: form.full_name.trim(),
      email: form.email.trim(),
      phone: form.phone.trim() || null,
      settlement_id: form.settlement_id,
      role: form.role,
      is_active: form.is_active,
      badge: form.badge || null,
    };
    if (form.password) body.password = form.password;
    try {
      if (creating) {
        const created = await api<User>('/admin/users', {
          method: 'POST',
          body: JSON.stringify(body),
        });
        setUsers((prev) => [created, ...prev.filter((u) => u.id !== created.id)]);
        setCreating(false);
        setSelected(created);
        setForm((prev) => ({ ...prev, password: '', password2: '' }));
        pushToast('Пользователь создан');
      } else if (selected) {
        const updated = await api<User>(`/admin/users/${selected.id}`, {
          method: 'PATCH',
          body: JSON.stringify(body),
        });
        setUsers((prev) => prev.map((u) => (u.id === updated.id ? updated : u)));
        setSelected(updated);
        setForm((prev) => ({ ...prev, password: '', password2: '' }));
        pushToast('Пользователь сохранён');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function sendPush() {
    if (!selected || creating || busy || pushBusy) return;
    const text = pushBody.trim();
    if (!text) {
      setError('Напишите текст пуша');
      return;
    }
    if (!(await confirmAction(`Отправить пуш «${selected.full_name}»?`))) return;
    setPushBusy(true);
    setError('');
    try {
      const res = await api<{ ok?: boolean; devices?: number; message?: string }>(
        `/admin/users/${selected.id}/push`,
        {
          method: 'POST',
          body: JSON.stringify({ title: pushTitle.trim() || 'Рядом56', body: text }),
        },
      );
      pushToast(res.message || 'Сообщение отправлено');
      setPushBody('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка отправки');
    } finally {
      setPushBusy(false);
    }
  }

  const pageCount = Math.max(1, Math.ceil(users.length / USER_PAGE));
  const safePage = Math.min(page, pageCount);
  const pageItems = users.slice((safePage - 1) * USER_PAGE, safePage * USER_PAGE);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

  return (
    <div className="users-page">
      <div className="page-head compact">
        <div>
          <h1>Пользователи</h1>
          <p>Сначала живые. Фейковые — для ленты. Подозрительные — один IP на несколько аккаунтов</p>
        </div>
        <div className="toolbar compact" style={{ margin: 0 }}>
          <button className="btn" type="button" onClick={openCreate}>
            Создать пользователя
          </button>
          <button className="btn secondary" type="button" onClick={() => exportCsv().catch(console.error)}>
            Экспорт CSV
          </button>
        </div>
      </div>
      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setAppliedQ(query);
        }}
      >
        <input
          placeholder="Имя, email, телефон, IP, устройство…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <label className="check-inline">
          <input type="checkbox" checked={suspicious} onChange={(e) => setSuspicious(e.target.checked)} />
          Только подозрительные
        </label>
        <select
          value={userKind}
          onChange={(e) => setUserKind(e.target.value as 'all' | 'feed' | 'real')}
        >
          <option value="real">Живые</option>
          <option value="feed">Фейковые (для ленты)</option>
          <option value="all">Все</option>
        </select>
        <button className="btn" type="submit">
          Найти
        </button>
      </form>
      {error && !creating && !selected && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Человек</th>
              <th>Посёлок, село, город</th>
              <th>Роль</th>
              <th>Статус</th>
              <th>Устройство</th>
              <th>Был</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {pageItems.map((u) => (
              <tr
                key={u.id}
                className={`dir-row${selected?.id === u.id ? ' is-open' : ''}`}
                onClick={() => openEdit(u)}
              >
                <td>
                  <div className="audit-who">{u.full_name}</div>
                  <div className="audit-sub">{u.email}{u.phone ? ` · ${u.phone}` : ''}</div>
                </td>
                <td className="cell-plain">{u.settlement?.display_name || '—'}</td>
                <td>
                  <span className="cell-plain">{ROLE_LABELS[u.role]}</span>
                  {u.badge === 'feed' ? <div className="audit-sub">лента</div> : null}
                </td>
                <td>
                  <span className={`status-text ${u.is_active ? 'is-approved' : 'is-rejected'}`}>
                    {u.is_active ? 'Активен' : 'Заблокирован'}
                  </span>
                  <div className="audit-sub">{u.has_push ? 'пуш есть' : 'без пуша'}</div>
                </td>
                <td className="audit-sub">
                  {u.last_ip || 'нет IP'}
                  {(u.device_brand || u.device_model) ? ` · ${[u.device_brand, u.device_model].filter(Boolean).join(' ')}` : ''}
                </td>
                <td className="audit-when">{formatAuditWhen(u.last_seen_at)}</td>
                <td className="acts" onClick={(e) => e.stopPropagation()}>
                  <button
                    className="row-act"
                    type="button"
                    onClick={() => navigate(`/listings?authorId=${u.id}`)}
                  >
                    Объявления
                  </button>
                  <button className="row-act" type="button" onClick={() => openEdit(u)}>
                    Изменить
                  </button>
                </td>
              </tr>
            ))}
            {!users.length && (
              <tr>
                <td colSpan={7} className="empty">
                  {appliedQ || suspicious || userKind !== 'all' ? 'Ничего не найдено' : 'Пользователей пока нет'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={users.length} onPage={setPage} />

      {(creating || selected) && (
        <div className="modal-backdrop" onClick={closeEditor}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h2>{creating ? 'Новый пользователь' : 'Редактировать пользователя'}</h2>
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
                  Посёлок, село или город
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
                {!creating && selected && !form.is_active && selected.ban_reason ? (
                  <p className="muted">Причина блокировки: {selected.ban_reason}. Снимите блок статусом «Активен».</p>
                ) : null}
                <label className="field">
                  Метка
                  <select value={form.badge} onChange={(e) => setForm({ ...form, badge: e.target.value })}>
                    {Object.entries(BADGE_LABELS).map(([value, label]) => (
                      <option key={value || 'none'} value={value}>
                        {label}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  {creating ? 'Пароль' : 'Новый пароль'}
                  <input
                    type="password"
                    autoComplete="new-password"
                    required={creating}
                    placeholder={creating ? 'минимум 6 символов' : 'оставьте пустым, чтобы не менять'}
                    value={form.password}
                    onChange={(e) => setForm({ ...form, password: e.target.value })}
                  />
                </label>
                <label className="field">
                  Повторите пароль
                  <input
                    type="password"
                    autoComplete="new-password"
                    required={creating || Boolean(form.password)}
                    value={form.password2}
                    onChange={(e) => setForm({ ...form, password2: e.target.value })}
                  />
                </label>
              </div>

              {selected && !creating && (
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
              )}

              {selected && !creating && (
              <div className="panel" style={{ marginTop: 16, marginBottom: 0, padding: 14 }}>
                <h3 style={{ margin: '0 0 10px', fontSize: 15 }}>Пуш этому пользователю</h3>
                <p className="muted" style={{ margin: '0 0 10px' }}>
                  {selected.has_push
                    ? 'Токен есть — уйдёт на телефон и в колокольчик приложения.'
                    : 'Токена нет: в колокольчик запишется, на телефон не придёт, пока человек не откроет приложение с пушами.'}
                </p>
                <label className="field">
                  Заголовок
                  <input
                    maxLength={80}
                    value={pushTitle}
                    onChange={(e) => setPushTitle(e.target.value)}
                    placeholder="Рядом56"
                  />
                </label>
                <label className="field" style={{ marginTop: 10 }}>
                  Текст
                  <textarea
                    rows={3}
                    maxLength={400}
                    value={pushBody}
                    onChange={(e) => setPushBody(e.target.value)}
                    placeholder="Короткое сообщение на телефон"
                  />
                </label>
                <div style={{ marginTop: 12 }}>
                  <button className="btn" type="button" disabled={busy || pushBusy} onClick={() => sendPush().catch(console.error)}>
                    {pushBusy ? 'Отправка…' : 'Отправить пуш'}
                  </button>
                </div>
              </div>
              )}

              {error && <p className="error">{error}</p>}
              <div className="modal-actions">
                <button className="btn" type="submit" disabled={busy}>
                  {busy ? 'Сохранение…' : creating ? 'Создать' : 'Сохранить'}
                </button>
                {selected && !creating && (
                <button
                  className="btn ghost"
                  type="button"
                  disabled={busy}
                  onClick={async () => {
                    if (!(await confirmAction(`Выйти из аккаунта «${selected.full_name}» на всех телефонах?`))) return;
                    setBusy(true);
                    setError('');
                    try {
                      const res = await api<{ ok?: boolean; message?: string }>(`/admin/users/${selected.id}/revoke-sessions`, {
                        method: 'POST',
                      });
                      pushToast(res.message || 'Выполнен выход на всех устройствах');
                    } catch (err) {
                      setError(err instanceof Error ? err.message : 'Ошибка');
                    } finally {
                      setBusy(false);
                    }
                  }}
                >
                  Выйти на всех телефонах
                </button>
                )}
                {selected && !creating && (
                <button
                  className="btn ghost"
                  type="button"
                  onClick={() => {
                    const id = selected.id;
                    closeEditor();
                    navigate(`/listings?authorId=${id}`);
                  }}
                >
                  Объявления
                </button>
                )}
                <button className="btn secondary" type="button" onClick={closeEditor}>
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

const EVENT_PAGE_SIZE = 10;

function EventsPage() {
  const [searchParams] = useSearchParams();
  const statusParam = searchParams.get('status');
  const upcomingParam = searchParams.get('upcoming') === '1' || searchParams.get('upcoming') === 'true';
  const idParam = searchParams.get('id');
  const openedFromUrl = useRef<string | null>(null);
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
  const [statusFilter, setStatusFilter] = useState<'all' | 'draft' | 'scheduled' | 'published'>(() => {
    if (upcomingParam) return 'published';
    if (statusParam === 'draft' || statusParam === 'scheduled' || statusParam === 'published') return statusParam;
    return 'all';
  });
  const [page, setPage] = useState(1);

  async function load() {
    const params = new URLSearchParams({ limit: '500' });
    if (upcomingParam) {
      params.set('upcoming', 'true');
      params.set('status', 'published');
    } else if (statusFilter !== 'all') {
      params.set('status', statusFilter);
    }
    const [ev, s] = await Promise.all([
      api<EventItem[] | { items: EventItem[] }>(`/events?${params}`),
      api<Settlement[]>('/settlements'),
    ]);
    setItems(asItems(ev));
    setSettlements(s);
  }

  useEffect(() => {
    if (upcomingParam) setStatusFilter('published');
    else if (statusParam === 'draft' || statusParam === 'scheduled' || statusParam === 'published') {
      setStatusFilter(statusParam);
    }
  }, [statusParam, upcomingParam]);

  useEffect(() => {
    load().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [statusFilter, upcomingParam]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items;
    return items.filter(
      (item) =>
        item.title.toLowerCase().includes(q) ||
        item.place_text.toLowerCase().includes(q) ||
        (item.settlement_name || '').toLowerCase().includes(q) ||
        (item.address || '').toLowerCase().includes(q),
    );
  }, [items, query]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / EVENT_PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * EVENT_PAGE_SIZE, safePage * EVENT_PAGE_SIZE);

  useEffect(() => {
    setPage(1);
  }, [query, statusFilter]);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

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

  useEffect(() => {
    if (!idParam) {
      openedFromUrl.current = null;
      return;
    }
    if (openedFromUrl.current === idParam) return;
    const id = Number(idParam);
    if (!Number.isFinite(id)) return;
    const found = items.find((x) => x.id === id);
    if (found) {
      openedFromUrl.current = idParam;
      startEdit(found);
      return;
    }
    api<EventItem>(`/events/${id}`)
      .then((item) => {
        openedFromUrl.current = idParam;
        startEdit(item);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [idParam, items]);

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
    try {
      await api(`/events/${id}`, { method: 'DELETE' });
      if (editingId === id) closeModal();
      await load();
      pushToast('Событие удалено');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Афиша</h1>
          <p>События района для вкладки «Афиша» в приложении</p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить событие
        </button>
      </div>
      <div className="toolbar compact">
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
      <div className="list compact">
        {visible.map((item) => {
          const extra = extraSeanceCount(item.description);
          const preview = eventPreview(item.description);
          return (
            <article
              key={item.id}
              className="row-card compact event-card"
              onClick={() => startEdit(item)}
            >
              <div className="event-cover">
                {item.cover_url ? (
                  <img src={mediaUrl(item.cover_url)} alt="" />
                ) : (
                  <div className="event-cover-empty">Нет фото</div>
                )}
              </div>
              <div className="row-main">
                <h3 className="row-title">{item.title}</h3>
                <div className="meta">
                  <span className="chip">{formatEventWhen(item.starts_at, item.ends_at)}</span>
                  {extra > 0 && <span className="chip neutral">ещё {extra} дат</span>}
                  <span className="chip neutral">{item.place_text}</span>
                  {item.settlement_name && <span className="chip neutral">{item.settlement_name}</span>}
                  <span
                    className={`chip ${item.status === 'published' ? 'ok' : item.status === 'scheduled' ? 'warn' : 'neutral'}`}
                  >
                    {EVENT_STATUS_LABELS[item.status || ''] || (item.is_published ? 'Опубликовано' : 'Черновик')}
                  </span>
                  {item.view_count != null && item.view_count > 0 && (
                    <span className="chip neutral">{item.view_count} просм.</span>
                  )}
                </div>
                {preview ? <p className="row-body">{preview}</p> : null}
              </div>
              <div className="actions inline" onClick={(e) => e.stopPropagation()}>
                <button className="btn" type="button" onClick={() => startEdit(item)}>
                  Изменить
                </button>
                <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                  Удалить
                </button>
              </div>
            </article>
          );
        })}
        {!filtered.length && <div className="empty">{query.trim() ? 'Ничего не найдено' : 'Событий пока нет'}</div>}
      </div>
      <Pager page={safePage} pageCount={pageCount} total={filtered.length} onPage={setPage} />

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
                  Посёлок, село или город
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

const TRANSPORT_PAGE_SIZE = 25;
const WEEK_DAYS = [
  { id: 'mon', short: 'Пн' },
  { id: 'tue', short: 'Вт' },
  { id: 'wed', short: 'Ср' },
  { id: 'thu', short: 'Чт' },
  { id: 'fri', short: 'Пт' },
  { id: 'sat', short: 'Сб' },
  { id: 'sun', short: 'Вс' },
] as const;
const ALL_DAYS = WEEK_DAYS.map((d) => d.id);
const WEEKDAY_IDS = ALL_DAYS.slice(0, 5);
const WEEKEND_IDS = ALL_DAYS.slice(5);

type TripDraft = {
  depart: string;
  arrive: string;
  days: string[];
};

type TransportForm = {
  fromName: string;
  toName: string;
  via: TransportStop[];
  viaDraft: string;
  trips: TripDraft[];
  tripDays: string[];
  departDraft: string;
  arriveDraft: string;
  description: string;
  notes: string;
  fare_text: string;
  phone: string;
  settlement_id: number | '';
  is_published: boolean;
};

const EMPTY_TRANSPORT: TransportForm = {
  fromName: '',
  toName: '',
  via: [],
  viaDraft: '',
  trips: [],
  tripDays: [...ALL_DAYS],
  departDraft: '',
  arriveDraft: '',
  description: '',
  notes: '',
  fare_text: '',
  phone: '',
  settlement_id: '',
  is_published: true,
};

function sameDays(a: string[], b: string[]) {
  return a.length === b.length && a.every((id) => b.includes(id));
}

function daysLabel(days: string[]) {
  if (sameDays(days, ALL_DAYS)) return 'все дни';
  if (sameDays(days, WEEKDAY_IDS)) return 'будни';
  if (sameDays(days, WEEKEND_IDS)) return 'выходные';
  return WEEK_DAYS.filter((d) => days.includes(d.id))
    .map((d) => d.short)
    .join(', ');
}

function tripStamp(trip: { depart: string; arrive?: string | null }) {
  return trip.arrive ? `${trip.depart} → ${trip.arrive}` : trip.depart;
}

function tripCaption(trip: { depart: string; arrive?: string | null; days: string[]; days_label?: string }) {
  return `${trip.days_label || daysLabel(trip.days)} ${tripStamp(trip)}`;
}

function parseTimesFromText(text: string): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const re = /\b([01]?\d|2[0-3])[:.]([0-5]\d)\b/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(text || ''))) {
    const stamp = `${String(Number(match[1])).padStart(2, '0')}:${match[2]}`;
    if (!seen.has(stamp)) {
      seen.add(stamp);
      out.push(stamp);
    }
  }
  return out.sort();
}

function tripsFromItem(item: TransportRoute): TripDraft[] {
  if (item.trips?.length) {
    return item.trips.map((trip) => ({
      depart: trip.depart,
      arrive: trip.arrive || '',
      days: trip.days?.length ? [...trip.days] : [...ALL_DAYS],
    }));
  }
  const times = item.times?.length ? item.times : parseTimesFromText(item.schedule_text);
  return times.map((stamp) => {
    const parts = stamp.split('→').map((s) => s.trim());
    return { depart: parts[0]?.slice(0, 5) || stamp, arrive: parts[1]?.slice(0, 5) || '', days: [...ALL_DAYS] };
  });
}

function routePoints(item: TransportRoute): { id: number; name: string }[] {
  if (item.stop_points && item.stop_points.length) {
    return item.stop_points.map((p) => ({ id: p.id, name: p.name }));
  }
  return (item.stops || []).map((name) => ({ id: 0, name }));
}

function TransportPage() {
  const [items, setItems] = useState<TransportRoute[]>([]);
  const [total, setTotal] = useState(0);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [catalog, setCatalog] = useState<TransportStop[]>([]);
  const [form, setForm] = useState<TransportForm>(EMPTY_TRANSPORT);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [appliedQ, setAppliedQ] = useState('');
  const [publishedFilter, setPublishedFilter] = useState<'all' | 'published' | 'hidden'>('all');
  const [settlementFilter, setSettlementFilter] = useState<number | ''>('');
  const [page, setPage] = useState(1);

  const pageCount = Math.max(1, Math.ceil(total / TRANSPORT_PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const previewTitle =
    form.fromName.trim() && form.toName.trim()
      ? `${form.fromName.trim()} → ${form.toName.trim()}`
      : 'Откуда → куда';

  async function loadCatalog() {
    setCatalog(await api<TransportStop[]>('/transport/stops'));
  }

  async function loadSettlements() {
    setSettlements(await api<Settlement[]>('/settlements'));
  }

  async function load(nextPage = safePage) {
    const params = new URLSearchParams();
    params.set('limit', String(TRANSPORT_PAGE_SIZE));
    params.set('offset', String((nextPage - 1) * TRANSPORT_PAGE_SIZE));
    if (appliedQ.trim()) params.set('q', appliedQ.trim());
    if (settlementFilter !== '') params.set('settlement_id', String(settlementFilter));
    if (publishedFilter === 'published') params.set('published', 'true');
    if (publishedFilter === 'hidden') params.set('published', 'false');
    const data = await api<{ items: TransportRoute[]; total: number }>(`/transport?${params}`);
    setItems(data.items || []);
    setTotal(data.total || 0);
  }

  useEffect(() => {
    loadSettlements().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
    loadCatalog().catch(() => undefined);
  }, []);

  useEffect(() => {
    load(safePage).catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [safePage, appliedQ, publishedFilter, settlementFilter]);

  useEffect(() => {
    setPage(1);
  }, [appliedQ, publishedFilter, settlementFilter]);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_TRANSPORT);
    setError('');
    setModalOpen(true);
    loadCatalog().catch(() => undefined);
  }

  function startEdit(item: TransportRoute) {
    const points = routePoints(item);
    setEditingId(item.id);
    setForm({
      fromName: points[0]?.name || '',
      toName: points.length > 1 ? points[points.length - 1].name : '',
      via: points.slice(1, -1).map((p) => ({ id: p.id, name: p.name, created_at: '' })),
      viaDraft: '',
      trips: tripsFromItem(item),
      tripDays: [...ALL_DAYS],
      departDraft: '',
      arriveDraft: '',
      description: item.description || '',
      notes: item.notes || '',
      fare_text: item.fare_text || '',
      phone: item.phone || '',
      settlement_id: item.settlement_id ?? '',
      is_published: item.is_published,
    });
    setError('');
    setModalOpen(true);
    loadCatalog().catch(() => undefined);
  }

  function closeModal() {
    if (busy) return;
    setModalOpen(false);
    setEditingId(null);
    setForm(EMPTY_TRANSPORT);
    setError('');
  }

  async function resolveStop(name: string): Promise<TransportStop> {
    const trimmed = name.trim();
    if (trimmed.length < 2) throw new Error('Название остановки слишком короткое');
    const found = catalog.find((s) => s.name.toLowerCase() === trimmed.toLowerCase());
    if (found) return found;
    const created = await api<TransportStop>('/transport/stops', {
      method: 'POST',
      body: JSON.stringify({ name: trimmed }),
    });
    setCatalog((prev) => {
      if (prev.some((s) => s.id === created.id)) return prev;
      return [...prev, created].sort((a, b) => a.name.localeCompare(b.name, 'ru'));
    });
    return created;
  }

  async function addVia() {
    const name = form.viaDraft.trim();
    if (!name) return;
    try {
      const stop = await resolveStop(name);
      const used = [form.fromName, form.toName, ...form.via.map((s) => s.name)].map((s) => s.trim().toLowerCase());
      if (used.includes(stop.name.toLowerCase())) {
        setError('Эта остановка уже есть в маршруте');
        return;
      }
      setForm({ ...form, via: [...form.via, stop], viaDraft: '' });
      setError('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  function moveVia(index: number, dir: -1 | 1) {
    const next = [...form.via];
    const target = index + dir;
    if (target < 0 || target >= next.length) return;
    [next[index], next[target]] = [next[target], next[index]];
    setForm({ ...form, via: next });
  }

  function toggleTripDay(id: string) {
    const on = form.tripDays.includes(id);
    const next = on ? form.tripDays.filter((d) => d !== id) : [...form.tripDays, id];
    setForm({ ...form, tripDays: ALL_DAYS.filter((d) => next.includes(d)) });
  }

  function addTrip() {
    const depart = form.departDraft.trim().slice(0, 5);
    const arrive = form.arriveDraft.trim().slice(0, 5);
    if (!/^\d{2}:\d{2}$/.test(depart) || !/^\d{2}:\d{2}$/.test(arrive)) {
      setError('Укажите время отправления и прибытия');
      return;
    }
    if (!form.tripDays.length) {
      setError('Выберите дни следования');
      return;
    }
    const days = ALL_DAYS.filter((d) => form.tripDays.includes(d));
    const exists = form.trips.some(
      (t) => t.depart === depart && t.arrive === arrive && sameDays(t.days, days),
    );
    if (exists) {
      setForm({ ...form, departDraft: '', arriveDraft: '' });
      return;
    }
    const trips = [...form.trips, { depart, arrive, days }].sort((a, b) => a.depart.localeCompare(b.depart));
    setForm({ ...form, trips, departDraft: '', arriveDraft: '' });
    setError('');
  }

  async function saveItem(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (!form.fromName.trim() || !form.toName.trim()) {
      setError('Укажите откуда и куда');
      return;
    }
    if (form.fromName.trim().toLowerCase() === form.toName.trim().toLowerCase()) {
      setError('Откуда и куда должны отличаться');
      return;
    }
    if (!form.trips.length) {
      setError('Добавьте хотя бы один рейс');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const from = await resolveStop(form.fromName);
      const to = await resolveStop(form.toName);
      const viaStops: TransportStop[] = [];
      for (const stop of form.via) {
        viaStops.push(stop.id ? stop : await resolveStop(stop.name));
      }
      const body = {
        stop_ids: [from.id, ...viaStops.map((s) => s.id), to.id],
        trips: form.trips.map((t) => ({
          depart: t.depart,
          arrive: t.arrive || null,
          days: t.days,
        })),
        description: form.description.trim() || null,
        notes: form.notes.trim() || null,
        fare_text: form.fare_text.trim() || null,
        phone: form.phone.trim() || null,
        settlement_id: form.settlement_id === '' ? null : Number(form.settlement_id),
        is_published: form.is_published,
      };
      if (editingId) {
        await api(`/transport/${editingId}`, { method: 'PATCH', body: JSON.stringify(body) });
      } else {
        await api('/transport', { method: 'POST', body: JSON.stringify(body) });
      }
      setModalOpen(false);
      setEditingId(null);
      setForm(EMPTY_TRANSPORT);
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
    try {
      await api(`/transport/${id}`, { method: 'DELETE' });
      if (editingId === id) closeModal();
      await load();
      pushToast('Маршрут удалён');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Транспорт</h1>
          <p>Маршрут — откуда и куда. Время и остановки добавляются по одному.</p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить маршрут
        </button>
      </div>
      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setAppliedQ(query);
        }}
      >
        <input placeholder="Остановка, место…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select
          value={publishedFilter}
          onChange={(e) => {
            setPage(1);
            setPublishedFilter(e.target.value as 'all' | 'published' | 'hidden');
          }}
        >
          <option value="all">Все статусы</option>
          <option value="published">Опубликованные</option>
          <option value="hidden">Скрытые</option>
        </select>
        <select
          value={settlementFilter === '' ? '' : String(settlementFilter)}
          onChange={(e) => {
            setPage(1);
            setSettlementFilter(e.target.value ? Number(e.target.value) : '');
          }}
        >
          <option value="">Все посёлки, сёла и города</option>
          {settlements.map((s) => (
            <option key={s.id} value={s.id}>
              {s.display_name}
            </option>
          ))}
        </select>
        <button className="btn" type="submit">
          Найти
        </button>
      </form>
      {error && !modalOpen && <p className="error">{error}</p>}

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Маршрут</th>
              <th>Остановки</th>
              <th>Рейсы</th>
              <th>Посёлок, село, город</th>
              <th>Статус</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => {
              const points = routePoints(item);
              const trips = item.trips?.length ? item.trips : tripsFromItem(item);
              return (
                <tr key={item.id} className="dir-row" onClick={() => startEdit(item)}>
                  <td>
                    <div className="audit-who">{item.title}</div>
                    {item.next_departure ? <div className="audit-sub">ближайший {item.next_departure}</div> : null}
                  </td>
                  <td className="audit-details">
                    {points.length ? points.map((p) => p.name).join(' · ') : '—'}
                  </td>
                  <td>
                    <div className="time-chips compact">
                      {trips.slice(0, 4).map((t) => (
                        <span key={tripCaption(t)} className="time-chip">
                          {tripCaption(t)}
                        </span>
                      ))}
                      {trips.length > 4 ? <span className="audit-sub">+{trips.length - 4}</span> : null}
                    </div>
                  </td>
                  <td className="audit-obj">{item.settlement_name || '—'}</td>
                  <td>
                    {item.is_published ? <span className="chip ok">В приложении</span> : <span className="chip warn">Скрыто</span>}
                  </td>
                  <td onClick={(e) => e.stopPropagation()}>
                    <div className="actions inline">
                      <button className="btn" type="button" onClick={() => startEdit(item)}>
                        Изменить
                      </button>
                      <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                        Удалить
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
            {!items.length && (
              <tr>
                <td colSpan={6} className="empty">
                  {appliedQ || publishedFilter !== 'all' || settlementFilter !== ''
                    ? 'Ничего не найдено'
                    : 'Маршрутов пока нет — нажмите «Добавить маршрут»'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={total} onPage={setPage} />

      {modalOpen && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(720px, 100%)' }}>
            <h2>{editingId ? 'Редактировать маршрут' : 'Новый маршрут'}</h2>
            <p className="route-preview">{previewTitle}</p>
            <form onSubmit={saveItem}>
              <datalist id="transport-stop-catalog">
                {catalog.map((s) => (
                  <option key={s.id} value={s.name} />
                ))}
              </datalist>
              <div className="grid2">
                <label className="field">
                  Откуда
                  <input
                    required
                    list="transport-stop-catalog"
                    value={form.fromName}
                    onChange={(e) => setForm({ ...form, fromName: e.target.value })}
                    placeholder="Сакмара"
                  />
                </label>
                <label className="field">
                  Куда
                  <input
                    required
                    list="transport-stop-catalog"
                    value={form.toName}
                    onChange={(e) => setForm({ ...form, toName: e.target.value })}
                    placeholder="Оренбург"
                  />
                </label>
                <div className="field full">
                  <span>Промежуточные остановки</span>
                  <div className="stop-stack">
                    {form.via.map((stop, index) => (
                      <div key={`${stop.id}-${stop.name}-${index}`} className="stop-item">
                        <span className="stop-label">ещё</span>
                        <span>{stop.name}</span>
                        <div className="stop-item-actions">
                          <button type="button" className="btn ghost" disabled={index === 0} onClick={() => moveVia(index, -1)}>
                            ↑
                          </button>
                          <button
                            type="button"
                            className="btn ghost"
                            disabled={index === form.via.length - 1}
                            onClick={() => moveVia(index, 1)}
                          >
                            ↓
                          </button>
                          <button
                            type="button"
                            className="btn ghost"
                            onClick={() => setForm({ ...form, via: form.via.filter((_, i) => i !== index) })}
                          >
                            ×
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                  <div className="picker-row">
                    <input
                      list="transport-stop-catalog"
                      value={form.viaDraft}
                      onChange={(e) => setForm({ ...form, viaDraft: e.target.value })}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          e.preventDefault();
                          addVia();
                        }
                      }}
                      placeholder="Добавить остановку по пути"
                    />
                    <button className="btn secondary" type="button" onClick={addVia}>
                      Добавить
                    </button>
                  </div>
                  <p className="field-hint">Новое имя сохранится в общую базу и подставится в следующих маршрутах.</p>
                </div>
                <div className="field full">
                  <span>Рейсы</span>
                  <div className="time-chips">
                    {form.trips.map((trip, index) => (
                      <span key={`${tripCaption(trip)}-${index}`} className="time-chip">
                        {tripCaption(trip)}
                        <button
                          type="button"
                          aria-label={`Убрать ${tripCaption(trip)}`}
                          onClick={() => setForm({ ...form, trips: form.trips.filter((_, i) => i !== index) })}
                        >
                          ×
                        </button>
                      </span>
                    ))}
                    {!form.trips.length && (
                      <span className="audit-sub">Пока пусто — дни, отправление, прибытие и «Добавить рейс»</span>
                    )}
                  </div>
                  <div className="day-presets">
                    <button
                      type="button"
                      className={`day-pick${sameDays(form.tripDays, ALL_DAYS) ? ' is-on' : ''}`}
                      onClick={() => setForm({ ...form, tripDays: [...ALL_DAYS] })}
                    >
                      Все дни
                    </button>
                    <button
                      type="button"
                      className={`day-pick${sameDays(form.tripDays, WEEKDAY_IDS) ? ' is-on' : ''}`}
                      onClick={() => setForm({ ...form, tripDays: [...WEEKDAY_IDS] })}
                    >
                      Будни
                    </button>
                    <button
                      type="button"
                      className={`day-pick${sameDays(form.tripDays, WEEKEND_IDS) ? ' is-on' : ''}`}
                      onClick={() => setForm({ ...form, tripDays: [...WEEKEND_IDS] })}
                    >
                      Выходные
                    </button>
                  </div>
                  <div className="day-picks">
                    {WEEK_DAYS.map((day) => (
                      <button
                        key={day.id}
                        type="button"
                        className={`day-pick${form.tripDays.includes(day.id) ? ' is-on' : ''}`}
                        onClick={() => toggleTripDay(day.id)}
                      >
                        {day.short}
                      </button>
                    ))}
                  </div>
                  <div className="trip-add">
                    <label className="field">
                      Отправление
                      <input
                        type="time"
                        step={60}
                        value={form.departDraft}
                        onChange={(e) => setForm({ ...form, departDraft: e.target.value })}
                      />
                    </label>
                    <label className="field">
                      Прибытие
                      <input
                        type="time"
                        step={60}
                        value={form.arriveDraft}
                        onChange={(e) => setForm({ ...form, arriveDraft: e.target.value })}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            e.preventDefault();
                            addTrip();
                          }
                        }}
                      />
                    </label>
                    <button className="btn secondary" type="button" onClick={addTrip}>
                      Добавить рейс
                    </button>
                  </div>
                </div>
                <label className="field">
                  Посёлок, село или город
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
                  Краткое описание
                  <input value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
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

function newsPlaceLabel(item: { settlement_name?: string | null; source?: string | null; audience?: string | null }) {
  if (item.settlement_name) return item.settlement_name;
  if (item.audience === 'sakmarsky' || item.source === 'vk') return 'Сакмарский район';
  return 'Вся область';
}

function vkWallLabel(source: string) {
  if (source.includes('ntsk')) return 'Новотроицк.ру';
  if (source.includes('buzuluk')) return 'Бузулук';
  if (source.includes('pb056')) return 'Бугуруслан';
  if (source.includes('orsk')) return 'Орск.ру';
  if (source.includes('orenburg')) return 'Вся область';
  if (source.includes('sakmara')) return 'Сакмарский район';
  return source;
}

function VkNewsPage() {
  const [items, setItems] = useState<VkNewsRun[]>([]);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [openId, setOpenId] = useState<number | null>(null);

  async function load() {
    const data = await api<{ items: VkNewsRun[]; total: number }>('/admin/vk-news/runs?limit=40');
    setItems(data.items || []);
    setTotal(data.total || 0);
  }

  useEffect(() => {
    load().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  async function runNow() {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await api('/admin/vk-news/sync', { method: 'POST' });
      await load();
      pushToast('Проверка ВК закончилась — смотрите лог ниже');
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
          <h1>Новости из ВК</h1>
          <p>
            Каждые 30 минут скрипт смотрит стены:{' '}
            <a href="https://vk.ru/sakmaraadm" target="_blank" rel="noreferrer">
              vk.ru/sakmaraadm
            </a>
            {' — Сакмарский район, '}
            <a href="https://vk.ru/orenburg_vk" target="_blank" rel="noreferrer">
              vk.ru/orenburg_vk
            </a>
            {' — вся область, '}
            <a href="https://vk.ru/orskdotru" target="_blank" rel="noreferrer">
              vk.ru/orskdotru
            </a>
            {' — Орск.ру, '}
            <a href="https://vk.ru/ntskdotru" target="_blank" rel="noreferrer">
              vk.ru/ntskdotru
            </a>
            {' — Новотроицк.ру, '}
            <a href="https://vk.ru/buzuluk_town" target="_blank" rel="noreferrer">
              vk.ru/buzuluk_town
            </a>
            {' — Бузулук (город и район), '}
            <a href="https://vk.ru/pb056" target="_blank" rel="noreferrer">
              vk.ru/pb056
            </a>{' '}
            — Бугуруслан (город и район). Чужие регионы и похожие новости пропускает.
            Ключ нужен от человека (пользователя ВК), не от сообщества.
          </p>
        </div>
        <button className="btn" type="button" disabled={busy} onClick={runNow}>
          {busy ? 'Проверяю…' : 'Проверить сейчас'}
        </button>
      </div>
      {error && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Когда</th>
              <th>Откуда</th>
              <th>Кто запустил</th>
              <th>Итог</th>
              <th>Взял / новые / уже были</th>
              <th>Фото</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id} className="dir-row" onClick={() => setOpenId(openId === item.id ? null : item.id)}>
                <td className="audit-when">{formatAuditWhen(item.started_at)}</td>
                <td className="audit-obj">{vkWallLabel(item.source)}</td>
                <td className="audit-obj">{item.triggered_by === 'timer' ? 'по расписанию' : item.triggered_by}</td>
                <td>
                  {item.status === 'ok' ? <span className="chip ok">Готово</span> : <span className="chip warn">Сбой</span>}
                </td>
                <td>
                  {item.fetched} / {item.created} / {item.skipped}
                </td>
                <td>{item.photos}</td>
                <td>{openId === item.id ? 'скрыть' : 'подробнее'}</td>
              </tr>
            ))}
            {openId != null &&
              items
                .filter((x) => x.id === openId)
                .map((item) => (
                  <tr key={`d-${item.id}`}>
                    <td colSpan={7}>
                      <div className="audit-sub" style={{ whiteSpace: 'pre-wrap' }}>
                        Источник: {item.source}
                        {'\n'}
                        {item.error ? `Ошибка: ${item.error}\n` : ''}
                        {item.details || 'Нет подробностей'}
                      </div>
                    </td>
                  </tr>
                ))}
            {!items.length && (
              <tr>
                <td colSpan={7} className="empty">
                  Пока не запускали. Нажмите «Проверить сейчас» — возьмёт свежие посты, в том числе последний.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <p className="audit-sub">Всего запусков: {total}</p>
    </div>
  );
}

const EMPTY_NEWS: NewsForm = {
  title: '',
  body: '',
  settlement_id: '',
  is_published: true,
  is_pinned: false,
};

function NewsPage() {
  const [searchParams] = useSearchParams();
  const idParam = searchParams.get('id');
  const openedFromUrl = useRef<string | null>(null);
  const [items, setItems] = useState<NewsItem[]>([]);
  const [total, setTotal] = useState(0);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [form, setForm] = useState<NewsForm>(EMPTY_NEWS);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [appliedQ, setAppliedQ] = useState('');
  const [publishedFilter, setPublishedFilter] = useState<'all' | 'published' | 'hidden'>('all');
  const [photoFiles, setPhotoFiles] = useState<File[]>([]);
  const [editingPhotos, setEditingPhotos] = useState<NonNullable<NewsItem['photos']>>([]);
  const [page, setPage] = useState(1);
  const NEWS_PAGE = 25;
  const pageCount = Math.max(1, Math.ceil(total / NEWS_PAGE));
  const safePage = Math.min(page, pageCount);

  async function loadSettlements() {
    setSettlements(await api<Settlement[]>('/settlements'));
  }

  async function load(nextPage = safePage) {
    const params = new URLSearchParams();
    params.set('limit', String(NEWS_PAGE));
    params.set('offset', String((nextPage - 1) * NEWS_PAGE));
    if (appliedQ.trim()) params.set('q', appliedQ.trim());
    if (publishedFilter === 'published') params.set('published', 'true');
    if (publishedFilter === 'hidden') params.set('published', 'false');
    const data = await api<{ items: NewsItem[]; total: number }>(`/news?${params}`);
    setItems(data.items || []);
    setTotal(data.total || 0);
  }

  useEffect(() => {
    loadSettlements().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  useEffect(() => {
    load(safePage).catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [safePage, appliedQ, publishedFilter]);

  useEffect(() => {
    setPage(1);
  }, [appliedQ, publishedFilter]);

  useEffect(() => {
    if (page !== safePage) setPage(safePage);
  }, [page, safePage]);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_NEWS);
    setPhotoFiles([]);
    setEditingPhotos([]);
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
    setPhotoFiles([]);
    setEditingPhotos(item.photos || []);
    setError('');
    setModalOpen(true);
  }

  useEffect(() => {
    if (!idParam) {
      openedFromUrl.current = null;
      return;
    }
    if (openedFromUrl.current === idParam) return;
    const id = Number(idParam);
    if (!Number.isFinite(id)) return;
    const found = items.find((x) => x.id === id);
    if (found) {
      openedFromUrl.current = idParam;
      startEdit(found);
      return;
    }
    api<NewsItem>(`/news/${id}`)
      .then((item) => {
        openedFromUrl.current = idParam;
        startEdit(item);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [idParam, items]);

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
      if (photoFiles.length && id) {
        const fd = new FormData();
        photoFiles.forEach((f) => fd.append('files', f));
        await api(`/news/${id}/photos`, { method: 'POST', body: fd });
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
    try {
      await api(`/news/${id}`, { method: 'DELETE' });
      if (editingId === id) closeModal();
      await load();
      pushToast('Новость удалена');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Новости</h1>
          <p>Новости области и Сакмарского района для ленты приложения</p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить новость
        </button>
      </div>
      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setAppliedQ(query);
        }}
      >
        <input placeholder="Заголовок, текст…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select
          value={publishedFilter}
          onChange={(e) => {
            setPage(1);
            setPublishedFilter(e.target.value as 'all' | 'published' | 'hidden');
          }}
        >
          <option value="all">Все статусы</option>
          <option value="published">Опубликованные</option>
          <option value="hidden">Скрытые</option>
        </select>
        <button className="btn" type="submit">
          Найти
        </button>
      </form>
      {error && !modalOpen && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Новость</th>
              <th>Посёлок, село, город</th>
              <th>Дата</th>
              <th>Статус</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id} className="dir-row" onClick={() => startEdit(item)}>
                <td>
                  <div className="audit-who">{item.title}</div>
                  <div className="audit-sub">
                    {item.source === 'vk' ? 'из ВК, Сакмарский район · ' : ''}
                    {item.source === 'vk_oblast' ? 'из ВК, вся область · ' : ''}
                    {item.is_pinned ? 'закреплена · ' : ''}
                    {item.body.length > 90 ? `${item.body.slice(0, 90)}…` : item.body}
                  </div>
                </td>
                <td className="audit-obj">{newsPlaceLabel(item)}</td>
                <td className="audit-when">{formatAuditWhen(item.published_at || item.created_at)}</td>
                <td>
                  {item.is_published ? <span className="chip ok">В приложении</span> : <span className="chip warn">Скрыто</span>}
                </td>
                <td onClick={(e) => e.stopPropagation()}>
                  <div className="actions inline">
                    <button className="btn" type="button" onClick={() => startEdit(item)}>
                      Изменить
                    </button>
                    <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                      Удалить
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {!items.length && (
              <tr>
                <td colSpan={5} className="empty">
                  {appliedQ || publishedFilter !== 'all' ? 'Ничего не найдено' : 'Новостей пока нет — нажмите «Добавить новость»'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={total} onPage={setPage} />

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
                  Посёлок, село или город
                  <select
                    value={form.settlement_id === '' ? '' : String(form.settlement_id)}
                    onChange={(e) =>
                      setForm({ ...form, settlement_id: e.target.value ? Number(e.target.value) : '' })
                    }
                  >
                    <option value="">Вся область</option>
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
                  Фото (можно несколько)
                  <input
                    type="file"
                    accept="image/*"
                    multiple
                    onChange={(e) => setPhotoFiles(Array.from(e.target.files || []))}
                  />
                </label>
                {!!editingPhotos.length && (
                  <div className="field full">
                    <div className="audit-sub">Уже в новости — нажмите «убрать», если лишнее</div>
                    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 8 }}>
                      {editingPhotos.map((p) => (
                        <div key={p.id} style={{ position: 'relative' }}>
                          <img
                            src={mediaUrl(p.url)}
                            alt=""
                            style={{ width: 96, height: 72, objectFit: 'cover', borderRadius: 8, border: '1px solid var(--line)' }}
                          />
                          {editingId && p.id > 0 && (
                            <button
                              className="btn danger"
                              type="button"
                              style={{ marginTop: 4 }}
                              onClick={async () => {
                                if (!editingId) return;
                                try {
                                  const updated = await api<NewsItem>(`/news/${editingId}/photos/${p.id}`, { method: 'DELETE' });
                                  setEditingPhotos(updated.photos || []);
                                  pushToast('Фото убрано');
                                } catch (err) {
                                  setError(err instanceof Error ? err.message : 'Ошибка');
                                }
                              }}
                            >
                              Убрать
                            </button>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
                {!!photoFiles.length && (
                  <div className="audit-sub field full">К сохранению: {photoFiles.length} новых фото</div>
                )}
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
  settlement_ids: number[];
};

const EMPTY_ALERT: AlertForm = {
  message: '',
  kind: 'info',
  priority: 0,
  is_active: true,
  starts_at: '',
  ends_at: '',
  settlement_ids: [],
};

const ALERT_CITY_HINTS = [
  'Оренбург',
  'Орск',
  'Новотроицк',
  'Бузулук',
  'Бугуруслан',
  'Гай',
  'Медногорск',
  'Сорочинск',
  'Кувандык',
  'Соль-Илецк',
  'Сакмара',
];

function alertPlacesLabel(item: DistrictAlert) {
  const names = item.settlement_names || [];
  if (!names.length && !(item.settlement_ids || []).length) return 'Вся область';
  if (names.length <= 2) return names.join(', ') || `${(item.settlement_ids || []).length} мест`;
  return `${names.slice(0, 2).join(', ')} и ещё ${names.length - 2}`;
}

function alertPeriod(item: DistrictAlert) {
  const start = item.starts_at ? formatAuditWhen(item.starts_at) : '';
  const end = item.ends_at ? formatAuditWhen(item.ends_at) : '';
  if (start && end) return `${start} — ${end}`;
  if (start) return `с ${start}`;
  if (end) return `до ${end}`;
  return 'без срока';
}

const BROADCAST_KINDS: { id: 'news' | 'promo' | 'question' | 'info'; label: string; title: string }[] = [
  { id: 'news', label: 'Новость', title: 'Новость района' },
  { id: 'promo', label: 'Акция', title: 'Акция' },
  { id: 'question', label: 'Вопрос', title: 'Вопрос к жителям' },
  { id: 'info', label: 'Сообщение', title: 'Рядом56' },
];

const BROADCAST_AUDIENCES: { id: 'all' | 'users' | 'guests'; label: string; sendLabel: string }[] = [
  { id: 'all', label: 'Всем', sendLabel: 'Отправить всем' },
  { id: 'users', label: 'С аккаунтом', sendLabel: 'Отправить с аккаунтом' },
  { id: 'guests', label: 'Гостям', sendLabel: 'Отправить гостям' },
];

function BroadcastPage() {
  const [kind, setKind] = useState<(typeof BROADCAST_KINDS)[number]['id']>('news');
  const [audience, setAudience] = useState<(typeof BROADCAST_AUDIENCES)[number]['id']>('all');
  const [title, setTitle] = useState('Новость района');
  const [body, setBody] = useState('');
  const [people, setPeople] = useState(0);
  const [devices, setDevices] = useState(0);
  const [userDevices, setUserDevices] = useState(0);
  const [guestDevices, setGuestDevices] = useState(0);
  const [history, setHistory] = useState<AuditLog[]>([]);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function loadMeta() {
    const [preview, log] = await Promise.all([
      api<{ people: number; devices: number; user_devices?: number; guest_devices?: number }>('/admin/broadcast'),
      api<{ items: AuditLog[] }>('/admin/audit-log?entity_type=broadcast&limit=20'),
    ]);
    setPeople(preview.people || 0);
    setDevices(preview.devices || 0);
    setUserDevices(preview.user_devices ?? Math.max(0, (preview.devices || 0) - (preview.guest_devices || 0)));
    setGuestDevices(preview.guest_devices || 0);
    setHistory(log.items || []);
  }

  useEffect(() => {
    loadMeta().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  function pickKind(next: (typeof BROADCAST_KINDS)[number]['id']) {
    const prevTitle = BROADCAST_KINDS.find((k) => k.id === kind)?.title || '';
    const nextTitle = BROADCAST_KINDS.find((k) => k.id === next)?.title || 'Рядом56';
    setKind(next);
    if (!title.trim() || title.trim() === prevTitle) setTitle(nextTitle);
  }

  const audienceMeta = BROADCAST_AUDIENCES.find((a) => a.id === audience) || BROADCAST_AUDIENCES[0];
  const audienceDevices =
    audience === 'users' ? userDevices : audience === 'guests' ? guestDevices : devices;
  const canSend =
    audience === 'users' ? people > 0 || userDevices > 0 : audience === 'guests' ? guestDevices > 0 : devices > 0 || people > 0;

  async function send() {
    const text = body.trim();
    if (text.length < 3) {
      setError('Напишите текст — хотя бы пару слов');
      return;
    }
    let confirmText = '';
    if (audience === 'users') {
      confirmText = `Отправить с аккаунтом?\nКолокольчик: ${people} чел., пуш примерно на ${userDevices} телефон(ов).`;
    } else if (audience === 'guests') {
      confirmText = `Отправить гостям без входа?\nПуш примерно на ${guestDevices} телефон(ов). В колокольчик не попадёт.`;
    } else {
      confirmText = `Отправить всем?\nКолокольчик: ${people} чел., пуш примерно на ${devices} телефон(ов) (${userDevices} с аккаунтом, ${guestDevices} гостей).`;
    }
    const ok = await confirmAction(confirmText);
    if (!ok) return;
    setBusy(true);
    setError('');
    try {
      const res = await api<{ message?: string }>('/admin/broadcast', {
        method: 'POST',
        body: JSON.stringify({ kind, audience, title: title.trim(), body: text }),
      });
      setBody('');
      pushToast(res.message || 'Отправлено');
      await loadMeta();
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Ошибка';
      setError(msg);
      pushToast(msg);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>На телефоны</h1>
          <p>
            Новость, акция или вопрос — на телефон пушем. Можно выбрать: всем, только с аккаунтом или только гостям
            без входа. У зарегистрированных ещё попадёт в колокольчик. Баннер на весь экран — в разделе «Срочное».
          </p>
        </div>
      </div>

      <div className="panel" style={{ marginBottom: 16 }}>
        <p className="muted" style={{ margin: '0 0 12px' }}>
          С аккаунтом: <strong>{people}</strong> чел., пуш на <strong>{userDevices}</strong> телефон(ов). Гости без
          входа: <strong>{guestDevices}</strong> телефон(ов).
          {audience === 'users' ? (
            <>
              {' '}
              Сейчас выбрано: только аккаунты — пуш на <strong>{audienceDevices}</strong> телефон(ов).
            </>
          ) : audience === 'guests' ? (
            <>
              {' '}
              Сейчас выбрано: только гости — пуш на <strong>{audienceDevices}</strong> телефон(ов).
            </>
          ) : (
            <>
              {' '}
              Сейчас выбрано: всем — пуш на <strong>{audienceDevices}</strong> телефон(ов).
            </>
          )}
        </p>
        <p className="muted" style={{ margin: '0 0 12px', fontSize: 13 }}>
          Кому отправить
        </p>
        <div className="toolbar compact" style={{ marginBottom: 12 }}>
          {BROADCAST_AUDIENCES.map((item) => (
            <button
              key={item.id}
              type="button"
              className={audience === item.id ? 'btn' : 'btn ghost'}
              onClick={() => setAudience(item.id)}
            >
              {item.label}
            </button>
          ))}
        </div>
        <p className="muted" style={{ margin: '0 0 12px', fontSize: 13 }}>
          Тип сообщения
        </p>
        <div className="toolbar compact" style={{ marginBottom: 12 }}>
          {BROADCAST_KINDS.map((item) => (
            <button
              key={item.id}
              type="button"
              className={kind === item.id ? 'btn' : 'btn ghost'}
              onClick={() => pickKind(item.id)}
            >
              {item.label}
            </button>
          ))}
        </div>
        <label className="field">
          Заголовок на телефоне
          <input maxLength={80} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Рядом56" />
        </label>
        <label className="field" style={{ marginTop: 10 }}>
          Текст
          <textarea
            rows={4}
            maxLength={400}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder={
              kind === 'question'
                ? 'Например: удобно ли вам рейс в 7:00? Напишите в приложении'
                : kind === 'promo'
                  ? 'Что за акция, до какой даты, где смотреть'
                  : 'Коротко, простыми словами'
            }
          />
        </label>
        <p className="muted" style={{ margin: '8px 0 0' }}>
          {body.length} / 400
        </p>
        {error && <p className="error">{error}</p>}
        <div className="modal-actions" style={{ marginTop: 16 }}>
          <button className="btn" type="button" disabled={busy || !canSend} onClick={() => send().catch(console.error)}>
            {busy ? 'Отправляем… подождите' : audienceMeta.sendLabel}
          </button>
        </div>
      </div>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Когда</th>
              <th>Кто</th>
              <th>Что отправили</th>
            </tr>
          </thead>
          <tbody>
            {history.map((row) => (
              <tr key={row.id}>
                <td className="audit-when">{formatAuditWhen(row.created_at)}</td>
                <td className="audit-who">{row.actor_name || '—'}</td>
                <td className="audit-details">{row.details || '—'}</td>
              </tr>
            ))}
            {!history.length && (
              <tr>
                <td colSpan={3} className="empty">
                  Пока никому разом не писали
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

const RIDES_PAGE_SIZE = 25;

function rideKindLabel(kind: string) {
  return kind === 'need' ? 'Ищу' : 'Еду';
}

function rideStatusLabel(status: string) {
  if (status === 'open') return 'открыта';
  if (status === 'hidden') return 'скрыта';
  return 'снята';
}

function RidesPage() {
  const [items, setItems] = useState<Ride[]>([]);
  const [total, setTotal] = useState(0);
  const [query, setQuery] = useState('');
  const [appliedQ, setAppliedQ] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'open' | 'closed' | 'hidden'>('open');
  const [page, setPage] = useState(1);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const pageCount = Math.max(1, Math.ceil(total / RIDES_PAGE_SIZE));
  const safePage = Math.min(page, pageCount);

  async function load(nextPage = safePage) {
    const params = new URLSearchParams();
    params.set('limit', String(RIDES_PAGE_SIZE));
    params.set('offset', String((nextPage - 1) * RIDES_PAGE_SIZE));
    if (appliedQ.trim()) params.set('q', appliedQ.trim());
    if (statusFilter !== 'all') params.set('status', statusFilter);
    const data = await api<{ items: Ride[]; total: number }>(`/rides/admin?${params}`);
    setItems(data.items || []);
    setTotal(data.total || 0);
  }

  useEffect(() => {
    load(safePage).catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [safePage, appliedQ, statusFilter]);

  useEffect(() => {
    setPage(1);
  }, [appliedQ, statusFilter]);

  async function hideRide(id: number) {
    if (!window.confirm('Скрыть эту попутку из ленты?')) return;
    setBusy(true);
    setError('');
    try {
      await api(`/rides/${id}/hide`, { method: 'POST' });
      await load(safePage);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function removeRide(id: number) {
    if (!window.confirm('Удалить попутку совсем?')) return;
    setBusy(true);
    setError('');
    try {
      await api(`/rides/${id}`, { method: 'DELETE' });
      await load(safePage);
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
          <h1>Попутки</h1>
          <p>Кто едет и кто ищет место. Модерации перед публикацией нет — при жалобе скрывайте.</p>
        </div>
      </div>
      <form
        className="toolbar compact"
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setAppliedQ(query);
        }}
      >
        <input placeholder="Имя, телефон, комментарий…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select
          value={statusFilter}
          onChange={(e) => {
            setPage(1);
            setStatusFilter(e.target.value as 'all' | 'open' | 'closed' | 'hidden');
          }}
        >
          <option value="open">Открытые</option>
          <option value="closed">Снятые</option>
          <option value="hidden">Скрытые</option>
          <option value="all">Все</option>
        </select>
        <button className="btn" type="submit">
          Найти
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Маршрут</th>
              <th>Когда</th>
              <th>Кто</th>
              <th>Статус</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id}>
                <td>
                  <div className="audit-who">
                    {rideKindLabel(item.kind)} · {item.title}
                  </div>
                  <div className="audit-sub">
                    {item.kind === 'need' ? `${item.seats} чел.` : `${item.seats} мест.`}
                    {item.note ? ` · ${item.note}` : ''}
                  </div>
                </td>
                <td className="audit-when">{formatDate(item.depart_at)}</td>
                <td>
                  <div className="audit-who">{item.author_name || `user #${item.author_id}`}</div>
                  <div className="audit-sub">{item.contact_phone || '—'}</div>
                </td>
                <td>
                  <span className={item.status === 'open' ? 'chip ok' : 'chip neutral'}>{rideStatusLabel(item.status)}</span>
                </td>
                <td>
                  {item.status !== 'hidden' && (
                    <button className="btn ghost" type="button" disabled={busy} onClick={() => hideRide(item.id)}>
                      Скрыть
                    </button>
                  )}
                  <button className="btn ghost" type="button" disabled={busy} onClick={() => removeRide(item.id)}>
                    Удалить
                  </button>
                </td>
              </tr>
            ))}
            {!items.length && (
              <tr>
                <td colSpan={5} className="empty">
                  Попуток пока нет
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={safePage} pageCount={pageCount} total={total} onPage={setPage} />
    </div>
  );
}

function AlertsPage() {
  const [searchParams] = useSearchParams();
  const idParam = searchParams.get('id');
  const openedFromUrl = useRef<string | null>(null);
  const [items, setItems] = useState<DistrictAlert[]>([]);
  const [history, setHistory] = useState<DistrictAlert[]>([]);
  const [tab, setTab] = useState<'active' | 'history'>('active');
  const [form, setForm] = useState<AlertForm>(EMPTY_ALERT);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [page, setPage] = useState(1);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [placeQuery, setPlaceQuery] = useState('');
  const ALERT_PAGE = 25;

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
    api<Settlement[]>('/settlements')
      .then(setSettlements)
      .catch(() => setSettlements([]));
  }, []);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_ALERT);
    setPlaceQuery('');
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
      settlement_ids: item.settlement_ids || [],
    });
    setPlaceQuery('');
    setError('');
    setModalOpen(true);
  }

  useEffect(() => {
    if (!idParam) {
      openedFromUrl.current = null;
      return;
    }
    if (openedFromUrl.current === idParam) return;
    const id = Number(idParam);
    if (!Number.isFinite(id)) return;
    const found = [...items, ...history].find((x) => x.id === id);
    if (found) {
      openedFromUrl.current = idParam;
      startEdit(found);
      return;
    }
    api<DistrictAlert>(`/alerts/${id}`)
      .then((item) => {
        openedFromUrl.current = idParam;
        startEdit(item);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, [idParam, items, history]);

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
      settlement_ids: form.settlement_ids,
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
    try {
      await api(`/alerts/${id}`, { method: 'DELETE' });
      if (editingId === id) closeModal();
      await load();
      pushToast('Объявление удалено');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  const shown = tab === 'history' ? history : items;
  const alertPageCount = Math.max(1, Math.ceil(shown.length / ALERT_PAGE));
  const alertSafePage = Math.min(page, alertPageCount);
  const alertPageItems = shown.slice((alertSafePage - 1) * ALERT_PAGE, alertSafePage * ALERT_PAGE);

  useEffect(() => {
    setPage(1);
  }, [tab]);

  useEffect(() => {
    if (page !== alertSafePage) setPage(alertSafePage);
  }, [page, alertSafePage]);

  function kindChip(kind: string) {
    if (kind === 'danger') return 'chip danger';
    if (kind === 'warn') return 'chip warn';
    return 'chip ok';
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Срочное</h1>
          <p>
            {tab === 'history'
              ? 'Выключенные, прошедшие и ещё не начавшиеся баннеры'
              : 'Сейчас показываются в приложении. Можно всей области или выбранным городам, сёлам и посёлкам'}
          </p>
        </div>
        <button className="btn" type="button" onClick={openCreate}>
          Добавить объявление
        </button>
      </div>
      <div className="toolbar compact">
        <button type="button" className={`btn ${tab === 'active' ? '' : 'secondary'}`} onClick={() => setTab('active')}>
          Текущие
        </button>
        <button type="button" className={`btn ${tab === 'history' ? '' : 'secondary'}`} onClick={() => setTab('history')}>
          История
        </button>
      </div>
      {error && !modalOpen && <p className="error">{error}</p>}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Текст</th>
              <th>Где</th>
              <th>Тип</th>
              <th>Период</th>
              <th>Статус</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {alertPageItems.map((item) => (
              <tr key={item.id} className="dir-row" onClick={() => startEdit(item)}>
                <td>
                  <div className="audit-who">{item.message}</div>
                  <div className="audit-sub">приоритет {item.priority ?? 0}</div>
                </td>
                <td className="audit-details">{alertPlacesLabel(item)}</td>
                <td>
                  <span className={kindChip(item.kind)}>{ALERT_KIND_LABELS[item.kind] || item.kind}</span>
                </td>
                <td className="audit-details">
                  {alertPeriod(item)}
                  <div className="audit-sub">обновлено {formatAuditWhen(item.updated_at)}</div>
                </td>
                <td>
                  {item.is_active ? <span className="chip ok">В приложении</span> : <span className="chip warn">Выкл.</span>}
                </td>
                <td onClick={(e) => e.stopPropagation()}>
                  <div className="actions inline">
                    <button className="btn" type="button" onClick={() => startEdit(item)}>
                      Изменить
                    </button>
                    <button className="btn danger" type="button" onClick={() => remove(item.id)}>
                      Удалить
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {!shown.length && (
              <tr>
                <td colSpan={6} className="empty">
                  {tab === 'history' ? 'История пуста' : 'Срочных объявлений пока нет — нажмите «Добавить объявление»'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pager page={alertSafePage} pageCount={alertPageCount} total={shown.length} onPage={setPage} />

      {modalOpen && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: 'min(640px, 100%)' }}>
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
                <div className="field full">
                  Кому показывать
                  <div className="toolbar compact" style={{ marginTop: 8 }}>
                    <button
                      type="button"
                      className={form.settlement_ids.length === 0 ? 'btn' : 'btn ghost'}
                      onClick={() => setForm({ ...form, settlement_ids: [] })}
                    >
                      Вся область
                    </button>
                    <button
                      type="button"
                      className={form.settlement_ids.length > 0 ? 'btn' : 'btn ghost'}
                      onClick={() => {
                        if (form.settlement_ids.length === 0) setPlaceQuery('Оренбург');
                      }}
                    >
                      Выбранные места
                    </button>
                  </div>
                  <p className="muted" style={{ margin: '8px 0 0', fontSize: 13 }}>
                    {form.settlement_ids.length === 0
                      ? 'Увидят все, у кого открыто приложение.'
                      : `Только ${form.settlement_ids.length} ${form.settlement_ids.length === 1 ? 'место' : 'мест'}. Остальные не увидят баннер и не получат пуш.`}
                  </p>
                  <div className="toolbar compact" style={{ marginTop: 8, flexWrap: 'wrap' }}>
                    {ALERT_CITY_HINTS.map((hint) => {
                      const found = settlements.find((s) => {
                        const name = (s.name || '').toLowerCase();
                        const display = (s.display_name || '').toLowerCase();
                        const h = hint.toLowerCase();
                        return name === h || display === h || display.startsWith(`${h},`) || display.startsWith(`${h} `);
                      });
                      if (!found) return null;
                      const on = form.settlement_ids.includes(found.id);
                      return (
                        <button
                          key={hint}
                          type="button"
                          className={on ? 'btn' : 'btn ghost'}
                          onClick={() =>
                            setForm({
                              ...form,
                              settlement_ids: on
                                ? form.settlement_ids.filter((id) => id !== found.id)
                                : [...form.settlement_ids, found.id],
                            })
                          }
                        >
                          {hint}
                        </button>
                      );
                    })}
                  </div>
                  {form.settlement_ids.length > 0 && (
                    <div style={{ marginTop: 10 }}>
                      {form.settlement_ids.map((id) => {
                        const place = settlements.find((s) => s.id === id);
                        return (
                          <span key={id} className="chip ok" style={{ margin: '0 6px 6px 0' }}>
                            {place?.display_name || `#${id}`}
                            <button
                              type="button"
                              className="btn ghost"
                              style={{ marginLeft: 6, padding: '0 6px' }}
                              onClick={() =>
                                setForm({ ...form, settlement_ids: form.settlement_ids.filter((x) => x !== id) })
                              }
                            >
                              ×
                            </button>
                          </span>
                        );
                      })}
                    </div>
                  )}
                  <input
                    style={{ marginTop: 10 }}
                    value={placeQuery}
                    onChange={(e) => setPlaceQuery(e.target.value)}
                    placeholder="Найти посёлок, село или город"
                  />
                  {placeQuery.trim().length >= 2 && (
                    <div className="table-wrap" style={{ marginTop: 8, maxHeight: 180, overflow: 'auto' }}>
                      {settlements
                        .filter((s) => {
                          if (form.settlement_ids.includes(s.id)) return false;
                          const q = placeQuery.trim().toLowerCase();
                          return (
                            (s.display_name || '').toLowerCase().includes(q) ||
                            (s.name || '').toLowerCase().includes(q)
                          );
                        })
                        .slice(0, 12)
                        .map((s) => (
                          <button
                            key={s.id}
                            type="button"
                            className="btn ghost"
                            style={{ display: 'block', width: '100%', textAlign: 'left', marginBottom: 4 }}
                            onClick={() => {
                              setForm({ ...form, settlement_ids: [...form.settlement_ids, s.id] });
                              setPlaceQuery('');
                            }}
                          >
                            {s.display_name}
                          </button>
                        ))}
                    </div>
                  )}
                </div>
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

type CalKind = 'event' | 'news' | 'alert';

type CalEntry = {
  id: string;
  kind: CalKind;
  dateKey: string;
  sort: string;
  title: string;
  time: string;
  place: string;
  status: string;
  statusTone: string;
  note: string;
  href: string;
};

const CAL_MONTHS: Record<string, number> = {
  января: 0,
  февраля: 1,
  марта: 2,
  апреля: 3,
  мая: 4,
  июня: 5,
  июля: 6,
  августа: 7,
  сентября: 8,
  октября: 9,
  ноября: 10,
  декабря: 11,
};

function dateKeyOf(d: Date) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function formatClockRange(startIso?: string | null, endIso?: string | null) {
  const start = parseApiDate(startIso ?? null);
  if (!start) return '';
  const t1 = `${pad2(start.getHours())}:${pad2(start.getMinutes())}`;
  const end = parseApiDate(endIso ?? null);
  if (!end) return t1;
  return `${t1}–${pad2(end.getHours())}:${pad2(end.getMinutes())}`;
}

function eachDateKey(from: Date, to: Date, cap = 62) {
  const keys: string[] = [];
  const cur = new Date(from.getFullYear(), from.getMonth(), from.getDate());
  const last = new Date(to.getFullYear(), to.getMonth(), to.getDate());
  for (let i = 0; i < cap && cur <= last; i += 1) {
    keys.push(dateKeyOf(cur));
    cur.setDate(cur.getDate() + 1);
  }
  return keys;
}

function eventSeanceEntries(item: EventItem): CalEntry[] {
  const base = parseApiDate(item.starts_at);
  const year = base?.getFullYear() ?? new Date().getFullYear();
  const block = (item.description || '').split(/Источник:/i)[0];
  const re = /(\d{1,2})\s+([а-яё]+),\s*(\d{2}):(\d{2})(?:\s*[–-]\s*(\d{2}):(\d{2}))?/gi;
  const place = [item.place_text, item.settlement_name].filter(Boolean).join(' · ');
  const status = EVENT_STATUS_LABELS[item.status || ''] || (item.is_published ? 'Опубликовано' : 'Черновик');
  const statusTone = item.status === 'published' || item.is_published ? 'ok' : item.status === 'scheduled' ? 'warn' : 'neutral';
  const found: CalEntry[] = [];
  for (const m of block.matchAll(re)) {
    const month = CAL_MONTHS[m[2].toLowerCase()];
    if (month == null) continue;
    const day = Number(m[1]);
    const t1 = `${m[3]}:${m[4]}`;
    const t2 = m[5] && m[6] ? `${m[5]}:${m[6]}` : '';
    const key = `${year}-${pad2(month + 1)}-${pad2(day)}`;
    found.push({
      id: `event-${item.id}-${key}`,
      kind: 'event',
      dateKey: key,
      sort: t1,
      title: item.title,
      time: t2 ? `${t1}–${t2}` : t1,
      place,
      status,
      statusTone,
      note: item.address || '',
      href: `/events?id=${item.id}`,
    });
  }
  if (found.length) return found;
  if (!base) return [];
  return [
    {
      id: `event-${item.id}-${localDateKey(item.starts_at)}`,
      kind: 'event',
      dateKey: localDateKey(item.starts_at),
      sort: formatClockRange(item.starts_at, item.ends_at) || '99:99',
      title: item.title,
      time: formatClockRange(item.starts_at, item.ends_at),
      place,
      status,
      statusTone,
      note: item.address || '',
      href: `/events?id=${item.id}`,
    },
  ];
}

function buildCalendarEntries(events: EventItem[], news: NewsItem[], alerts: DistrictAlert[]): CalEntry[] {
  const out: CalEntry[] = [];
  for (const item of events) out.push(...eventSeanceEntries(item));
  for (const item of news) {
    const when = item.published_at || item.created_at;
    const key = localDateKey(when);
    if (!key) continue;
    out.push({
      id: `news-${item.id}`,
      kind: 'news',
      dateKey: key,
      sort: formatClockRange(when) || '99:99',
      title: item.title,
      time: formatClockRange(when),
      place: newsPlaceLabel(item),
      status: item.is_published ? (item.is_pinned ? 'Закреплена' : 'Опубликована') : 'Черновик',
      statusTone: item.is_published ? 'ok' : 'neutral',
      note: (item.body || '').replace(/\s+/g, ' ').slice(0, 180),
      href: `/news?id=${item.id}`,
    });
  }
  for (const item of alerts) {
    const start = parseApiDate(item.starts_at || item.created_at);
    if (!start) continue;
    const end = parseApiDate(item.ends_at || item.starts_at || item.created_at) || start;
    const kindLabel = item.kind === 'danger' ? 'Тревога' : item.kind === 'warn' ? 'Важно' : 'Инфо';
    for (const key of eachDateKey(start, end)) {
      out.push({
        id: `alert-${item.id}-${key}`,
        kind: 'alert',
        dateKey: key,
        sort: formatClockRange(item.starts_at) || '00:00',
        title: item.message,
        time: formatClockRange(item.starts_at, item.ends_at) || 'весь день',
        place: kindLabel,
        status: item.is_active ? 'Активно' : 'Выключено',
        statusTone: item.is_active ? (item.kind === 'danger' ? 'danger' : 'warn') : 'neutral',
        note: '',
        href: `/alerts?id=${item.id}`,
      });
    }
  }
  return out.sort((a, b) => a.sort.localeCompare(b.sort) || a.title.localeCompare(b.title, 'ru'));
}

const CAL_KIND_LABEL: Record<CalKind, string> = {
  event: 'Афиша',
  news: 'Новость',
  alert: 'Срочное',
};

function EditorialCalendarPage() {
  const navigate = useNavigate();
  const now = new Date();
  const [month, setMonth] = useState(() => new Date(now.getFullYear(), now.getMonth(), 1));
  const [events, setEvents] = useState<EventItem[]>([]);
  const [news, setNews] = useState<NewsItem[]>([]);
  const [alerts, setAlerts] = useState<DistrictAlert[]>([]);
  const [error, setError] = useState('');
  const [kindFilter, setKindFilter] = useState<'all' | CalKind>('all');
  const [selectedDay, setSelectedDay] = useState(now.getDate());

  useEffect(() => {
    Promise.all([
      api<EventItem[] | { items: EventItem[] }>('/events?limit=500'),
      api<NewsItem[] | { items: NewsItem[] }>('/news?limit=500'),
      api<DistrictAlert[]>('/alerts'),
    ])
      .then(([ev, n, a]) => {
        setEvents(asItems(ev));
        setNews(asItems(n));
        setAlerts(a);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  const year = month.getFullYear();
  const mon = month.getMonth();
  const daysInMonth = new Date(year, mon + 1, 0).getDate();
  const startWeekday = (new Date(year, mon, 1).getDay() + 6) % 7;
  const isCurrentMonth = year === now.getFullYear() && mon === now.getMonth();
  const todayKey = dateKeyOf(now);
  const safeDay = Math.min(selectedDay, daysInMonth);
  const selectedKey = `${year}-${pad2(mon + 1)}-${pad2(safeDay)}`;

  useEffect(() => {
    if (isCurrentMonth) setSelectedDay(now.getDate());
    else setSelectedDay(1);
  }, [year, mon]);

  const entries = useMemo(() => buildCalendarEntries(events, news, alerts), [events, news, alerts]);
  const visible = kindFilter === 'all' ? entries : entries.filter((e) => e.kind === kindFilter);
  const byDay = useMemo(() => {
    const map = new Map<string, CalEntry[]>();
    for (const row of visible) {
      const list = map.get(row.dateKey);
      if (list) list.push(row);
      else map.set(row.dateKey, [row]);
    }
    return map;
  }, [visible]);

  const selectedItems = byDay.get(selectedKey) || [];
  const monthPrefix = `${year}-${pad2(mon + 1)}-`;
  const monthItems = visible.filter((e) => e.dateKey.startsWith(monthPrefix));
  const monthCounts = {
    event: monthItems.filter((e) => e.kind === 'event').length,
    news: monthItems.filter((e) => e.kind === 'news').length,
    alert: monthItems.filter((e) => e.kind === 'alert').length,
  };

  function goToday() {
    setMonth(new Date(now.getFullYear(), now.getMonth(), 1));
    setSelectedDay(now.getDate());
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Календарь</h1>
          <p>
            {monthCounts.event} в афише · {monthCounts.news} новостей · {monthCounts.alert} срочных
          </p>
        </div>
        <div className="toolbar compact" style={{ margin: 0 }}>
          <button type="button" className="btn secondary" onClick={() => setMonth(new Date(year, mon - 1, 1))}>
            ←
          </button>
          <strong style={{ textTransform: 'capitalize', minWidth: 160, textAlign: 'center' }}>
            {month.toLocaleDateString('ru-RU', { month: 'long', year: 'numeric' })}
          </strong>
          <button type="button" className="btn secondary" onClick={() => setMonth(new Date(year, mon + 1, 1))}>
            →
          </button>
          <button type="button" className="btn ghost" onClick={goToday}>
            Сегодня
          </button>
        </div>
      </div>
      <div className="cal-legend">
        {(['all', 'event', 'news', 'alert'] as const).map((k) => (
          <button
            key={k}
            type="button"
            className={`cal-legend-btn ${k}${kindFilter === k ? ' is-on' : ''}`}
            onClick={() => setKindFilter(k)}
          >
            {k === 'all' ? 'Всё' : CAL_KIND_LABEL[k]}
          </button>
        ))}
      </div>
      {error && <p className="error">{error}</p>}
      <div className="cal-layout">
        <div className="cal-grid">
          {['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'].map((d) => (
            <div key={d} className="cal-dow">
              {d}
            </div>
          ))}
          {Array.from({ length: startWeekday }).map((_, i) => (
            <div key={`pad-${i}`} />
          ))}
          {Array.from({ length: daysInMonth }).map((_, i) => {
            const day = i + 1;
            const key = `${year}-${pad2(mon + 1)}-${pad2(day)}`;
            const rows = byDay.get(key) || [];
            const extra = rows.length > 3 ? rows.length - 3 : 0;
            const weekend = (startWeekday + day - 1) % 7 >= 5;
            return (
              <button
                type="button"
                key={key}
                className={`cal-day${key === todayKey ? ' is-today' : ''}${key === selectedKey ? ' is-selected' : ''}${
                  weekend ? ' is-weekend' : ''
                }${rows.length ? '' : ' is-empty'}`}
                onClick={() => setSelectedDay(day)}
              >
                <span className="cal-num">{day}</span>
                {rows.slice(0, 3).map((row) => (
                  <span key={row.id} className={`cal-item ${row.kind}${row.statusTone === 'danger' ? ' danger' : ''}`}>
                    {row.time ? `${row.time} ` : ''}
                    {row.title}
                  </span>
                ))}
                {extra > 0 && <span className="cal-more">ещё {extra}</span>}
              </button>
            );
          })}
        </div>
        <aside className="panel cal-detail">
          <h2>
            {safeDay} {MONTHS_GEN[mon]}
            {isCurrentMonth && safeDay === now.getDate() ? ' · сегодня' : ''}
          </h2>
          {!selectedItems.length && <p className="muted">В этот день ничего не стоит в афише, новостях и срочных.</p>}
          <div className="cal-detail-list">
            {selectedItems.map((row) => (
              <article key={row.id} className="cal-card">
                <div className="meta">
                  <span className={`chip ${row.kind === 'alert' ? row.statusTone : row.kind === 'news' ? 'neutral' : ''}`.trim()}>
                    {CAL_KIND_LABEL[row.kind]}
                  </span>
                  {row.time && <span className="chip">{row.time}</span>}
                  <span className={`chip ${row.statusTone}`}>{row.status}</span>
                </div>
                <h3>{row.title}</h3>
                {row.place && <p className="cal-place">{row.place}</p>}
                {row.note && <p className="muted">{row.note}</p>}
                <button type="button" className="btn ghost" onClick={() => navigate(row.href)}>
                  Открыть раздел
                </button>
              </article>
            ))}
          </div>
        </aside>
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

function PromoPage({ canEdit }: { canEdit: boolean }) {
  const [items, setItems] = useState<PromoLink[]>([]);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [title, setTitle] = useState('');
  const [slug, setSlug] = useState('');
  const [note, setNote] = useState('');

  async function load() {
    const data = await api<PromoLink[]>('/admin/promo');
    setItems(data || []);
  }

  useEffect(() => {
    load().catch((err) => setError(err instanceof Error ? err.message : 'Ошибка'));
  }, []);

  async function createLink(e: React.FormEvent) {
    e.preventDefault();
    if (!canEdit) return;
    const cleanSlug = slug.trim().toLowerCase();
    if (title.trim().length < 2 || !/^[a-z0-9][a-z0-9_-]{1,31}$/.test(cleanSlug)) {
      setError('Название и короткий адрес латиницей, например otdam');
      return;
    }
    setBusy(true);
    setError('');
    try {
      await api<PromoLink>('/admin/promo', {
        method: 'POST',
        body: JSON.stringify({ title: title.trim(), slug: cleanSlug, note: note.trim() || null }),
      });
      setTitle('');
      setSlug('');
      setNote('');
      await load();
      pushToast('Ссылка готова — копируйте в пост');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    } finally {
      setBusy(false);
    }
  }

  async function copyUrl(url: string) {
    try {
      await navigator.clipboard.writeText(url);
      pushToast('Ссылка скопирована');
    } catch {
      pushToast('Скопируйте ссылку вручную');
    }
  }

  async function setActive(row: PromoLink, is_active: boolean) {
    if (!canEdit) return;
    try {
      const updated = await api<PromoLink>(`/admin/promo/${row.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ is_active }),
      });
      setItems((prev) => prev.map((x) => (x.id === updated.id ? updated : x)));
      pushToast(is_active ? 'Снова в списке рабочих' : 'Скрыли из рабочих — старые посты всё ещё считают');
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Ошибка');
    }
  }

  function shareOf(row: PromoLink) {
    if (!row.visits_unique) return '—';
    return `${Math.round((row.downloads_unique / row.visits_unique) * 100)}%`;
  }

  return (
    <div>
      <div className="page-head compact">
        <div>
          <h1>Реклама</h1>
          <p>
            Для каждой группы своя ссылка. В пост ВК ставьте её, не обычный адрес сайта. Тогда видно, сколько
            зашли и сколько скачали приложение.
          </p>
        </div>
      </div>
      {canEdit ? (
        <form className="toolbar compact" onSubmit={createLink}>
          <input
            placeholder="Название, например Отдам даром"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={120}
          />
          <input
            placeholder="Коротко: otdam"
            value={slug}
            onChange={(e) => setSlug(e.target.value.toLowerCase().replace(/[^a-z0-9_-]/g, ''))}
            maxLength={32}
          />
          <input
            placeholder="Группа ВК, по желанию"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            maxLength={255}
          />
          <button className="btn" type="submit" disabled={busy}>
            Сделать ссылку
          </button>
        </form>
      ) : null}
      {error ? <p className="error">{error}</p> : null}
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Группа</th>
              <th>Ссылка в пост</th>
              <th>Зашли</th>
              <th>Сегодня</th>
              <th>Скачали</th>
              <th>Сегодня</th>
              <th>Скачали из зашедших</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((row) => (
              <tr key={row.id} className={row.is_active ? 'dir-row' : 'dir-row error-row'}>
                <td>
                  <div className="audit-who">{row.title}</div>
                  <div className="audit-sub">{row.note || `/${row.slug}`}</div>
                </td>
                <td>
                  <div className="promo-url">{row.url}</div>
                  <div className="audit-sub">уникальных: {row.visits_unique} зашли · {row.downloads_unique} скачали</div>
                </td>
                <td>{row.visits_unique || row.visits}</td>
                <td>{row.visits_today}</td>
                <td>{row.downloads_unique || row.downloads}</td>
                <td>{row.downloads_today}</td>
                <td>{shareOf(row)}</td>
                <td>
                  <div className="actions inline">
                    <button className="btn" type="button" onClick={() => copyUrl(row.url)}>
                      Копировать
                    </button>
                    {canEdit ? (
                      <button className="btn ghost" type="button" onClick={() => setActive(row, !row.is_active)}>
                        {row.is_active ? 'Скрыть' : 'Показать'}
                      </button>
                    ) : null}
                  </div>
                </td>
              </tr>
            ))}
            {!items.length ? (
              <tr>
                <td className="empty" colSpan={8}>
                  Пока нет ссылок. Создайте для группы короткий адрес и копируйте его в рекламный пост.
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </div>
  );
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
            скачать и установить APK. Загружайте только release-подписанный APK с тем же ключом — иначе Android
            поставит второе приложение рядом со старым.
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
        <Route path="/" element={<Dashboard role={user!.role} />} />
        {canSeeInbox(user!.role) && <Route path="/inbox" element={<ContactsPage />} />}
        {canSeeInbox(user!.role) && <Route path="/promo" element={<PromoPage canEdit={user!.role === 'admin'} />} />}
        {canModerate(user!.role) && <Route path="/moderation" element={<ModerationPage />} />}
        {canModerate(user!.role) && <Route path="/listings" element={<ListingsPage />} />}
        {(canModerate(user!.role) || canEditDirectory(user!.role)) && (
          <Route path="/reports" element={<ReportsPage canListings={canModerate(user!.role)} />} />
        )}
        <Route path="/audit" element={<AuditPage />} />
        {canModerate(user!.role) && <Route path="/errors" element={<ErrorsPage />} />}
        {canEditDirectory(user!.role) && <Route path="/directory" element={<DirectoryPage />} />}
        {canEditDirectory(user!.role) && <Route path="/events" element={<EventsPage />} />}
        {canEditDirectory(user!.role) && <Route path="/calendar" element={<EditorialCalendarPage />} />}
        {canEditDirectory(user!.role) && <Route path="/transport" element={<TransportPage />} />}
        {canModerate(user!.role) && <Route path="/rides" element={<RidesPage />} />}
        {canEditDirectory(user!.role) && <Route path="/news" element={<NewsPage />} />}
        {canEditDirectory(user!.role) && <Route path="/news-vk" element={<VkNewsPage />} />}
        {canEditDirectory(user!.role) && <Route path="/broadcast" element={<BroadcastPage />} />}
        {canEditDirectory(user!.role) && <Route path="/alerts" element={<AlertsPage />} />}
        {canModerate(user!.role) && <Route path="/chats" element={<ChatsModerationPage />} />}
        {canModerate(user!.role) && <Route path="/calls" element={<CallsPage />} />}
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
