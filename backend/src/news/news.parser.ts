import { XMLParser } from 'fast-xml-parser';

export interface ParsedFeedItem {
  title: string;
  url: string;
  summary: string | null;
  imageUrl: string | null;
  publishedAt: Date;
}

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  textNodeName: '#text',
  // Feeds are untrusted input: never expand DOCTYPE entities.
  processEntities: true,
  htmlEntities: true,
  trimValues: true,
});

const NAMED: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: ' ',
  rsquo: '’',
  lsquo: '‘',
  rdquo: '”',
  ldquo: '“',
  ndash: '–',
  mdash: '—',
  hellip: '…',
};

export function decodeEntities(text: string): string {
  return text
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => safeChar(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => safeChar(parseInt(d, 10)))
    .replace(/&([a-z]+);/gi, (m, name) => NAMED[name.toLowerCase()] ?? m);
}

function safeChar(code: number): string {
  if (!Number.isFinite(code) || code <= 0 || code > 0x10ffff) return '';
  try {
    return String.fromCodePoint(code);
  } catch {
    return '';
  }
}

/** Plain text from an HTML-ish fragment, cut to `max` characters on a word boundary. */
export function toPlainExcerpt(html: string | null | undefined, max = 280): string | null {
  if (!html) return null;
  let text = decodeEntities(
    html
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]*>/g, ' '),
  );
  text = decodeEntities(text).replace(/\s+/g, ' ').trim();
  // Many feeds end the excerpt with "The post X appeared first on Y."
  text = text.replace(/\s*The post .{0,200} appeared first on .{0,80}\.?$/i, '').trim();
  if (!text) return null;
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const lastSpace = cut.lastIndexOf(' ');
  return `${cut.slice(0, lastSpace > max * 0.6 ? lastSpace : max).trim()}…`;
}

const asText = (v: unknown): string => {
  if (v === null || v === undefined) return '';
  if (typeof v === 'string') return v;
  if (typeof v === 'number') return String(v);
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>;
    if (typeof o['#text'] === 'string') return o['#text'] as string;
  }
  return '';
};

const asArray = <T>(v: T | T[] | undefined): T[] => (v === undefined || v === null ? [] : Array.isArray(v) ? v : [v]);

/** Only plain web links are kept; `javascript:`, `data:` etc. are dropped. */
export function safeHttpUrl(value: string | null | undefined): string | null {
  if (!value) return null;
  try {
    const u = new URL(value.trim());
    return u.protocol === 'http:' || u.protocol === 'https:' ? u.toString() : null;
  } catch {
    return null;
  }
}

function findImage(item: Record<string, any>, html: string): string | null {
  const candidates: unknown[] = [];
  for (const key of ['media:content', 'media:thumbnail', 'enclosure']) {
    for (const node of asArray(item[key])) {
      const type = typeof node === 'object' ? (node as any)['@_type'] : undefined;
      if (type && !String(type).startsWith('image')) continue;
      candidates.push(typeof node === 'object' ? (node as any)['@_url'] : undefined);
    }
  }
  const inline = html.match(/<img[^>]+src=["']([^"']+)["']/i)?.[1];
  candidates.push(inline);
  for (const c of candidates) {
    const url = safeHttpUrl(typeof c === 'string' ? c : null);
    if (url) return url;
  }
  return null;
}

function parseDate(...values: unknown[]): Date | null {
  for (const v of values) {
    const text = asText(v);
    if (!text) continue;
    const d = new Date(text);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return null;
}

/** Parses RSS 2.0 or Atom into plain items. Malformed entries are skipped, not fatal. */
export function parseFeed(xml: string, now: Date = new Date()): ParsedFeedItem[] {
  let doc: any;
  try {
    doc = parser.parse(xml);
  } catch {
    return [];
  }

  const rssItems = asArray<Record<string, any>>(doc?.rss?.channel?.item);
  const atomItems = asArray<Record<string, any>>(doc?.feed?.entry);
  const raw = rssItems.length ? rssItems : atomItems;
  const out: ParsedFeedItem[] = [];

  for (const item of raw) {
    const title = decodeEntities(asText(item.title)).replace(/\s+/g, ' ').trim();
    let link = asText(item.link);
    if (!link && item.link && typeof item.link === 'object') {
      const links = asArray<any>(item.link);
      const alt = links.find((l) => !l['@_rel'] || l['@_rel'] === 'alternate') ?? links[0];
      link = alt?.['@_href'] ?? '';
    }
    const url = safeHttpUrl(link) ?? (asText(item.guid).startsWith('http') ? safeHttpUrl(asText(item.guid)) : null);
    if (!title || !url) continue;

    const html = asText(item.description) || asText(item.summary) || asText(item['content:encoded']) || asText(item.content);
    const publishedAt = parseDate(item.pubDate, item.published, item.updated, item['dc:date']) ?? now;
    // A feed occasionally carries a date far in the future; never trust it.
    const safeDate = publishedAt.getTime() > now.getTime() + 60 * 60 * 1000 ? now : publishedAt;

    out.push({
      title: title.slice(0, 300),
      url,
      summary: toPlainExcerpt(html),
      imageUrl: findImage(item, html),
      publishedAt: safeDate,
    });
  }
  return out;
}
