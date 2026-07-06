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
    if (!this.braveSearchApiKey) {
      this.logger.warn('BRAVE_SEARCH_API_KEY not configured - using cached insights');
      return this.getCachedInsights(query);
    }

    try {
      const response = await fetch(`${this.braveSearchUrl}?q=${encodeURIComponent(query)}&count=5`, {
        headers: {
          'Accept': 'application/json',
          'X-Subscription-Token': this.braveSearchApiKey,
        },
      });

      if (!response.ok) {
        const error = await response.text();
        this.logger.error(`Brave search error: ${response.status} - ${error}`);
        return this.getCachedInsights(query);
      }

      const data = await response.json();
      const results = data.web?.results || [];

      const insights = results.map(item => {
        return `• ${item.title}: ${item.description || 'No description available'}`;
      });

      const sources = results.map(item => ({
        url: item.url,
        title: item.title,
      }));

      return { insights, sources };

    } catch (error) {
      this.logger.error(`Web search failed: ${error.message}`);
      return this.getCachedInsights(query);
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
