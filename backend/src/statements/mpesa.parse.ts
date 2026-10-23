/**
 * Reads M-Pesa "you have received" messages and statement rows into plain
 * records. Tolerant on purpose: Safaricom words the SMS differently for a
 * personal number, a till and a paybill, and owners paste whatever they have.
 */
export interface ParsedMpesa {
  code: string;
  amount: number;
  senderName: string | null;
  /** Digits as written, which may be masked: 0712***678. */
  senderPhone: string | null;
  paidAt: Date | null;
}

const CODE_AT_START = /\b([A-Z0-9]{10})\s+Confirmed\b/g;
const PHONE = String.raw`(?:\+?254|0)[17][\d\s*]{7,12}\d`;
const NAIROBI_OFFSET_HOURS = 3;

const OUTGOING = /\b(sent to|paid to|withdraw|bought|airtime|you have transferred|transferred to|pay bill to|give|deposit)\b/i;

function parseAmount(text: string): number | null {
  const match = text.match(/Ksh\.?\s*([\d,]+(?:\.\d{1,2})?)/i);
  if (!match) return null;
  const value = Number(match[1].replace(/,/g, ''));
  return Number.isFinite(value) && value > 0 ? value : null;
}

function parseSmsDate(text: string): Date | null {
  const m = text.match(/on\s+(\d{1,2})\/(\d{1,2})\/(\d{2,4})\s+at\s+(\d{1,2}):(\d{2})\s*(AM|PM)/i);
  if (!m) return null;
  let year = Number(m[3]);
  if (year < 100) year += 2000;
  let hour = Number(m[4]) % 12;
  if (m[6].toUpperCase() === 'PM') hour += 12;
  const date = new Date(Date.UTC(year, Number(m[2]) - 1, Number(m[1]), hour - NAIROBI_OFFSET_HOURS, Number(m[5])));
  return Number.isNaN(date.getTime()) ? null : date;
}

function cleanName(value: string | null | undefined): string | null {
  if (!value) return null;
  const cleaned = value.replace(/\s+/g, ' ').replace(/[.,;:-]+$/g, '').trim();
  return cleaned.length >= 2 ? cleaned : null;
}

function parseSender(segment: string): { name: string | null; phone: string | null } {
  // "from JOHN DOE 0712345678", "from JOHN DOE 0712***678"
  const nameThenPhone = segment.match(new RegExp(String.raw`from\s+([A-Za-z][A-Za-z .'-]*?)\s+(${PHONE})`, 'i'));
  if (nameThenPhone) {
    return { name: cleanName(nameThenPhone[1]), phone: nameThenPhone[2].replace(/\s+/g, '') };
  }
  // "from 254712345678 JOHN DOE." (till and paybill wording)
  const phoneThenName = segment.match(
    new RegExp(String.raw`from\s+(${PHONE})\s*[-–]?\s*([A-Za-z][A-Za-z .'-]*?)(?=\.|\s+on\b|\s+Account\b|\s+New\b|$)`, 'i'),
  );
  if (phoneThenName) {
    return { name: cleanName(phoneThenName[2]), phone: phoneThenName[1].replace(/\s+/g, '') };
  }
  const phoneOnly = segment.match(new RegExp(String.raw`from\s+(${PHONE})`, 'i'));
  if (phoneOnly) return { name: null, phone: phoneOnly[1].replace(/\s+/g, '') };
  const nameOnly = segment.match(/from\s+([A-Za-z][A-Za-z .'-]*?)(?=\s+on\b|\.|\s+Account\b|\s+New\b|$)/i);
  return { name: cleanName(nameOnly?.[1]), phone: null };
}

function parseSmsMessages(text: string): { entries: ParsedMpesa[]; skipped: number } {
  const starts: number[] = [];
  for (const m of text.matchAll(CODE_AT_START)) starts.push(m.index ?? 0);
  const entries: ParsedMpesa[] = [];
  let skipped = 0;

  starts.forEach((start, i) => {
    const segment = text.slice(start, starts[i + 1] ?? text.length).replace(/\s+/g, ' ').trim();
    const code = segment.match(/^([A-Z0-9]{10})/)?.[1];
    const inbound = /\breceived\b/i.test(segment);
    if (!code || !inbound || (OUTGOING.test(segment) && !/\byou have received\b|\breceived from\b/i.test(segment))) {
      skipped++;
      return;
    }
    const amount = parseAmount(segment);
    if (!amount) {
      skipped++;
      return;
    }
    const sender = parseSender(segment);
    entries.push({
      code,
      amount,
      senderName: sender.name,
      senderPhone: sender.phone,
      paidAt: parseSmsDate(segment),
    });
  });
  return { entries, skipped };
}

/** Splits one CSV line, honouring quoted fields. */
function splitCsv(line: string): string[] {
  const out: string[] = [];
  let current = '';
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (quoted && line[i + 1] === '"') {
        current += '"';
        i++;
      } else quoted = !quoted;
    } else if (ch === ',' && !quoted) {
      out.push(current);
      current = '';
    } else current += ch;
  }
  out.push(current);
  return out.map((cell) => cell.trim());
}

function parseCsvStatement(text: string): { entries: ParsedMpesa[]; skipped: number } {
  const lines = text.split(/\r?\n/).filter((l) => l.trim());
  const headerIndex = lines.findIndex((l) => /receipt\s*no/i.test(l));
  if (headerIndex < 0) return { entries: [], skipped: 0 };
  const header = splitCsv(lines[headerIndex]).map((h) => h.toLowerCase());
  const col = (re: RegExp) => header.findIndex((h) => re.test(h));
  const receipt = col(/receipt/);
  const time = col(/completion|time|date/);
  const details = col(/details|description/);
  const paidIn = col(/paid\s*in|credit/);
  if (receipt < 0 || paidIn < 0) return { entries: [], skipped: 0 };

  const entries: ParsedMpesa[] = [];
  let skipped = 0;
  for (const line of lines.slice(headerIndex + 1)) {
    const cells = splitCsv(line);
    const code = (cells[receipt] ?? '').toUpperCase();
    const amount = Number((cells[paidIn] ?? '').replace(/,/g, ''));
    if (!/^[A-Z0-9]{10}$/.test(code) || !(amount > 0)) {
      skipped++;
      continue;
    }
    const detail = cells[details] ?? '';
    const sender = detail.match(/from\s*-?\s*([\d*]+)\s*-?\s*(.*)$/i);
    const rawTime = cells[time] ?? '';
    const stamped = rawTime ? new Date(`${rawTime.replace(' ', 'T')}+03:00`) : null;
    entries.push({
      code,
      amount,
      senderName: cleanName(sender?.[2]),
      senderPhone: sender?.[1] ?? null,
      paidAt: stamped && !Number.isNaN(stamped.getTime()) ? stamped : null,
    });
  }
  return { entries, skipped };
}

export function parseMpesaText(text: string): { entries: ParsedMpesa[]; skipped: number } {
  const input = (text ?? '').slice(0, 200_000);
  const result = /receipt\s*no/i.test(input) && input.includes(',') ? parseCsvStatement(input) : parseSmsMessages(input);

  // The same message pasted twice must only appear once.
  const seen = new Set<string>();
  const entries = result.entries.filter((entry) => {
    if (seen.has(entry.code)) return false;
    seen.add(entry.code);
    return true;
  });
  return { entries, skipped: result.skipped + (result.entries.length - entries.length) };
}
