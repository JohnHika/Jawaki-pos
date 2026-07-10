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

export interface SanitizedTodoItem {
  content: string;
  status: 'pending' | 'in_progress' | 'completed';
  activeForm: string;
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
      {
        name: 'todo_write',
        description:
          'Update the visible task checklist for the current multi-step request. Use proactively for any request with 3+ distinct steps, or when the user explicitly asks for a checklist — not for a single trivial question. Always include every task (not just changed ones): exactly one must be in_progress at a time, mark a task completed immediately when done (never batch), and never mark one completed if it failed or is only partially done.',
        mutating: false,
        input_schema: {
          type: 'object',
          properties: {
            todos: {
              type: 'array',
              description: 'The full current list of tasks, replacing whatever list existed before.',
              items: {
                type: 'object',
                properties: {
                  content: { type: 'string', description: 'Imperative form, e.g. "Check low stock items".' },
                  status: { type: 'string', enum: ['pending', 'in_progress', 'completed'] },
                  activeForm: { type: 'string', description: 'Present-continuous form shown while in progress, e.g. "Checking low stock items".' },
                },
                required: ['content', 'status', 'activeForm'],
              },
            },
          },
          required: ['todos'],
        },
      },
      {
        name: 'propose_plan',
        description:
          "Propose a short plan for a multi-step or ambiguous piece of work and pause for the user's approval before proceeding — use before taking several actions in sequence (e.g. checking several data points then raising a reorder), not for a single simple answer or a single tool call. Do not use ask_user_question to ask 'is this plan okay?' — this tool IS the approval request.",
        mutating: true,
        input_schema: {
          type: 'object',
          properties: {
            plan: {
              type: 'string',
              description: 'The plan, as short markdown (a few bullet points of what you intend to check/do, in order). Plain language, no more than ~6 steps.',
            },
          },
          required: ['plan'],
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
      case 'todo_write':
        // No server-side state to write to — the sanitized list is handed
        // back to AiService, which surfaces it in the /ai/chat response so
        // the client can render it; the client echoes it back on the next
        // turn via `todos` (stateless, like the rest of this tool suite).
        return this.sanitizeTodos(input?.todos);
      default:
        throw new Error(`Unknown or non-read tool: ${toolName}`);
    }
  }

  /** Coerces raw todo_write tool input into a strict shape.
   *
   * The model is inconsistent about field names for the task label across
   * calls with the exact same tool schema — `content`, `text`, `name`, and
   * `title` have all been observed live — and frequently omits `activeForm`.
   * Rather than maintaining an ever-growing alias list (whack-a-mole: each
   * new field name silently drops every item until patched), this resolves
   * the label from a preferred-key list and then falls back to the first
   * non-status string value on the object, so any reasonable shape the
   * model emits still yields a usable checklist item. activeForm is
   * backfilled from the label when missing (a checklist item without a
   * present-form label is still useful; only a genuinely unlabeled item
   * drops). */
  sanitizeTodos(raw: unknown): SanitizedTodoItem[] {
    const todosIn = Array.isArray(raw) ? raw : [];
    const validStatuses = new Set(['pending', 'in_progress', 'completed']);
    // Keys that are NOT the label, so the first-string-value fallback below
    // never mistakes them for the task text.
    const nonLabelKeys = new Set(['status', 'state', 'activeform', 'active_form', 'id', 'index', 'order', 'priority', 'done', 'completed']);

    const pickLabel = (t: any): string => {
      if (!t || typeof t !== 'object') {
        return typeof t === 'string' ? t.trim() : '';
      }
      for (const key of ['content', 'text', 'name', 'title', 'task', 'label', 'description', 'todo', 'item', 'step']) {
        if (typeof t[key] === 'string' && t[key].trim()) return t[key].trim();
      }
      // Fallback: first non-empty string value that isn't a known metadata key.
      for (const [key, val] of Object.entries(t)) {
        if (nonLabelKeys.has(key.toLowerCase())) continue;
        if (typeof val === 'string' && val.trim()) return val.trim();
      }
      return '';
    };

    const pickStatus = (t: any): SanitizedTodoItem['status'] => {
      const raw = (typeof t?.status === 'string' ? t.status : typeof t?.state === 'string' ? t.state : '')
        .toLowerCase()
        .trim()
        .replace(/[\s-]+/g, '_');
      if (validStatuses.has(raw)) return raw as SanitizedTodoItem['status'];
      if (raw === 'inprogress' || raw === 'active' || raw === 'doing' || raw === 'current') return 'in_progress';
      if (raw === 'done' || raw === 'complete' || raw === 'finished') return 'completed';
      if (t?.completed === true || t?.done === true) return 'completed';
      return 'pending';
    };

    return todosIn
      .map((t: any) => {
        const content = pickLabel(t);
        if (!content) return null;
        const activeForm =
          typeof t?.activeForm === 'string' && t.activeForm.trim()
            ? t.activeForm.trim()
            : typeof t?.active_form === 'string' && t.active_form.trim()
              ? t.active_form.trim()
              : content;
        return { content, status: pickStatus(t), activeForm };
      })
      .filter((t): t is SanitizedTodoItem => Boolean(t));
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
