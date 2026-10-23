import { classifyNews, MIN_RELEVANCE_SCORE } from './news.classify';
import { parseFeed, safeHttpUrl, toPlainExcerpt } from './news.parser';

describe('classifyNews', () => {
  it('rates a new import rule from KRA as HIGH customs/tax news', () => {
    const c = classifyNews(
      'KRA to Block Some Imports as New Rules Take Effect From November',
      'The Kenya Revenue Authority says customs systems will reject imports that do not meet the new rules.',
    );
    expect(c.category).toBe('CUSTOMS_TAX');
    expect(c.impact).toBe('HIGH');
  });

  it('rates a KEBS ban on a product as HIGH trade news', () => {
    const c = classifyNews(
      'KEBS Names Mitumba Clothing Banned From Importation in Fresh Warning to Traders',
      'The Kenya Bureau of Standards says importers of the banned items risk seizure at customs.',
    );
    expect(c.category).toBe('TRADE_IMPORT');
    expect(c.impact).toBe('HIGH');
  });

  it('recognises the markets this product is built for', () => {
    const c = classifyNews('Traders at Gikomba and Kamukunji protest new county levy');
    expect(c.category).toBe('COUNTY_LICENSING');
    expect(c.score).toBeGreaterThanOrEqual(MIN_RELEVANCE_SCORE);
  });

  it('classifies fuel price news as logistics', () => {
    expect(classifyNews('EPRA announces new pump prices for diesel and petrol').category).toBe('LOGISTICS');
  });

  it('classifies currency and interest-rate news as money', () => {
    expect(classifyNews('Shilling weakens as CBK holds interest rate').category).toBe('MONEY_FX');
  });

  it('drops unrelated headlines below the relevance bar', () => {
    for (const title of [
      'Multi-Vehicle Crash at Salgaa Disrupts Traffic Along Nakuru-Eldoret Highway',
      'Gor Mahia beat AFC Leopards in derby',
      'Celebrity wedding draws large crowd',
    ]) {
      expect(classifyNews(title).score).toBeLessThan(MIN_RELEVANCE_SCORE);
    }
  });

  it('does not match inside longer words (tax vs taxi, port vs report)', () => {
    expect(classifyNews('Taxi drivers report a new route').score).toBe(0);
  });

  it('keeps an official source category when nothing matches', () => {
    expect(classifyNews('Survey of September 2026', null, 'MONEY_FX').category).toBe('MONEY_FX');
  });

  it('counts a topic in the headline for more than the same topic in the excerpt', () => {
    const inTitle = classifyNews('KRA customs update', 'Nothing else here');
    const inBody = classifyNews('An update', 'KRA customs update');
    expect(inTitle.score).toBeGreaterThan(inBody.score);
  });
});

describe('feed parsing', () => {
  const rss = `<?xml version="1.0"?>
  <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
    <channel>
      <title>Test</title>
      <item>
        <title><![CDATA[KRA raises duty on imports &amp; containers]]></title>
        <link>https://example.com/story-1</link>
        <description><![CDATA[<p>Traders say the <b>new</b> rule hurts.&nbsp;The post KRA raises appeared first on Example.</p>]]></description>
        <pubDate>Thu, 22 Oct 2026 08:00:00 +0300</pubDate>
        <media:content url="https://example.com/a.jpg" type="image/jpeg" />
      </item>
      <item>
        <title>Bad link</title>
        <link>javascript:alert(1)</link>
      </item>
      <item>
        <title>Future dated</title>
        <link>https://example.com/story-3</link>
        <pubDate>Thu, 22 Oct 2099 08:00:00 +0300</pubDate>
      </item>
    </channel>
  </rss>`;

  const now = new Date('2026-10-23T08:00:00Z');

  it('parses RSS items with CDATA, entities, excerpt and image', () => {
    const items = parseFeed(rss, now);
    const first = items[0];
    expect(first.title).toBe('KRA raises duty on imports & containers');
    expect(first.url).toBe('https://example.com/story-1');
    expect(first.summary).toBe('Traders say the new rule hurts.');
    expect(first.imageUrl).toBe('https://example.com/a.jpg');
    expect(first.publishedAt.toISOString()).toBe('2026-10-22T05:00:00.000Z');
  });

  it('drops items whose link is not a plain web link', () => {
    expect(parseFeed(rss, now).some((i) => i.title === 'Bad link')).toBe(false);
  });

  it('never trusts a date in the future', () => {
    const future = parseFeed(rss, now).find((i) => i.title === 'Future dated')!;
    expect(future.publishedAt.getTime()).toBeLessThanOrEqual(now.getTime());
  });

  it('parses Atom feeds', () => {
    const atom = `<feed xmlns="http://www.w3.org/2005/Atom"><entry>
      <title>Atom story</title>
      <link rel="alternate" href="https://example.com/atom-1"/>
      <updated>2026-10-22T10:00:00Z</updated>
      <summary>Short summary</summary>
    </entry></feed>`;
    const [item] = parseFeed(atom, now);
    expect(item.url).toBe('https://example.com/atom-1');
    expect(item.summary).toBe('Short summary');
  });

  it('survives garbage without throwing', () => {
    expect(parseFeed('this is not xml', now)).toEqual([]);
    expect(parseFeed('', now)).toEqual([]);
  });

  it('truncates long excerpts on a word boundary', () => {
    const long = 'word '.repeat(200);
    const out = toPlainExcerpt(long, 100)!;
    expect(out.length).toBeLessThanOrEqual(101);
    expect(out.endsWith('…')).toBe(true);
  });

  it('only accepts http(s) links', () => {
    expect(safeHttpUrl('https://a.com/x')).toBe('https://a.com/x');
    expect(safeHttpUrl('javascript:alert(1)')).toBeNull();
    expect(safeHttpUrl('data:text/html,hi')).toBeNull();
    expect(safeHttpUrl('not a url')).toBeNull();
  });
});
