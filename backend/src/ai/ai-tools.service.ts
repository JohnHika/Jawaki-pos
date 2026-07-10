import { Inject, Injectable, Logger, forwardRef } from '@nestjs/common';
import { ReportingService } from '../reporting/reporting.service';
import { InventoryService } from '../inventory/inventory.service';
import { ReportFilterDto, ReportPeriod } from '../reporting/dto/reporting.dto';

export interface AiToolDefinition {
  name: string;
  description: string;
  input_schema: {
    type: 'object';
    properties: Record<string, unknown>;
    required?: string[];
  };
  /** Mutating tools always pause the agent loop for user confirmation. */
  mutating: boolean;
}

export interface AiToolCallContext {
  tenantId: string;
  branchId?: string;
  userId?: string;
}

/**
 * Read/write POS actions the gateway's tool-calling loop can invoke mid
 * conversation, letting the AI pull fresher or more specific data than
 * what the mobile client pre-attaches to the request. Read tools execute
 * immediately server-side; the one mutating tool (create_stock_reorder)
 * is only ever invoked after the caller has resolved a confirm-before-mutate
 * round-trip — see AiService.chatViaAxonGatewayMessages().
 */
@Injectable()
export class AiToolsService {
  private readonly logger = new Logger(AiToolsService.name);

  constructor(
    private readonly reporting: ReportingService,
    @Inject(forwardRef(() => InventoryService))
    private readonly inventory: InventoryService,
  ) {}

  getToolDefinitions(): AiToolDefinition[] {
    return [
      {
        name: 'ask_user_question',
        description:
          'Ask the user one or more multiple-choice questions to gather information, clarify ambiguity, understand preferences, or offer them a decision to make. Use this whenever a request is ambiguous (e.g. which product/branch/date range) instead of guessing. The user will always be able to type a custom "Other" answer too.',
        mutating: false,
        input_schema: {
          type: 'object',
          properties: {
            questions: {
              type: 'array',
              minItems: 1,
              maxItems: 4,
              description: 'Questions to ask the user (1-4 questions).',
              items: {
                type: 'object',
                properties: {
                  question: {
                    type: 'string',
                    description: 'The complete question to ask, ending with a question mark.',
                  },
                  header: {
                    type: 'string',
                    description: 'Very short label (max 12 chars), e.g. "Product", "Branch".',
                  },
                  options: {
                    type: 'array',
                    minItems: 2,
                    maxItems: 4,
                    description: "2-4 distinct, mutually exclusive choices. Don't include an 'Other' option — it's added automatically.",
                    items: {
                      type: 'object',
                      properties: {
                        label: { type: 'string', description: 'Concise (1-5 words) display text.' },
                        description: { type: 'string', description: 'What this option means or implies.' },
                      },
                      required: ['label', 'description'],
                    },
                  },
                  multiSelect: { type: 'boolean', description: 'Allow selecting multiple answers. Defaults to false.' },
                },
                required: ['question', 'header', 'options'],
              },
            },
          },
          required: ['questions'],
        },
      },
      {
        name: 'get_sales_summary',
        description:
          "Get this shop's sales totals (revenue, transactions, average ticket, items sold) for a date range. Use this to answer questions about how sales performed over a specific period, especially when the period differs from what was already provided in the conversation context.",
        mutating: false,
        input_schema: {
          type: 'object',
          properties: {
            period: {
              type: 'string',
              enum: [
                'TODAY',
                'YESTERDAY',
                'THIS_WEEK',
                'LAST_WEEK',
                'THIS_MONTH',
                'LAST_MONTH',
                'THIS_QUARTER',
                'THIS_YEAR',
              ],
              description: 'Named date range. Omit if using startDate/endDate instead.',
            },
            startDate: { type: 'string', description: 'ISO date, inclusive. Use with endDate instead of period.' },
            endDate: { type: 'string', description: 'ISO date, inclusive. Use with startDate instead of period.' },
          },
        },
      },
      {
        name: 'get_low_stock_items',
        description:
          'Get the current list of products at or below their minimum stock threshold for this shop, sorted by most critical shortfall first. Use this to answer questions about what needs restocking right now.',
        mutating: false,
        input_schema: { type: 'object', properties: {} },
      },
      {
        name: 'get_top_products',
        description:
          'Get the best-selling products by revenue for a date range. Use this for questions about top/best-selling items over a specific period.',
        mutating: false,
        input_schema: {
          type: 'object',
          properties: {
            period: {
              type: 'string',
              enum: [
                'TODAY',
                'YESTERDAY',
                'THIS_WEEK',
                'LAST_WEEK',
                'THIS_MONTH',
                'LAST_MONTH',
                'THIS_QUARTER',
                'THIS_YEAR',
              ],
              description: 'Named date range. Omit if using startDate/endDate instead.',
            },
            startDate: { type: 'string', description: 'ISO date, inclusive. Use with endDate instead of period.' },
            endDate: { type: 'string', description: 'ISO date, inclusive. Use with startDate instead of period.' },
            limit: { type: 'number', description: 'Max products to return, default 5.' },
          },
        },
      },
      {
        name: 'create_stock_reorder',
        description:
          "Raise an internal stock request for a specific product at this branch, to be reviewed and approved by a supervisor. Only call this after the user has explicitly confirmed they want to raise the request — never call it speculatively. Always ask for the product and quantity first if either is unclear.",
        mutating: true,
        input_schema: {
          type: 'object',
          properties: {
            productId: { type: 'string', description: 'The product ID to reorder (from get_low_stock_items results, or already known from context).' },
            quantity: { type: 'number', description: 'Quantity to request.' },
            reason: { type: 'string', description: 'Short reason for the request, e.g. "Low stock, AI-assisted reorder".' },
            priority: { type: 'string', enum: ['low', 'normal', 'high'], description: 'Defaults to normal.' },
          },
          required: ['productId', 'quantity'],
        },
      },
    ];
  }

  /** Executes a single non-mutating tool call and returns its JSON-serializable result. */
  async executeReadTool(
    toolName: string,
    input: Record<string, any>,
    ctx: AiToolCallContext,
  ): Promise<unknown> {
    switch (toolName) {
      case 'get_sales_summary':
        return this.reporting.getSalesSummary(ctx.tenantId, this.toFilter(input, ctx));
      case 'get_low_stock_items':
        return this.inventory.getLowStockAlerts(ctx.tenantId, ctx.branchId);
      case 'get_top_products':
        return this.reporting.getTopProducts(
          ctx.tenantId,
          this.toFilter(input, ctx),
          typeof input?.limit === 'number' ? input.limit : 5,
        );
      default:
        throw new Error(`Unknown or non-read tool: ${toolName}`);
    }
  }

  /** Executes the one mutating tool. Only called after explicit user confirmation. */
  async executeStockReorder(
    input: { productId: string; quantity: number; reason?: string; priority?: string },
    ctx: AiToolCallContext,
  ): Promise<unknown> {
    if (!ctx.branchId) {
      throw new Error('No branch context available to raise a stock request.');
    }
    if (!ctx.userId) {
      throw new Error('No user context available to attribute this stock request.');
    }
    return this.inventory.createStockRequest(ctx.userId, ctx.tenantId, {
      branchId: ctx.branchId,
      productId: input.productId,
      quantity: input.quantity,
      reason: input.reason || 'AI-assisted reorder',
      priority: input.priority || 'normal',
    });
  }

  private toFilter(input: Record<string, any>, ctx: AiToolCallContext): ReportFilterDto {
    const filter = new ReportFilterDto();
    if (ctx.branchId) filter.branchId = ctx.branchId;
    if (input?.startDate && input?.endDate) {
      filter.startDate = input.startDate;
      filter.endDate = input.endDate;
    } else if (input?.period && Object.values(ReportPeriod).includes(input.period)) {
      filter.period = input.period as ReportPeriod;
    } else {
      filter.period = ReportPeriod.TODAY;
    }
    return filter;
  }
}
