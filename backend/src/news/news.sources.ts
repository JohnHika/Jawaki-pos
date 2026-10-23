/**
 * Where headlines come from. Every entry is a publisher's own public RSS feed
 * (or an official body's); we keep the headline, a short excerpt and the link
 * back to the original, never the article text.
 *
 * Deliberately NOT here: Google News RSS. Its terms limit it to personal,
 * non-commercial feed readers, which a paid product is not.
 */
export interface NewsFeed {
  key: string;
  name: string;
  url: string;
  /** Used when the headline matches no topic but the source itself is relevant. */
  defaultCategory?: string;
  /** Official bodies are kept even when no keyword matches. */
  official?: boolean;
}

export const NEWS_FEEDS: NewsFeed[] = [
  {
    key: 'capitalfm-business',
    name: 'Capital FM Business',
    url: 'https://www.capitalfm.co.ke/business/feed/',
  },
  {
    key: 'capitalfm-news',
    name: 'Capital FM',
    url: 'https://www.capitalfm.co.ke/news/feed/',
  },
  {
    key: 'standard-business',
    name: 'The Standard Business',
    url: 'https://www.standardmedia.co.ke/rss/business.php',
  },
  {
    key: 'standard-headlines',
    name: 'The Standard',
    url: 'https://www.standardmedia.co.ke/rss/headlines.php',
  },
  {
    key: 'kenyans',
    name: 'Kenyans.co.ke',
    url: 'https://www.kenyans.co.ke/feeds/news',
  },
  {
    key: 'cbk',
    name: 'Central Bank of Kenya',
    url: 'https://www.centralbank.go.ke/feed/',
    defaultCategory: 'MONEY_FX',
    official: true,
  },
];

/** Pages a trader should be able to open in one tap; no feed, so just links. */
export const OFFICIAL_LINKS = [
  {
    key: 'kra-notices',
    name: 'KRA public notices',
    category: 'CUSTOMS_TAX',
    url: 'https://www.kra.go.ke/news-center/public-notices',
    about: 'Customs, VAT and tax notices straight from KRA',
  },
  {
    key: 'kentrade',
    name: 'KenTrade (single window)',
    category: 'TRADE_IMPORT',
    url: 'https://www.kentrade.go.ke',
    about: 'Import / export permits and the IDF',
  },
  {
    key: 'kebs',
    name: 'KEBS',
    category: 'TRADE_IMPORT',
    url: 'https://www.kebs.org',
    about: 'Standards, PVoC and banned or substandard goods',
  },
  {
    key: 'cbk-rates',
    name: 'CBK exchange rates',
    category: 'MONEY_FX',
    url: 'https://www.centralbank.go.ke/rates/forex-exchange-rates/',
    about: 'The official daily rates',
  },
  {
    key: 'epra',
    name: 'EPRA fuel prices',
    category: 'LOGISTICS',
    url: 'https://www.epra.go.ke',
    about: 'Monthly pump prices, which move transport costs',
  },
  {
    key: 'nairobi-county',
    name: 'Nairobi City County',
    category: 'COUNTY_LICENSING',
    url: 'https://nairobi.go.ke',
    about: 'Business permits, levies and market notices',
  },
  {
    key: 'kpa',
    name: 'Kenya Ports Authority',
    category: 'LOGISTICS',
    url: 'https://www.kpa.co.ke',
    about: 'Mombasa port notices and container tracking',
  },
];
