import { Injectable, Logger, HttpException, HttpStatus } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ChatMessageDto, ChatRequestDto } from './dto/chat.dto';

type NvidiaRole = 'system' | 'user' | 'assistant';

interface NvidiaMessage {
  role: NvidiaRole;
  content: string;
}

interface NvidiaResponse {
  choices?: Array<{
    message?: { content?: string };
  }>;
  error?: { message?: string };
}

interface AxonGatewayResponse {
  model?: string;
  plan?: string;
  response?: string;
  detail?: string;
}

interface BusinessResponse {
  summary: string;
  key_insights: string[];
  problems_detected: Array<{
    problem: string;
    impact: string;
    priority: 'high' | 'medium' | 'low';
  }>;
  recommended_actions: Array<{
    action: string;
    reason: string;
    expected_result: string;
  }>;
  growth_opportunities: string[];
  follow_up_questions: string[];
}

@Injectable()
export class AiService {
  private readonly logger = new Logger(AiService.name);
  // Axon Gateway (arche-axon.xyz) — primary provider. Own org/tier, routes to
  // whichever model that tier maps to; falls back to NVIDIA direct, then to
  // the local rule-based analysis if neither provider is reachable/configured.
  private readonly gatewayApiKey: string;
  private readonly gatewayBaseUrl: string;
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private model: string;

  constructor(private readonly configService: ConfigService) {
    this.gatewayApiKey = this.configService.get<string>('AXON_GATEWAY_API_KEY') || '';
    this.gatewayBaseUrl =
      this.configService.get<string>('AXON_GATEWAY_BASE_URL') ||
      'https://api.arche-axon.xyz/v1';

    this.apiKey = this.configService.get<string>('NVIDIA_API_KEY') || '';
    this.baseUrl =
      this.configService.get<string>('NVIDIA_API_BASE_URL') ||
      'https://integrate.api.nvidia.com/v1';
    this.model =
      this.configService.get<string>('NVIDIA_MODEL') ||
      'nvidia/nemotron-3-super-120b-a12b';

    if (!this.gatewayApiKey && !this.apiKey) {
      this.logger.warn('Neither AXON_GATEWAY_API_KEY nor NVIDIA_API_KEY set - AI endpoints will use local business responses');
    }
  }

  async chat(dto: ChatRequestDto): Promise<{ reply: string; model: string }> {
    const normalized = this.normalizeRequest(dto);

    if (this.gatewayApiKey) {
      const gatewayResult = await this.chatViaAxonGateway(normalized);
      if (gatewayResult) return gatewayResult;
      // Gateway configured but the call failed — fall through to NVIDIA
      // direct (if configured) rather than jumping straight to the local
      // canned response, so a transient gateway outage doesn't degrade
      // answer quality more than necessary.
    }

    if (!this.apiKey) {
      return this.localBusinessResponse(normalized, 'local-business-ai');
    }

    try {
      const response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          model: this.model,
          messages: this.buildMessages(normalized),
          temperature: 0.15,
          max_tokens: 1100,
          top_p: 0.7,
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
          throw new HttpException('AI rate limit exceeded. Please try again shortly.', HttpStatus.TOO_MANY_REQUESTS);
        }

        return this.localBusinessResponse(normalized, `${this.model} fallback`);
      }

      const data = (await response.json()) as NvidiaResponse;
      if (data.error) {
        this.logger.error(`NVIDIA API returned error: ${data.error.message || 'unknown error'}`);
        return this.localBusinessResponse(normalized, `${this.model} fallback`);
      }

      const reply = data.choices?.[0]?.message?.content?.trim();
      if (!reply) {
        return this.localBusinessResponse(normalized, `${this.model} fallback`);
      }

      return { reply, model: this.model };
    } catch (error) {
      if (error instanceof HttpException) {
        throw error;
      }

      this.logger.error(`AI chat error: ${error instanceof Error ? error.message : String(error)}`);
      return this.localBusinessResponse(normalized, `${this.model} fallback`);
    }
  }

  /// Calls the Axon Gateway's chat endpoint. Returns null (not a thrown
  /// error) on any failure so `chat()` can fall through to the next
  /// provider tier — a gateway hiccup should never surface as a hard
  /// error to the POS app when NVIDIA or the local fallback can still
  /// answer.
  private async chatViaAxonGateway(
    dto: ChatRequestDto,
  ): Promise<{ reply: string; model: string } | null> {
    try {
      const response = await fetch(`${this.gatewayBaseUrl}/chat/`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.gatewayApiKey}`,
        },
        body: JSON.stringify({
          // The gateway strips any client-supplied `system` message and
          // replaces it with its own mandatory Axon-identity prompt, so
          // the POS business-analysis instructions are sent as the first
          // user message instead — the one role it won't override.
          messages: this.buildGatewayMessages(dto),
          cache: false,
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text().catch(() => '');
        this.logger.error(`Axon Gateway error: ${response.status} - ${errorBody}`);
        return null;
      }

      const data = (await response.json()) as AxonGatewayResponse;
      const reply = data.response?.trim();
      if (!reply) {
        this.logger.error('Axon Gateway returned an empty response');
        return null;
      }

      return { reply, model: data.model || 'axon-gateway' };
    } catch (error) {
      this.logger.error(`Axon Gateway request failed: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  private buildGatewayMessages(dto: ChatRequestDto): Array<{ role: string; content: string }> {
    const systemPrompt = this.buildSystemPrompt(dto);
    const conversation = (dto.messages || [])
      .filter((message) => Boolean(message?.content) && message.role !== 'system')
      .map((message) => ({
        role: ['user', 'assistant'].includes(message.role) ? message.role : 'user',
        content: message.content,
      }));

    const messages: Array<{ role: string; content: string }> = [
      { role: 'user', content: systemPrompt },
    ];

    if (conversation.length > 0) {
      messages.push(...conversation);
    } else {
      messages.push({ role: 'user', content: this.buildStructuredUserMessage(dto) });
    }

    if (dto.data_context || dto.business_context) {
      messages.push({ role: 'user', content: this.buildStructuredUserMessage(dto) });
    }

    return messages;
  }

  async listAvailableModels(): Promise<{ models: string[]; currentModel: string }> {
    if (!this.apiKey) {
      return {
        models: [this.model],
        currentModel: this.model,
      };
    }

    try {
      const response = await fetch(`${this.baseUrl}/models`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`,
        },
      });

      if (!response.ok) {
        this.logger.warn(`NVIDIA models request failed with ${response.status}`);
        return { models: [this.model], currentModel: this.model };
      }

      const data = await response.json();
      const models = Array.isArray(data?.data)
        ? data.data.map((model: { id?: string }) => model.id).filter(Boolean)
        : [];

      return {
        models: models.length > 0 ? models : [this.model],
        currentModel: this.model,
      };
    } catch (error) {
      this.logger.error(`Failed to fetch NVIDIA models: ${error instanceof Error ? error.message : String(error)}`);
      return { models: [this.model], currentModel: this.model };
    }
  }

  setCurrentModel(model: string): void {
    if (!model?.trim()) {
      throw new HttpException('Model is required', HttpStatus.BAD_REQUEST);
    }

    this.model = model.trim();
    this.logger.log(`AI model set to: ${this.model}`);
  }

  getCurrentModel(): string {
    return this.model;
  }

  private normalizeRequest(dto: ChatRequestDto): ChatRequestDto {
    const messages = Array.isArray(dto.messages) ? dto.messages : [];
    const lastUserMessage = [...messages].reverse().find((message) => message.role === 'user');
    const userQuestion = dto.user_question?.trim() || lastUserMessage?.content?.trim() || '';

    return {
      ...dto,
      messages,
      user_question: userQuestion,
      context: dto.context || 'general',
      includeData: dto.includeData ?? Boolean(dto.data_context),
      ai_task: dto.ai_task || 'analyze_and_recommend',
      response_style: dto.response_style || 'actionable_partner',
    };
  }

  private buildMessages(dto: ChatRequestDto): NvidiaMessage[] {
    const messages: NvidiaMessage[] = [
      {
        role: 'system',
        content: this.buildSystemPrompt(dto),
      },
    ];

    const conversation = (dto.messages || [])
      .filter((message) => Boolean(message?.content))
      .map((message) => this.toNvidiaMessage(message));

    if (conversation.length > 0) {
      messages.push(...conversation);
    } else {
      messages.push({
        role: 'user',
        content: this.buildStructuredUserMessage(dto),
      });
    }

    if (dto.data_context || dto.business_context) {
      messages.push({
        role: 'user',
        content: this.buildStructuredUserMessage(dto),
      });
    }

    return messages;
  }

  private toNvidiaMessage(message: ChatMessageDto): NvidiaMessage {
    const role = ['system', 'user', 'assistant'].includes(message.role)
      ? (message.role as NvidiaRole)
      : 'user';

    return {
      role,
      content: message.content,
    };
  }

  private buildStructuredUserMessage(dto: ChatRequestDto): string {
    const parts = [`Question: ${dto.user_question || 'Analyze my business and recommend next steps.'}`];

    if (dto.business_context) {
      parts.push(`Business context: ${JSON.stringify(dto.business_context)}`);
    }

    if (dto.data_context) {
      parts.push(`Available POS data: ${JSON.stringify(dto.data_context)}`);
    }

    return parts.join('\n');
  }

  private buildSystemPrompt(dto: ChatRequestDto): string {
    const styleInstruction =
      dto.response_style === 'detailed_report'
        ? 'Give enough detail for an owner to act without needing another report.'
        : dto.response_style === 'concise'
          ? 'Keep the answer short and focused.'
          : 'Be specific, practical, and action-oriented.';

    return `You are Axon POS AI, a business growth partner for POS users in Kenya.

Analyze sales, inventory, customers, staff activity, expenses, and branch performance. Detect risks and opportunities, then recommend specific next steps with expected business impact.

Response rules:
- Use plain business language.
- Format currency as KES.
- Prefer concrete recommendations over generic advice.
- Do not invent sales, stock, customer, staff, or payment facts.
- If the POS data does not include something, say the data is not available and explain what would be needed.
- If POS data is provided, base the answer on that data.
- If data is missing, say what data would improve the answer and still provide useful guidance.
- ${styleInstruction}

Current context: ${dto.context || 'general'}
AI task: ${dto.ai_task || 'analyze_and_recommend'}
Real POS data included: ${dto.includeData ? 'yes' : 'no'}`;
  }

  private localBusinessResponse(dto: ChatRequestDto, model: string): { reply: string; model: string } {
    const response = this.buildLocalBusinessAnalysis(dto);
    const reply = this.formatBusinessResponse(response);

    return { reply, model };
  }

  private buildLocalBusinessAnalysis(dto: ChatRequestDto): BusinessResponse {
    const question = (dto.user_question || '').toLowerCase();
    const data = dto.data_context || {};
    const business = dto.business_context || {};
    const branch = business.branch || dto.storeId || 'this branch';
    const totalSales = this.toNumber(data.total_sales ?? data.sales?.total_sales);
    const transactions = this.toNumber(data.transactions ?? data.sales?.transactions);
    const topProducts = this.toArray(data.top_products ?? data.sales?.top_products);
    const lowStockItems = this.toArray(data.low_stock_items ?? data.inventory?.low_stock_items);
    const slowMovingItems = this.toArray(data.slow_moving_items ?? data.inventory?.slow_moving_items);

    const averageBasket = totalSales && transactions ? Math.round(totalSales / transactions) : undefined;
    const focus = this.detectFocus(question, dto.context);

    const keyInsights: string[] = [];
    const problems: BusinessResponse['problems_detected'] = [];
    const actions: BusinessResponse['recommended_actions'] = [];
    const growth: string[] = [];

    if (totalSales) {
      keyInsights.push(`${branch} has recorded KES ${totalSales.toLocaleString('en-KE')} in sales for the selected period.`);
    }

    if (averageBasket) {
      keyInsights.push(`Average transaction value is about KES ${averageBasket.toLocaleString('en-KE')}.`);
    }

    if (topProducts.length > 0) {
      const names = topProducts.slice(0, 3).map((item) => item.name || item.productName || 'Unnamed product').join(', ');
      keyInsights.push(`Top moving products are ${names}.`);
    }

    if (lowStockItems.length > 0) {
      problems.push({
        problem: `${lowStockItems.length} item(s) are below safe stock levels.`,
        impact: 'Fast-moving products may stock out and cause lost sales.',
        priority: 'high',
      });
      actions.push({
        action: `Restock ${this.describeItems(lowStockItems)} first.`,
        reason: 'These items are most likely to block sales if they run out.',
        expected_result: 'Fewer lost sales and better customer satisfaction.',
      });
    }

    if (slowMovingItems.length > 0) {
      problems.push({
        problem: `${slowMovingItems.length} item(s) are slow-moving.`,
        impact: 'Cash is tied up in products that are not converting quickly.',
        priority: lowStockItems.length > 0 ? 'medium' : 'high',
      });
      actions.push({
        action: `Create a bundle or small discount for ${this.describeItems(slowMovingItems)}.`,
        reason: 'Bundling slow items with fast movers clears stock without training customers to wait for discounts.',
        expected_result: 'Improved cash flow and cleaner inventory.',
      });
    }

    if (focus === 'sales' || focus === 'general') {
      actions.push({
        action: 'Run a peak-hour promotion on the top 3 products.',
        reason: 'Focused promotions on already-moving products usually lift basket value faster than broad discounts.',
        expected_result: 'Higher daily revenue and stronger repeat traffic.',
      });
      growth.push('Track top products weekly and create bundles that pair fast movers with higher-margin add-ons.');
    }

    if (focus === 'customers' || question.includes('loyalty')) {
      actions.push({
        action: 'Start a simple loyalty offer for repeat customers.',
        reason: 'A small reward gives customers a reason to return and lets staff collect customer details at checkout.',
        expected_result: 'Better retention and more useful customer purchase history.',
      });
      growth.push('Segment customers into new, repeat, and inactive groups before sending offers.');
    }

    if (keyInsights.length === 0) {
      keyInsights.push('No live POS totals were included, so this answer is based on business operating patterns.');
    }

    if (problems.length === 0) {
      problems.push({
        problem: 'Limited live sales and stock data was provided to the assistant.',
        impact: 'Recommendations are useful but less precise than they could be.',
        priority: 'medium',
      });
    }

    if (actions.length === 0) {
      actions.push({
        action: 'Review today sales, low-stock products, and inactive customers before closing.',
        reason: 'These three checks catch the most common daily retail problems.',
        expected_result: 'Better stock control and clearer next-day priorities.',
      });
    }

    growth.push('Use M-Pesa-friendly checkout messaging and receipt follow-ups to improve repeat purchases.');
    growth.push('Review profit margin by category, not just total sales, so discounts do not hide weak margins.');

    return {
      summary: this.buildSummary(branch, focus, totalSales, transactions),
      key_insights: keyInsights.slice(0, 4),
      problems_detected: problems.slice(0, 3),
      recommended_actions: actions.slice(0, 4),
      growth_opportunities: [...new Set(growth)].slice(0, 4),
      follow_up_questions: [
        'Do you want me to focus next on sales, stock, customers, or profit margin?',
      ],
    };
  }

  private buildSummary(branch: string, focus: string, totalSales?: number, transactions?: number): string {
    const salesText = totalSales
      ? `KES ${totalSales.toLocaleString('en-KE')}${transactions ? ` from ${transactions} transaction(s)` : ''}`
      : 'the available POS activity';

    return `For ${branch}, I reviewed ${salesText} with a ${focus} focus. The best next step is to protect fast-moving stock, improve basket value, and turn slow stock back into cash.`;
  }

  private formatBusinessResponse(response: BusinessResponse): string {
    const lines = [
      `**Summary**`,
      response.summary,
      '',
      `**Key insights**`,
      ...response.key_insights.map((item) => `- ${item}`),
      '',
      `**Problems detected**`,
      ...response.problems_detected.map((item) => `- ${item.problem} Impact: ${item.impact} Priority: ${item.priority}.`),
      '',
      `**Recommended actions**`,
      ...response.recommended_actions.map((item) => `- ${item.action} Reason: ${item.reason} Expected result: ${item.expected_result}`),
      '',
      `**Growth opportunities**`,
      ...response.growth_opportunities.map((item) => `- ${item}`),
      '',
      `**Follow-up**`,
      `- ${response.follow_up_questions[0]}`,
    ];

    return lines.join('\n');
  }

  private detectFocus(question: string, context?: string): string {
    if (context && context !== 'general') {
      return context;
    }

    if (question.includes('stock') || question.includes('inventory') || question.includes('reorder')) {
      return 'inventory';
    }

    if (question.includes('customer') || question.includes('client') || question.includes('loyalty')) {
      return 'customers';
    }

    if (question.includes('profit') || question.includes('margin') || question.includes('price')) {
      return 'profit';
    }

    if (question.includes('sale') || question.includes('revenue') || question.includes('sold')) {
      return 'sales';
    }

    return 'general';
  }

  private toNumber(value: unknown): number | undefined {
    const numberValue = Number(value);
    return Number.isFinite(numberValue) && numberValue > 0 ? numberValue : undefined;
  }

  private toArray(value: unknown): Array<Record<string, any>> {
    return Array.isArray(value) ? value : [];
  }

  private describeItems(items: Array<Record<string, any>>): string {
    if (items.length === 0) {
      return 'priority items';
    }

    return items
      .slice(0, 3)
      .map((item) => item.name || item.productName || item.sku || 'Unnamed product')
      .join(', ');
  }
}
