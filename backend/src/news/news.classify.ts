export type NewsCategory =
  | 'CUSTOMS_TAX'
  | 'TRADE_IMPORT'
  | 'MONEY_FX'
  | 'COUNTY_LICENSING'
  | 'LOGISTICS'
  | 'MARKET'
  | 'GENERAL';

export type NewsImpact = 'HIGH' | 'MEDIUM' | 'LOW';

export interface Classification {
  category: NewsCategory;
  impact: NewsImpact;
  score: number;
  tags: string[];
}

interface Term {
  /** Matched as a whole word / phrase, case-insensitive. */
  term: string;
  weight: number;
  category: Exclude<NewsCategory, 'GENERAL'>;
  /** Short label shown to the user as a tag. */
  tag?: string;
}

const t = (
  category: Term['category'],
  weight: number,
  terms: string[],
  tag?: string,
): Term[] => terms.map((term) => ({ term, weight, category, tag }));

/**
 * What matters to a trader who imports from China or Dubai and sells from a
 * Nairobi market stall. Strong terms (3) are almost always relevant on their
 * own; medium (2) usually; weak (1) only count in company.
 */
const TERMS: Term[] = [
  ...t('CUSTOMS_TAX', 3, ['kra', 'kenya revenue authority', 'customs', 'duty', 'duties', 'finance bill', 'finance act', 'minimum yield', 'etims', 'excise', 'import duty']),
  ...t('CUSTOMS_TAX', 2, ['tax', 'taxes', 'vat', 'valuation', 'benchmark', 'turnover tax', 'withholding', 'presumptive', 'levy', 'levies', 'penalty', 'penalties']),
  ...t('TRADE_IMPORT', 3, ['import ban', 'ban on imports', 'imports', 'importers', 'tariff', 'tariffs', 'kebs', 'pvoc', 'kentrade', 'clearing agent', 'clearing agents', 'consolidated cargo', 'single customs territory', 'counterfeit', 'counterfeits', 'contraband', 'anti-dumping']),
  ...t('TRADE_IMPORT', 2, ['import', 'export', 'exporters', 'container', 'containers', 'standards', 'agoa', 'eac', 'trade deal', 'trade war', 'icd', 'inland container depot', 'mombasa port', 'kenya ports authority', 'kpa', 'idf']),
  ...t('TRADE_IMPORT', 1, ['china', 'chinese', 'dubai', 'turkey', 'india', 'guangzhou', 'shipping', 'cargo']),
  ...t('MONEY_FX', 3, ['exchange rate', 'shilling', 'forex', 'central bank rate', 'interest rate', 'interest rates', 'cbk', 'mpc']),
  ...t('MONEY_FX', 2, ['inflation', 'm-pesa', 'mpesa', 'mobile money', 'safaricom', 'bank charges', 'loan', 'loans', 'credit', 'fuliza', 'hustler fund', 'dollar']),
  ...t('COUNTY_LICENSING', 3, ['kamukunji', 'gikomba', 'nyamakima', 'eastleigh', 'toi market', 'muthurwa', 'single business permit', 'hawkers', 'hawking', 'nairobi cbd', 'nairobi city county']),
  ...t('COUNTY_LICENSING', 2, ['county government', 'county', 'licence', 'license', 'permit', 'permits', 'demolition', 'demolitions', 'evict', 'eviction', 'evicted', 'fire safety', 'market traders', 'sakaja', 'cess']),
  ...t('LOGISTICS', 3, ['fuel prices', 'pump prices', 'epra', 'diesel', 'petrol', 'sgr', 'standard gauge railway']),
  ...t('LOGISTICS', 2, ['transport', 'truckers', 'trucks', 'matatu', 'freight', 'road closure', 'strike', 'port of mombasa', 'nairobi expressway']),
  ...t('LOGISTICS', 1, ['port', 'ports', 'road', 'roads']),
  ...t('MARKET', 3, ['cost of living', 'small traders', 'small-scale traders', 'jua kali', 'wholesalers', 'wholesale']),
  ...t('MARKET', 2, ['traders', 'trader', 'sme', 'smes', 'msme', 'msmes', 'retailers', 'retail', 'consumer', 'consumers', 'supermarket', 'supermarkets', 'unga', 'sugar prices']),
  ...t('MARKET', 1, ['prices', 'price', 'business', 'businesses', 'market']),
];

/** Words that turn "something about tax" into "something that just changed". */
const ACTION_TERMS = [
  'ban', 'bans', 'banned', 'crackdown', 'hike', 'hikes', 'raise', 'raises', 'raised', 'increase', 'increases', 'increased',
  'new', 'deadline', 'directive', 'directs', 'orders', 'ordered', 'suspend', 'suspends', 'suspended', 'demolish', 'demolishes',
  'evict', 'shut', 'shutdown', 'protest', 'protests', 'seize', 'seizes', 'seized', 'impound', 'impounded', 'slashes', 'cut', 'cuts',
  'introduces', 'introduced', 'effective', 'takes effect', 'revised', 'review', 'rules', 'warns', 'warning', 'notice',
];

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const compile = (term: string) => new RegExp(`(?<![a-z0-9])${escape(term)}(?![a-z0-9])`, 'i');

const COMPILED = TERMS.map((entry) => ({ ...entry, re: compile(entry.term) }));
const ACTION_RE = ACTION_TERMS.map(compile);

/** Plain-text, lower-cased form used for matching. */
export function normalizeForMatch(...parts: Array<string | null | undefined>): string {
  return parts
    .filter(Boolean)
    .join(' ')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&[a-z]+;|&#\d+;/gi, ' ')
    .replace(/\s+/g, ' ')
    .toLowerCase();
}

const CATEGORY_PRIORITY: NewsCategory[] = [
  'CUSTOMS_TAX',
  'TRADE_IMPORT',
  'COUNTY_LICENSING',
  'MONEY_FX',
  'LOGISTICS',
  'MARKET',
];

/**
 * Scores a headline (and excerpt) for how much it should matter to a market
 * trader. The title counts double: a topic in the headline is the story, in
 * the excerpt it is only context.
 */
export function classifyNews(
  title: string,
  summary?: string | null,
  defaultCategory?: NewsCategory,
): Classification {
  const titleText = normalizeForMatch(title);
  const bodyText = normalizeForMatch(summary);

  const perCategory = new Map<NewsCategory, number>();
  const tags = new Set<string>();
  let score = 0;

  for (const entry of COMPILED) {
    const inTitle = entry.re.test(titleText);
    const inBody = !inTitle && entry.re.test(bodyText);
    if (!inTitle && !inBody) continue;
    const points = inTitle ? entry.weight * 2 : entry.weight;
    score += points;
    perCategory.set(entry.category, (perCategory.get(entry.category) ?? 0) + points);
    if (entry.weight >= 2) tags.add(entry.tag ?? entry.term);
  }

  // A story needs a strong base topic before "new/hike/ban" makes it urgent.
  if (score >= 6 && ACTION_RE.some((re) => re.test(titleText))) score += 4;

  let category: NewsCategory = defaultCategory ?? 'GENERAL';
  let best = 0;
  for (const c of CATEGORY_PRIORITY) {
    const v = perCategory.get(c) ?? 0;
    if (v > best) {
      best = v;
      category = c;
    }
  }

  // Calibrated against live Kenyan feeds: "HIGH" is reserved for the handful of
  // stories a week that change what a trader must do (new import rules, a KRA
  // change, a banned product), because HIGH is what gets pushed to phones.
  const impact: NewsImpact = score >= 18 ? 'HIGH' : score >= 8 ? 'MEDIUM' : 'LOW';
  return { category, impact, score, tags: [...tags].slice(0, 6) };
}

/** Headlines scoring below this are treated as noise and not stored. */
export const MIN_RELEVANCE_SCORE = 4;
