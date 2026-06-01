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
  private readonly model: string;

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
    const base = `You are POS AI, an intelligent business assistant for a POS (Point of Sale) system used by retail stores in Kenya.

Your role:
- Help store owners analyze sales, inventory, and customer data
- Provide actionable business insights
- Answer questions about running a retail business
- Be concise, practical, and use simple language
- Suggest ways to increase profit and reduce waste

Context: ${context || 'general business advice'}
${includeData ? 'Real-time store data will be included in follow-up messages.' : ''}

Keep responses under 500 words. Use bullet points for clarity. Format currency as KES.`;

    return base;
  }
}
