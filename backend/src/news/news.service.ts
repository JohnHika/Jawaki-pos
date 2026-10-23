import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { LegacyUserRole, Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { NEWS_FEEDS, NewsFeed, OFFICIAL_LINKS } from './news.sources';
import { parseFeed } from './news.parser';
import { classifyNews, MIN_RELEVANCE_SCORE, NewsCategory } from './news.classify';

const FETCH_TIMEOUT_MS = 12_000;
const MAX_FEED_BYTES = 3 * 1024 * 1024;
const RETENTION_DAYS = 90;
/** After this many failed fetches in a row the source is flagged as broken. */
const BROKEN_AFTER = 6;
const PUSH_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const MAX_PUSHES_PER_REFRESH = 2;

export interface RefreshReport {
  sources: Array<{ key: string; ok: boolean; fetched: number; stored: number; error?: string }>;
  stored: number;
  pushed: number;
}

export interface NewsQuery {
  category?: string;
  impact?: string;
  q?: string;
  /** ISO date; only items published after it. */
  since?: string;
  page?: number;
  limit?: number;
}

@Injectable()
export class NewsService {
  private readonly logger = new Logger(NewsService.name);
  private refreshing = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
  ) {}

  @Cron('*/30 * * * *')
  async scheduledRefresh() {
    await this.refreshAll();
  }

  // ------------------------------------------------------------------- ingest

  /** Pulls every feed, keeps the relevant headlines, and pushes the urgent ones. */
  async refreshAll(): Promise<RefreshReport> {
    const report: RefreshReport = { sources: [], stored: 0, pushed: 0 };
    // Two overlapping runs (cron + a manual refresh) would double-push.
    if (this.refreshing) return report;
    this.refreshing = true;

    try {
      const hadItems = (await this.prisma.newsItem.count()) > 0;
      const created: Array<{ id: string; title: string; summary: string | null; impact: string; score: number; publishedAt: Date }> = [];

      for (const feed of NEWS_FEEDS) {
        const result = await this.ingest(feed);
        report.sources.push({
          key: feed.key,
          ok: result.ok,
          fetched: result.fetched,
          stored: result.created.length,
          error: result.error,
        });
        report.stored += result.created.length;
        created.push(...result.created);
      }

      await this.prisma.newsItem.deleteMany({
        where: { publishedAt: { lt: new Date(Date.now() - RETENTION_DAYS * 86_400_000) } },
      });

      // The very first run fills the table with weeks of old headlines; none
      // of those are "news" to the owner, so only later runs push.
      if (hadItems) report.pushed = await this.pushUrgent(created);
    } finally {
      this.refreshing = false;
    }
    return report;
  }

  private async ingest(feed: NewsFeed) {
    const created: Array<{ id: string; title: string; summary: string | null; impact: string; score: number; publishedAt: Date }> = [];
    let fetched = 0;
    try {
      const xml = await this.download(feed.url);
      const items = parseFeed(xml);
      fetched = items.length;

      const rows = items
        .map((item) => ({
          item,
          c: classifyNews(item.title, item.summary, feed.defaultCategory as NewsCategory | undefined),
        }))
        .filter(({ c }) => feed.official || c.score >= MIN_RELEVANCE_SCORE);

      if (rows.length > 0) {
        const existing = await this.prisma.newsItem.findMany({
          where: { url: { in: rows.map((r) => r.item.url) } },
          select: { url: true },
        });
        const known = new Set(existing.map((e) => e.url));

        for (const { item, c } of rows) {
          if (known.has(item.url)) continue;
          try {
            const row = await this.prisma.newsItem.create({
              data: {
                sourceKey: feed.key,
                sourceName: feed.name,
                title: item.title,
                summary: item.summary,
                url: item.url,
                imageUrl: item.imageUrl,
                publishedAt: item.publishedAt,
                category: c.category,
                tags: c.tags,
                // An official notice that matches no keyword is still worth
                // having, but is never "urgent".
                impact: c.score < MIN_RELEVANCE_SCORE ? 'LOW' : c.impact,
              },
              select: { id: true },
            });
            created.push({
              id: row.id,
              title: item.title,
              summary: item.summary,
              impact: c.impact,
              score: c.score,
              publishedAt: item.publishedAt,
            });
          } catch (error) {
            // Unique-url race with another instance: harmless.
            if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002')) throw error;
          }
        }
      }

      await this.markSource(feed, { ok: true });
      return { ok: true, fetched, created };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.logger.warn(`News source ${feed.key} failed: ${message}`);
      await this.markSource(feed, { ok: false, error: message });
      return { ok: false, fetched, created, error: message };
    }
  }

  private async download(url: string): Promise<string> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
      const response = await fetch(url, {
        signal: controller.signal,
        redirect: 'follow',
        headers: {
          'User-Agent': 'AxonPOS-NewsBot/1.0',
          Accept: 'application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.5',
        },
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const length = Number(response.headers.get('content-length') ?? 0);
      if (length > MAX_FEED_BYTES) throw new Error('Feed is too large');
      const text = await response.text();
      if (text.length > MAX_FEED_BYTES) throw new Error('Feed is too large');
      if (!/<(rss|feed)[\s>]/i.test(text.slice(0, 2000))) throw new Error('Not an RSS/Atom feed');
      return text;
    } finally {
      clearTimeout(timer);
    }
  }

  private async markSource(feed: NewsFeed, result: { ok: boolean; error?: string }) {
    try {
      const existing = await this.prisma.newsSource.findUnique({ where: { key: feed.key } });
      await this.prisma.newsSource.upsert({
        where: { key: feed.key },
        create: {
          key: feed.key,
          name: feed.name,
          url: feed.url,
          lastFetchedAt: result.ok ? new Date() : null,
          lastError: result.ok ? null : result.error?.slice(0, 300),
          consecutiveFailures: result.ok ? 0 : 1,
        },
        update: {
          name: feed.name,
          url: feed.url,
          ...(result.ok
            ? { lastFetchedAt: new Date(), lastError: null, consecutiveFailures: 0 }
            : {
                lastError: result.error?.slice(0, 300),
                consecutiveFailures: (existing?.consecutiveFailures ?? 0) + 1,
              }),
        },
      });
    } catch (error) {
      this.logger.warn(`Could not record health for ${feed.key}: ${error}`);
    }
  }

  /** Tells owners and managers about the few stories that change what they must do. */
  private async pushUrgent(
    created: Array<{ id: string; title: string; summary: string | null; impact: string; score: number; publishedAt: Date }>,
  ): Promise<number> {
    const urgent = created
      .filter((c) => c.impact === 'HIGH' && Date.now() - c.publishedAt.getTime() < PUSH_MAX_AGE_MS)
      .sort((a, b) => b.score - a.score)
      .slice(0, MAX_PUSHES_PER_REFRESH);
    if (urgent.length === 0) return 0;

    const tenants = await this.prisma.tenant.findMany({
      where: { isActive: true },
      select: { id: true, settings: true },
    });
    let pushed = 0;
    for (const tenant of tenants) {
      const prefs = (tenant.settings as Record<string, any> | null)?.news;
      if (prefs && prefs.pushHigh === false) continue;
      for (const story of urgent) {
        await this.notifications.sendToTenantRoles(
          tenant.id,
          [LegacyUserRole.ADMIN, LegacyUserRole.MANAGER],
          {
            title: 'Business news',
            body: story.title,
            data: { type: 'business_news', newsId: story.id },
          },
        );
        pushed++;
      }
    }
    return pushed;
  }

  // --------------------------------------------------------------------- read

  async list(query: NewsQuery) {
    const page = Math.max(query.page ?? 1, 1);
    const limit = Math.min(Math.max(query.limit ?? 20, 1), 50);
    const where: Prisma.NewsItemWhereInput = {};
    if (query.category) where.category = query.category;
    if (query.impact) where.impact = query.impact;
    if (query.since) {
      const d = new Date(query.since);
      if (!Number.isNaN(d.getTime())) where.publishedAt = { gt: d };
    }
    const q = query.q?.trim();
    if (q) {
      where.OR = [
        { title: { contains: q, mode: 'insensitive' } },
        { summary: { contains: q, mode: 'insensitive' } },
      ];
    }

    const [items, total, facets] = await Promise.all([
      this.prisma.newsItem.findMany({
        where,
        orderBy: [{ publishedAt: 'desc' }],
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.newsItem.count({ where }),
      this.prisma.newsItem.groupBy({
        by: ['category'],
        where: { publishedAt: { gt: new Date(Date.now() - 14 * 86_400_000) } },
        _count: { _all: true },
      }),
    ]);

    return {
      items: items.map((n) => this.shape(n)),
      total,
      page,
      limit,
      categories: facets.map((f) => ({ category: f.category, count: f._count._all })),
    };
  }

  /**
   * The short version for a home-screen card: what is urgent this week, and
   * the freshest headline in each topic.
   */
  async digest() {
    const weekAgo = new Date(Date.now() - 7 * 86_400_000);
    const [urgent, latest] = await Promise.all([
      this.prisma.newsItem.findMany({
        where: { impact: 'HIGH', publishedAt: { gt: weekAgo } },
        orderBy: { publishedAt: 'desc' },
        take: 5,
      }),
      this.prisma.newsItem.findMany({
        where: { publishedAt: { gt: new Date(Date.now() - 14 * 86_400_000) } },
        orderBy: { publishedAt: 'desc' },
        take: 60,
      }),
    ]);

    const perCategory = new Map<string, (typeof latest)[number]>();
    for (const n of latest) if (!perCategory.has(n.category)) perCategory.set(n.category, n);

    return {
      urgent: urgent.map((n) => this.shape(n)),
      byTopic: [...perCategory.values()].map((n) => this.shape(n)),
      generatedAt: new Date(),
    };
  }

  async sources() {
    const rows = await this.prisma.newsSource.findMany({ orderBy: { name: 'asc' } });
    return {
      feeds: rows.map((r) => ({
        key: r.key,
        name: r.name,
        lastFetchedAt: r.lastFetchedAt,
        lastError: r.lastError,
        healthy: r.consecutiveFailures < BROKEN_AFTER,
      })),
      official: OFFICIAL_LINKS,
      note: 'Headlines link to the original publisher. Check anything that affects your money with the official source before acting.',
    };
  }

  private shape(n: {
    id: string;
    sourceKey: string;
    sourceName: string;
    title: string;
    summary: string | null;
    url: string;
    imageUrl: string | null;
    publishedAt: Date;
    category: string;
    tags: string[];
    impact: string;
  }) {
    return {
      id: n.id,
      source: n.sourceName,
      sourceKey: n.sourceKey,
      title: n.title,
      summary: n.summary,
      url: n.url,
      imageUrl: n.imageUrl,
      publishedAt: n.publishedAt,
      category: n.category,
      tags: n.tags,
      impact: n.impact,
    };
  }
}
