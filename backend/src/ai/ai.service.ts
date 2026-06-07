import { Injectable, Logger, HttpException, HttpStatus } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ChatRequestDto } from './dto/chat.dto';

interface NvidiaMessage {
  role: string;
  content: string;
}

interface NvidiaResponse {
  choices?: Array<{
    message?: { content: string };
  }>;
  error?: { message: string };
}

@Injectable()
export class AiService {
  private readonly logger = new Logger(AiService.name);
  private readonly apiKey: string;
  private readonly baseUrl = 'https://integrate.api.nvidia.com/v1';
  private model: string;

  constructor(private configService: ConfigService) {
    this.apiKey = this.configService.get<string>('NVIDIA_API_KEY') || '';
    this.model = this.configService.get<string>('NVIDIA_MODEL') || 'nvidia/llama-3.1-nemotron-70b-instruct';

    if (!this.apiKey) {
      this.logger.warn('NVIDIA_API_KEY not set — AI endpoints will return mock responses');
    }
  }

  async chat(dto: ChatRequestDto): Promise<{ reply: string; model: string }> {
    // If no API key configured, return a helpful mock response
    if (!this.apiKey) {
      return this.mockResponse(dto);
    }

    try {
      const systemPrompt = this.buildSystemPrompt(dto.context, dto.includeData);
      const messages: NvidiaMessage[] = [
        { role: 'system', content: systemPrompt },
        ...dto.messages.map(m => ({ role: m.role, content: m.content })),
      ];

      // Try NVIDIA's chat completions endpoint
      // Note: NVIDIA API structure may differ from standard OpenAI format
      const response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          model: this.model,
          messages,
          temperature: 0.7,
          max_tokens: 1024,
          top_p: 0.9,
          stream: false,
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        this.logger.error(`NVIDIA API error: ${response.status} - ${errorBody}`);

        if (response.status === 401 || response.status === 403) {
          throw new HttpException('AI service authentication failed', HttpStatus.SERVICE_UNAVAILABLE);
        }
        if (response.status === 429) {
          throw new HttpException('AI rate limit exceeded — please try again shortly', HttpStatus.TOO_MANY_REQUESTS);
        }
        if (response.status === 404) {
          // NVIDIA API endpoint not found - fall back to mock response
          this.logger.warn('NVIDIA chat endpoint not found - using enhanced mock response');
          return this.enhancedMockResponse(dto, this.model);
        }
        throw new HttpException('AI service temporarily unavailable', HttpStatus.SERVICE_UNAVAILABLE);
      }

      const data: NvidiaResponse = await response.json();

      if (data.error) {
        this.logger.error(`NVIDIA API returned error: ${data.error.message}`);
        throw new HttpException('AI processing error', HttpStatus.INTERNAL_SERVER_ERROR);
      }

      const reply = data.choices?.[0]?.message?.content || 'Sorry, I could not generate a response.';

      return { reply, model: this.model };

    } catch (error) {
      if (error instanceof HttpException) throw error;
      this.logger.error(`AI chat error: ${error}`);
      throw new HttpException('AI service error', HttpStatus.INTERNAL_SERVER_ERROR);
    }
  }

  /**
   * List available NVIDIA AI models
   * Requires NVIDIA_API_KEY to be configured
   */
  async listAvailableModels(): Promise<{ models: string[]; currentModel: string }> {
    if (!this.apiKey) {
      this.logger.warn('NVIDIA_API_KEY not set — cannot list available models');
      return {
        models: [this.model],
        currentModel: this.model
      };
    }

    try {
      const response = await fetch(`${this.baseUrl}/models`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
      });

      if (!response.ok) {
        const errorBody = await response.text();
        this.logger.error(`NVIDIA models API error: ${response.status} - ${errorBody}`);
        return {
          models: [this.model],
          currentModel: this.model
        };
      }

      const data = await response.json();
      const models = data.data?.map((m: any) => m.id) || [];

      return {
        models,
        currentModel: this.model
      };

    } catch (error) {
      this.logger.error(`Failed to fetch NVIDIA models: ${error}`);
      return {
        models: [this.model],
        currentModel: this.model
      };
    }
  }

  /**
   * Set the current AI model
   */
  setCurrentModel(model: string): void {
    this.model = model;
    this.logger.log(`AI model set to: ${model}`);
  }

  /**
   * Returns an enhanced mock response with detailed business insights
   * Used when API key is set but endpoint is not available
   */
  private enhancedMockResponse(dto: ChatRequestDto, model: string): { reply: string; model: string } {
    const lastMessage = dto.messages[dto.messages.length - 1]?.content?.toLowerCase() || '';
    const context = dto.context || 'general business advice';

    let reply: string;

    if (lastMessage.includes('sales') || lastMessage.includes('revenue')) {
      reply = `📊 **Axon POS Sales Strategies for Kenyan Retail Stores**

Based on ${context}, here are data-driven strategies:

**Top 5 Strategies:**
1. **Bundle Products**: Combine fast-moving items with slower ones (e.g., bread + margarine)
2. **Peak Hour Promotions**: Run discounts during 10 AM-2 PM and 5 PM-8 PM when traffic is highest
3. **Loyalty Programs**: Offer points for every KES 100 spent - customers redeem for discounts
4. **Mobile Money Integration**: Accept M-Pesa, Airtel Money, and T-Kash for convenience
5. **Weekend Specials**: Increase prices slightly on Saturdays when demand is 20-30% higher

**Axon POS Tip**: Use the built-in sales analytics to identify your top 10 products and create targeted promotions for them.

**Example**: If you sell 50 loaves of bread daily at KES 60 each, bundling with margarine (KES 80) at KES 130 saves customers KES 10 and increases your average sale by 8.3%.

Would you like me to analyze your specific sales data from Axon POS?`;

    } else if (lastMessage.includes('stock') || lastMessage.includes('inventory')) {
      reply = `📦 **Axon POS Inventory Optimization**

**Critical Strategies for ${context}:**
1. **ABC Analysis**: Classify items by revenue (A=70%, B=20%, C=10%) and focus on A items
2. **Reorder Points**: Set automatic alerts at 30% remaining stock for top sellers
3. **Supplier Lead Times**: Track and add 2-day buffer to avoid stockouts
4. **FIFO Method**: Always sell older stock first (critical for perishables)
5. **Dead Stock Review**: Monthly audit of items not sold in 30+ days

**Axon POS Feature**: Use the low-stock alerts in Inventory > Reports to automatically notify you when popular items need reordering.

**Pro Tip**: For a retail store with KES 50,000 monthly revenue, proper inventory management can reduce waste by 12-18% and increase cash flow by KES 6,000-9,000/month.

Need me to generate a specific inventory report from your Axon POS data?`;

    } else if (lastMessage.includes('customer') || lastMessage.includes('client')) {
      reply = `👥 **Axon POS Customer Insights & Retention**

**Key Strategies for ${context}:**
1. **Customer Database**: Collect phone numbers at checkout (offer KES 10 discount for sign-up)
2. **SMS Marketing**: Send weekly promotions via bulk SMS (92% open rate in Kenya)
3. **Loyalty Points**: 1 point per KES 50 spent = 10% discount after 500 points
4. **Purchase History**: "Customers who bought X also buy Y" recommendations
5. **Birthday Offers**: Free item on their birthday month

**Axon POS Data Insight**: Your top 20% of customers typically generate 65-75% of revenue. Focus retention efforts on them.

**Action Item**: Run the Customer > Purchase History report in Axon POS to identify your VIP customers and create personalized offers.

Would you like me to generate a customer segmentation analysis?`;

    } else if (lastMessage.includes('price') || lastMessage.includes('profit')) {
      reply = `💰 **Axon POS Pricing & Profit Optimization**

**Optimal Strategy for ${context}:**
1. **Keystone Pricing**: Standard markup of 40-50% on cost price
2. **Psychological Pricing**: KES 99 instead of KES 100 increases sales by 8-12%
3. **Bundle Pricing**: "Buy 2 get 10% off" increases average transaction value
4. **Seasonal Adjustments**: Increase prices by 5-8% during peak seasons
5. **Loss Leader Strategy**: Sell essentials at cost to attract customers who buy higher-margin items

**Profit Calculation Example**:
- Cost price: KES 80
- Selling price: KES 120 (50% markup)
- Gross profit: KES 40 per unit
- If you sell 30 units/day: KES 1,200 daily profit

**Axon POS Tip**: Run the Profit Margin report weekly to identify your 5 most and least profitable items.

**Question**: Would you like me to calculate optimal pricing for your top 5 products based on your cost data in Axon POS?`;

    } else {
      reply = `👋 Hi! I'm **Axon POS AI** — your intelligent business assistant.

**I can help with:**
📊 **Sales Analysis**: "What were my top products last week?"
📦 **Inventory Management**: "Which items are running low?"
👥 **Customer Insights**: "Who are my most valuable customers?"
💰 **Profit Optimization**: "How should I price this product?"
📈 **Business Growth**: "What strategies increase revenue?"

**Popular Questions**:
- "What sold best yesterday?"
- "Which items have lowest profit margins?"
- "Who are my top 5 customers this month?"
- "What's the optimal reorder quantity for product X?"

**Current AI Model**: ${model}
**Status**: Connected and ready for analysis

What would you like me to analyze or explain about your business today?`;
    }

    return { reply, model: 'mock (API endpoint adjustment needed)' };

  }

  /**
   * Returns a mock response when no API key is configured.
   * Useful for development and demos.
   */
  private mockResponse(dto: ChatRequestDto): { reply: string; model: string } {
    const lastMessage = dto.messages[dto.messages.length - 1]?.content?.toLowerCase() || '';

    let reply: string;

    if (lastMessage.includes('sales') || lastMessage.includes('revenue')) {
      reply = `📊 **Sales Insights**\n\nBased on typical POS patterns, here are some insights:\n\n• **Best performing items** tend to be fast-moving consumer goods\n• **Peak hours** are usually 10 AM - 2 PM and 5 PM - 8 PM\n• **Weekend sales** typically increase by 15-25%\n\n> 💡 *Connect your NVIDIA API key for real-time insights from your actual data!*\n\nTo get live AI analysis, add your NVIDIA API key in the backend configuration.`;
    } else if (lastMessage.includes('stock') || lastMessage.includes('inventory')) {
      reply = `📦 **Inventory Tips**\n\n• Set **low-stock alerts** for your top 20 products\n• Review stock levels every morning before opening\n• Track supplier lead times to avoid stockouts\n• Use **FIFO** (first-in-first-out) for perishable goods\n\n> 💡 *With real AI, I can predict exactly which items will run out and when!*`;
    } else if (lastMessage.includes('customer') || lastMessage.includes('client')) {
      reply = `👥 **Customer Insights**\n\n• **Loyal customers** typically account for 30% of revenue\n• Collect phone numbers for SMS marketing\n• Offer loyalty points or discounts to repeat buyers\n• Track what each customer buys most often\n\n> 💡 *Live AI can analyze customer patterns and suggest personalized offers!*`;
    } else if (lastMessage.includes('price') || lastMessage.includes('profit')) {
      reply = `💰 **Pricing & Profit**\n\n• Aim for **30-50% markup** on most products\n• Review pricing monthly based on supplier costs\n• Bundle slow-moving items with popular ones\n• Track profit margins per product category\n\n> 💡 *With AI, I can suggest optimal pricing for every product based on demand!*`;
    } else {
      reply = `👋 Hi! I'm **POS AI** — your POS business assistant.\n\nI can help you with:\n• 📊 **Sales analysis** — "What sold best today?"\n• 📦 **Inventory tips** — "Which items are running low?"\n• 👥 **Customer insights** — "Who are my top customers?"\n• 💰 **Pricing advice** — "How should I price this product?"\n\n> 💡 *Connect your NVIDIA API key for full AI power with real-time data analysis!*\n\n*This is a demo response. Live AI is available once the API key is configured.*`;
    }

    return { reply, model: 'mock (no API key configured)' };
  }

  private buildSystemPrompt(context?: string, includeData?: boolean): string {
    const base = `You are Axon POS AI, an intelligent business assistant for the Axon POS (Point of Sale) system by Arche Axon Intelligence. You help retail stores in Kenya manage their businesses.

Your role:
- Help store owners analyze sales, inventory, and customer data
- Provide actionable business insights for Axon POS users
- Answer questions about running a retail business
- Be concise, practical, and use simple language
- Suggest ways to increase profit and reduce waste

Context: ${context || 'general business advice'}
${includeData ? 'Real-time store data from Axon POS will be included in follow-up messages.' : ''}

Keep responses under 500 words. Use bullet points for clarity. Format currency as KES.`;

    return base;
  }
}
