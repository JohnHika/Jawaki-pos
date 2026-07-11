/**
 * Per-branch operating hours — the canonical shape, a defensive normalizer,
 * and the "is the shop open right now / how long until close" computation.
 *
 * Stored in Branch.settings.operatingHours (JSON, no migration). Shared by
 * the branches service (validate/normalize on save) and the AI service
 * (inject open/closed + trading-window context into chat), so the assistant
 * reasons over real, user-controlled hours instead of a freeform memory.
 */

export const DAY_KEYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const;
export type DayKey = (typeof DAY_KEYS)[number];

/** One day's hours. `closed` wins over open/close. Break window optional. */
export interface DayHours {
  closed: boolean;
  open: string; // "HH:MM", 24h
  close: string; // "HH:MM", 24h
  breakStart?: string; // "HH:MM"
  breakEnd?: string; // "HH:MM"
}

export interface OperatingHours {
  /** Which day the business considers the start of its week. */
  weekStartDay: DayKey;
  days: Record<DayKey, DayHours>;
}

const TIME_RE = /^([01]?\d|2[0-3]):[0-5]\d$/;

function normalizeTime(value: unknown, fallback: string): string {
  if (typeof value !== 'string') return fallback;
  const trimmed = value.trim();
  if (!TIME_RE.test(trimmed)) return fallback;
  // Zero-pad the hour so string comparison ("08:00" < "16:00") is always valid.
  const [h, m] = trimmed.split(':');
  return `${h.padStart(2, '0')}:${m}`;
}

function normalizeDay(raw: any): DayHours {
  const closed = raw?.closed === true;
  const open = normalizeTime(raw?.open, '08:00');
  const close = normalizeTime(raw?.close, '18:00');
  const day: DayHours = { closed, open, close };
  // Only keep a break if BOTH ends are valid times, else drop it entirely.
  if (TIME_RE.test(String(raw?.breakStart ?? '')) && TIME_RE.test(String(raw?.breakEnd ?? ''))) {
    day.breakStart = normalizeTime(raw.breakStart, '13:00');
    day.breakEnd = normalizeTime(raw.breakEnd, '14:00');
  }
  return day;
}

/**
 * Coerce arbitrary client input into a valid OperatingHours object, never
 * throwing — bad fields fall back to sane defaults rather than corrupting
 * the settings blob (same defensive posture as the AI tool sanitizers).
 * Returns null when there's genuinely nothing usable to store.
 */
export function normalizeOperatingHours(raw: unknown): OperatingHours | null {
  if (!raw || typeof raw !== 'object') return null;
  const input = raw as Record<string, any>;
  const daysIn = (input.days && typeof input.days === 'object' ? input.days : {}) as Record<string, any>;

  const weekStartDay: DayKey = DAY_KEYS.includes(input.weekStartDay) ? input.weekStartDay : 'mon';

  const days = {} as Record<DayKey, DayHours>;
  for (const key of DAY_KEYS) {
    days[key] = normalizeDay(daysIn[key]);
  }
  return { weekStartDay, days };
}

function toMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

const JS_DAY_TO_KEY: DayKey[] = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

/**
 * Compute the live open/closed status for a set of hours at a given instant.
 * `now` is evaluated in the branch's timezone. Returns compact fields the AI
 * can reason over directly. Returns null when hours aren't configured.
 */
export function computeOpenStatus(
  hours: OperatingHours | null,
  timezone: string,
  now: Date = new Date(),
): {
  current_day: DayKey;
  is_open_now: boolean;
  opens_at: string | null;
  closes_at: string | null;
  minutes_until_close: number | null;
  minutes_until_open: number | null;
  on_break: boolean;
} | null {
  if (!hours) return null;

  // Get wall-clock day + minutes in the branch timezone.
  let localDayIdx: number;
  let localMinutes: number;
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone || 'Africa/Nairobi',
      weekday: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).formatToParts(now);
    const wd = parts.find((p) => p.type === 'weekday')?.value ?? 'Mon';
    const hourStr = parts.find((p) => p.type === 'hour')?.value ?? '00';
    const minStr = parts.find((p) => p.type === 'minute')?.value ?? '00';
    const wdMap: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
    localDayIdx = wdMap[wd] ?? now.getDay();
    // Intl can emit "24" for midnight in hour12:false — clamp to 0.
    const hr = parseInt(hourStr, 10) % 24;
    localMinutes = hr * 60 + parseInt(minStr, 10);
  } catch {
    localDayIdx = now.getDay();
    localMinutes = now.getHours() * 60 + now.getMinutes();
  }

  const dayKey = JS_DAY_TO_KEY[localDayIdx];
  const day = hours.days[dayKey];

  if (!day || day.closed) {
    return {
      current_day: dayKey,
      is_open_now: false,
      opens_at: null,
      closes_at: null,
      minutes_until_close: null,
      minutes_until_open: null,
      on_break: false,
    };
  }

  const openM = toMinutes(day.open);
  const closeM = toMinutes(day.close);
  const withinHours = localMinutes >= openM && localMinutes < closeM;

  let onBreak = false;
  if (withinHours && day.breakStart && day.breakEnd) {
    const bs = toMinutes(day.breakStart);
    const be = toMinutes(day.breakEnd);
    onBreak = localMinutes >= bs && localMinutes < be;
  }

  const isOpen = withinHours && !onBreak;

  return {
    current_day: dayKey,
    is_open_now: isOpen,
    opens_at: day.open,
    closes_at: day.close,
    minutes_until_close: withinHours ? closeM - localMinutes : null,
    minutes_until_open: localMinutes < openM ? openM - localMinutes : null,
    on_break: onBreak,
  };
}

/**
 * A `Date` whose UTC fields (getUTCFullYear/getUTCHours/etc.) hold the
 * current wall-clock date+time in `timezone`, rebased so that plain local
 * getters/setters (getDate, setHours, getDay, ...) read the same values too.
 * That equivalence only holds because the server process itself runs in UTC
 * (true for this app's Render deployment) — on a server in a different
 * process timezone this would need `setUTCHours` etc. throughout instead.
 *
 * Use this as a drop-in for `new Date()` in date-range math that was written
 * with local getters/setters, so "today"/"this week" etc. resolve for the
 * branch's timezone instead of the server's.
 */
export function nowInTimezone(timezone: string): Date {
  const tz = timezone || 'Africa/Nairobi';
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).formatToParts(new Date());
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00';
  return new Date(
    Date.UTC(
      Number(get('year')),
      Number(get('month')) - 1,
      Number(get('day')),
      Number(get('hour')) % 24,
      Number(get('minute')),
      Number(get('second')),
    ),
  );
}

/**
 * "YYYY-MM-DD" for the current instant as observed in `timezone` — e.g. at
 * 21:38 UTC, this is "tomorrow" in Africa/Nairobi (UTC+3, past local
 * midnight). Use this instead of `new Date().toISOString().split('T')[0]`
 * (the server's own UTC date) whenever "today" means "today for this
 * branch", not "today on the server".
 */
export function todayInTimezone(timezone: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone || 'Africa/Nairobi',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '01';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

/**
 * UTC instants for the start/end of a "YYYY-MM-DD" calendar date as observed
 * in `timezone` — not the server's ambient timezone. Without this, a sale at
 * 21:03 UTC (00:03 in Africa/Nairobi, UTC+3) lands in "today" for a Nairobi
 * branch but "yesterday" by naive `new Date(date).setHours(0,0,0,0)", which
 * runs in the server process's local timezone (UTC on Render) — silently
 * dropping the sale from daily summaries / end-of-day close right after
 * midnight EAT until the server's own midnight catches up.
 */
export function getDayBoundsInTimezone(
  dateStr: string,
  timezone: string,
): { start: Date; end: Date } {
  const tz = timezone || 'Africa/Nairobi';
  // Find the UTC offset (minutes) this timezone has for this calendar date by
  // formatting a UTC-midnight guess and reading back the local wall clock.
  const guess = new Date(`${dateStr}T00:00:00.000Z`);
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(guess);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00';
  const localAtGuess = Date.UTC(
    Number(get('year')),
    Number(get('month')) - 1,
    Number(get('day')),
    Number(get('hour')) % 24,
    Number(get('minute')),
  );
  const offsetMs = localAtGuess - guess.getTime();

  const start = new Date(guess.getTime() - offsetMs);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000 - 1);
  return { start, end };
}
