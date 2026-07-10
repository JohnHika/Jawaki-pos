import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ChatRequestDto } from './dto/chat.dto';

@Injectable()
export class AiWebService {
  private readonly logger = new Logger(AiWebService.name);
  private readonly braveSearchApiKey: string;
  private readonly braveSearchUrl = 'https://api.search.brave.com/res/v1/web/search';

  constructor(private configService: ConfigService) {
    this.braveSearchApiKey = this.configService.get<string>('BRAVE_SEARCH_API_KEY') || '';
  }

  /**
   * Search the web for current business insights
   * Returns relevant information to enhance AI responses
   */
  async searchBusinessInsights(query: string): Promise<{
    insights: string[],
    sources: { url: string; title: string }[]
  }> {
    // Tier 1: Brave (sturdiest) when a key is configured.
    if (this.braveSearchApiKey) {
      try {
        const response = await fetch(`${this.braveSearchUrl}?q=${encodeURIComponent(query)}&count=5`, {
          headers: {
            'Accept': 'application/json',
            'X-Subscription-Token': this.braveSearchApiKey,
          },
        });

        if (response.ok) {
          const data = await response.json();
          const results = data.web?.results || [];
          if (results.length > 0) {
            return {
              insights: results.map(
                (item) => `• ${item.title}: ${item.description || 'No description available'}`,
              ),
              sources: results.map((item) => ({ url: item.url, title: item.title })),
            };
          }
        } else {
          this.logger.warn(`Brave search ${response.status}; trying DuckDuckGo.`);
        }
      } catch (error) {
        this.logger.warn(`Brave search failed (${error.message}); trying DuckDuckGo.`);
      }
    }

    // Tier 2: keyless DuckDuckGo HTML search — real live results, no API key.
    const ddg = await this.searchDuckDuckGo(query);
    if (ddg.sources.length > 0) return ddg;

    // Tier 3: curated cached insights as a last resort.
    this.logger.warn('No live web results; using cached insights.');
    return this.getCachedInsights(query);
  }

  /**
   * Keyless web search via DuckDuckGo's HTML endpoint. Scrapes the result
   * titles/snippets/links with a regex — no API key, no paid provider.
   * (Unofficial and best-effort; the tiered fallback above covers failures.)
   */
  private async searchDuckDuckGo(query: string): Promise<{
    insights: string[];
    sources: { url: string; title: string }[];
  }> {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 8000);
      const response = await fetch('https://html.duckduckgo.com/html/', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
        },
        body: `q=${encodeURIComponent(query)}`,
        signal: controller.signal,
      });
      clearTimeout(timeout);
      if (!response.ok) return { insights: [], sources: [] };

      const html = await response.text();
      const insights: string[] = [];
      const sources: { url: string; title: string }[] = [];

      // Each result: <a class="result__a" href="...">Title</a> with a
      // following <a class="result__snippet">snippet</a>.
      const linkRe =
        /<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
      const snippetRe =
        /<a[^>]*class="result__snippet"[^>]*>([\s\S]*?)<\/a>/g;

      const links: Array<{ url: string; title: string }> = [];
      let m: RegExpExecArray | null;
      while ((m = linkRe.exec(html)) !== null && links.length < 6) {
        const url = this.decodeDdgUrl(m[1]);
        const title = this.stripHtml(m[2]);
        if (url && title) links.push({ url, title });
      }
      const snippets: string[] = [];
      while ((m = snippetRe.exec(html)) !== null && snippets.length < 6) {
        snippets.push(this.stripHtml(m[1]));
      }

      links.forEach((link, i) => {
        sources.push(link);
        const snip = snippets[i] || '';
        insights.push(`• ${link.title}${snip ? `: ${snip}` : ''}`);
      });

      return { insights, sources };
    } catch (error) {
      this.logger.warn(`DuckDuckGo search failed: ${error.message}`);
      return { insights: [], sources: [] };
    }
  }

  private stripHtml(s: string): string {
    return s
      .replace(/<[^>]*>/g, '')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#x27;/g, "'")
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // DuckDuckGo wraps result links as /l/?uddg=<encoded-real-url>.
  private decodeDdgUrl(href: string): string {
    try {
      const match = href.match(/[?&]uddg=([^&]+)/);
      if (match) return decodeURIComponent(match[1]);
      if (href.startsWith('//')) return `https:${href}`;
      return href;
    } catch {
      return href;
    }
  }

  /**
   * Get cached insights based on query type
   * Used when web search is not available
   */
  private getCachedInsights(query: string): {
    insights: string[],
    sources: { url: string; title: string }[]
  } {
    const insights: string[] = [];
    const sources: { url: string; title: string }[] = [];

    if (query.toLowerCase().includes('kenya') && query.toLowerCase().includes('retail')) {
      insights.push(
        '• Kenyan retail is growing at 16.4% annually with e-commerce leading the way',
        '• Mobile money (M-Pesa) is essential - 90% of transactions use mobile payments',
        '• Digital receipts and loyalty programs are replacing paper systems',
        '• Smart retail analytics is becoming essential for competitive advantage'
      );

      sources.push(
        {
          url: 'https://www.dhl.com/discover/en-ke/small-business-advice/business-innovation-trends/embracing-modern-retail-in-kenya',
          title: 'Embracing Modern Retail in Kenya - DHL Kenya'
        },
        {
          url: 'https://www.e-startupskenya.co.ke/2025/12/09/the-future-of-smart-retail-analytics-in-kenya/',
          title: 'The Future of Smart Retail Analytics in Kenya - E-Startups Kenya'
        }
      );
    } else if (query.toLowerCase().includes('inventory')) {
      insights.push(
        '• Real-time inventory tracking reduces stockouts by 30-50%',
        '• ABC analysis helps focus on top 20% of products that generate 80% of revenue',
        '• Automated reorder alerts prevent lost sales from stockouts',
        '• Dead stock audits should be done monthly to free up capital'
      );
    } else if (query.toLowerCase().includes('customer') || query.toLowerCase().includes('loyalty')) {
      insights.push(
        '• Loyalty programs increase repeat purchases by 25-40%',
        '• SMS marketing has 92% open rate in Kenya - highly effective',
        '• Top 20% of customers typically generate 65-75% of revenue',
        '• Personalized offers based on purchase history increase conversion rates'
      );
    } else if (query.toLowerCase().includes('sales') || query.toLowerCase().includes('revenue')) {
      insights.push(
        '• Bundling products increases average transaction value by 8-12%',
        '• Peak hours (10 AM-2 PM, 5 PM-8 PM) account for 60-70% of daily sales',
        '• Psychological pricing (KES 99 vs KES 100) increases sales by 8-12%',
        '• Mobile money integration increases conversion rates by 15-20%'
      );
    }

    return { insights, sources };
  }

  /**
   * Enhance AI response with current web insights
   * Adds relevant, up-to-date information to make responses more valuable
   */
  async enhanceWithWebInsights(dto: ChatRequestDto): Promise<ChatRequestDto> {
    const enhancedDto = { ...dto };

    // Build a search query based on the user's question and context
    let searchQuery = enhancedDto.user_question || '';

    if (enhancedDto.business_context) {
      if (enhancedDto.business_context.business_type) {
        searchQuery += ` ${enhancedDto.business_context.business_type}`;
      }
      if (enhancedDto.business_context.branch && enhancedDto.business_context.branch.includes('Kenya')) {
        searchQuery += ' Kenya';
      }
    }

    if (searchQuery) {
      const insights = await this.searchBusinessInsights(searchQuery);

      // Add insights to data context if it exists, or create it
      if (!enhancedDto.data_context) {
        enhancedDto.data_context = {};
      }

      enhancedDto.data_context.web_insights = insights.insights;
      enhancedDto.data_context.web_sources = insights.sources;
    }

    return enhancedDto;
  }

  /**
   * Get current business trends for Kenya
   * Provides up-to-date market intelligence
   */
  async getCurrentKenyaRetailTrends(): Promise<{
    trends: string[],
    statistics: string[],
    sources: { url: string; title: string }[]
  }> {
    const result = await this.searchBusinessInsights('Kenya retail business trends 2025');

    // Extract trends and statistics from insights
    const trends: string[] = [];
    const statistics: string[] = [];

    result.insights.forEach(insight => {
      if (insight.match(/\d+%/)) {
        statistics.push(insight.replace('• ', ''));
      } else {
        trends.push(insight.replace('• ', ''));
      }
    });

    return {
      trends,
      statistics,
      sources: result.sources
    };
  }
}
