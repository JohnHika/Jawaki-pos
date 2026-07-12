import { Inject, Injectable, Logger, forwardRef } from '@nestjs/common';
import { ReportingService } from '../reporting/reporting.service';
import { InventoryService } from '../inventory/inventory.service';
import { ExpensesService } from '../expenses/expenses.service';
import { CustomersService } from '../customers/customers.service';
import { SalesService } from '../sales/sales.service';
import { ReportFilterDto, ReportPeriod, ReportGroupBy } from '../reporting/dto/reporting.dto';

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
 * what the mobile client pre-attaches to the request. A broad read-tool
 * suite (sales, products, profit, payments, expenses, customers, debtors,
 * stock health, staff, branches, trends, heatmap) backs the POS skill
 * library. Read tools execute immediately server-side; the one mutating
 * tool (create_stock_reorder) is only ever invoked after the caller has
 * resolved a confirm-before-mutate round-trip — see
 * AiService.chatViaAxonGatewayMessages().
 */
@Injectable()
export class AiToolsService {
  private readonly logger = new Logger(AiToolsService.name);

  constructor(
    private readonly reporting: ReportingService,
    @Inject(forwardRef(() => InventoryService))
    private readonly inventory: InventoryService,
    private readonly expenses: ExpensesService,
    private readonly customers: CustomersService,
    private readonly sales: SalesService,
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
        name: 'get_payment_breakdown',
        description:
          'Get how sales were paid for over a date range — the split across cash, M-Pesa, card, and credit (buy-now-pay-later). Use for cash-flow, cash-up, and "how are people paying" questions.',
        mutating: false,
        input_schema: this.periodSchema(),
      },
      {
        name: 'get_sales_by_category',
        description:
          'Get sales revenue broken down by product category for a date range, with each category\'s share of total. Use to see which parts of the shop drive revenue.',
        mutating: false,
        input_schema: this.periodSchema(),
      },
      {
        name: 'get_sales_trend',
        description:
          'Get the sales trend over time for a date range, grouped by hour, day, week, or month. Use for "how have sales moved", trend, and growth questions.',
        mutating: false,
        input_schema: this.periodSchema({
          groupBy: { type: 'string', enum: ['HOUR', 'DAY', 'WEEK', 'MONTH'], description: 'Time bucket. Defaults to DAY.' },
        }),
      },
      {
        name: 'get_sales_heatmap',
        description:
          'Get a day-of-week x hour-of-day grid of sales (revenue and transaction counts) over a date range, plus the single busiest slot. Use to find peak trading hours and quiet times worth a promotion.',
        mutating: false,
        input_schema: this.periodSchema(),
      },
      {
        name: 'get_staff_performance',
        description:
          "Get each cashier/staff member's sales performance (sales count, revenue, average ticket, refunds) over a date range. Use for staff comparison and performance questions.",
        mutating: false,
        input_schema: this.periodSchema(),
      },
      {
        name: 'get_branch_comparison',
        description:
          'Compare all branches of this shop over a date range (sales count, revenue, average ticket, top product per branch). Use for multi-branch and "which branch is doing best" questions.',
        mutating: false,
        input_schema: this.periodSchema(),
      },
      {
        name: 'get_profit_loss',
        description:
          'Get profit & loss for a date range: revenue, cost of goods sold, gross profit, gross margin, and net profit. Use for profit, margin, and bottom-line questions (not just top-line sales).',
        mutating: false,
        input_schema: this.periodSchema(),
      },
      {
        name: 'get_profit_by_product',
        description:
          'Get gross profit and margin for each product over a date range (revenue, cost, gross profit, margin %, units sold), sorted by profit. Use to find which products actually make money, not just which sell most.',
        mutating: false,
        input_schema: this.periodSchema({ limit: { type: 'number', description: 'Max products, default 10.' } }),
      },
      {
        name: 'get_profit_by_category',
        description:
          'Get gross profit and margin per product category over a date range. Use to see which categories are most/least profitable.',
        mutating: false,
        input_schema: this.periodSchema(),
      },
      {
        name: 'get_expenses_summary',
        description:
          'Get a summary of this shop\'s expenses over a date range, broken down by category and status. Use for expense, spending, and cost-control questions.',
        mutating: false,
        input_schema: this.periodSchema(),
      },
      {
        name: 'get_inventory_valuation',
        description:
          'Get the current inventory valuation for this shop: total stock value, plus counts of low-stock, out-of-stock, and overstock items. Use for "how much stock is on the shelf worth" and stock-health questions.',
        mutating: false,
        input_schema: { type: 'object', properties: {} },
      },
      {
        name: 'get_slow_moving_stock',
        description:
          'Get slow-moving / dead stock: products with stock on hand that have not sold within a number of days, sorted by tied-up cash value. Use to find stock quietly holding cash hostage that could be cleared.',
        mutating: false,
        input_schema: {
          type: 'object',
          properties: {
            daysWithoutSale: { type: 'number', description: 'Consider a product slow if unsold this many days. Default 30.' },
            limit: { type: 'number', description: 'Max products, default 20.' },
          },
        },
      },
      {
        name: 'get_restock_suggestions',
        description:
          'Get a budget-aware restock plan for this branch: which low-stock items to reorder, suggested quantities, and estimated cost, capped to available cash and prioritized by how fast they sell. Use for "what should I restock" and reorder-planning questions.',
        mutating: false,
        input_schema: { type: 'object', properties: {} },
      },
      {
        name: 'get_debtors',
        description:
          'Get who owes this shop money: outstanding credit (buy-now-pay-later) balances aggregated per customer, sorted by amount owed, with the oldest unpaid date. Use for debt collection and credit-risk questions.',
        mutating: false,
        input_schema: { type: 'object', properties: {} },
      },
      {
        name: 'get_top_customers',
        description:
          'Get this shop\'s highest-spending customers over a date range. Use for loyalty, VIP, and "who are my best customers" questions.',
        mutating: false,
        input_schema: this.periodSchema({ limit: { type: 'number', description: 'Max customers, default 10.' } }),
      },
      {
        name: 'get_inactive_customers',
        description:
          "Get customers who haven't bought in a while (no purchase for a number of days). Use for win-back campaigns and lapsed-customer questions.",
        mutating: false,
        input_schema: {
          type: 'object',
          properties: {
            inactiveDays: { type: 'number', description: 'Consider a customer inactive after this many days without a purchase. Default 60.' },
            limit: { type: 'number', description: 'Max customers, default 20.' },
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
        name: 'generate_report',
        description:
          'Generate a downloadable report file (PDF, Word/DOCX, or CSV) built from real shop data. Use this when the user explicitly asks for a document/file/report they can download or share — not for a question that can just be answered in chat. Always ask which format they want if they haven\'t said, unless they already specified it.',
        mutating: false,
        input_schema: {
          type: 'object',
          properties: {
            reportType: {
              type: 'string',
              enum: ['SALES_SUMMARY', 'TOP_PRODUCTS', 'PROFIT_LOSS', 'INVENTORY', 'PAYMENT_BREAKDOWN'],
              description: 'Which report to generate.',
            },
            format: {
              type: 'string',
              enum: ['PDF', 'DOCX', 'CSV'],
              description: 'File format the user wants.',
            },
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
              description: 'Date range for the report. Not used for INVENTORY (always current). Defaults to THIS_WEEK.',
            },
          },
          required: ['reportType', 'format'],
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
      case 'get_payment_breakdown':
        return this.reporting.getPaymentMethodBreakdown(ctx.tenantId, this.toFilter(input, ctx));
      case 'get_sales_by_category':
        return this.reporting.getCategorySales(ctx.tenantId, this.toFilter(input, ctx));
      case 'get_sales_trend':
        return this.reporting.getSalesTrend(ctx.tenantId, this.toFilter(input, ctx));
      case 'get_sales_heatmap':
        return this.reporting.getSalesHeatmap(ctx.tenantId, this.toFilter(input, ctx));
      case 'get_staff_performance':
        return this.reporting.getCashierPerformance(ctx.tenantId, this.toFilter(input, ctx));
      case 'get_branch_comparison':
        return this.reporting.getBranchComparison(ctx.tenantId, this.toFilter(input, ctx));
      case 'get_profit_loss':
        return this.reporting.getProfitAndLossRange(ctx.tenantId, this.toFilter(input, ctx));
      case 'get_profit_by_product':
        return this.reporting.getProfitByProduct(
          ctx.tenantId,
          this.toFilter(input, ctx),
          typeof input?.limit === 'number' ? input.limit : 10,
        );
      case 'get_profit_by_category':
        return this.reporting.getProfitByCategory(ctx.tenantId, this.toFilter(input, ctx));
      case 'get_expenses_summary': {
        const { startDate, endDate } = this.toDateRange(input, ctx);
        return this.expenses.getSummary(ctx.tenantId, ctx.branchId, startDate, endDate);
      }
      case 'get_inventory_valuation':
        return this.reporting.getInventoryReport(ctx.tenantId, ctx.branchId);
      case 'get_slow_moving_stock':
        return this.reporting.getSlowMovingProducts(
          ctx.tenantId,
          ctx.branchId,
          typeof input?.daysWithoutSale === 'number' ? input.daysWithoutSale : 30,
          typeof input?.limit === 'number' ? input.limit : 20,
        );
      case 'get_restock_suggestions':
        if (!ctx.branchId) throw new Error('A branch is required for restock suggestions.');
        return this.inventory.getRestockSuggestions(ctx.tenantId, ctx.branchId);
      case 'get_debtors':
        return this.sales.getDebtorsByCustomer(ctx.tenantId);
      case 'get_top_customers':
        return this.customers.getTopCustomers(
          ctx.tenantId,
          this.toFilter(input, ctx),
          typeof input?.limit === 'number' ? input.limit : 10,
        );
      case 'get_inactive_customers':
        return this.customers.getInactiveCustomers(
          ctx.tenantId,
          typeof input?.inactiveDays === 'number' ? input.inactiveDays : 60,
          typeof input?.limit === 'number' ? input.limit : 20,
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
    if (input?.groupBy && Object.values(ReportGroupBy).includes(input.groupBy)) {
      filter.groupBy = input.groupBy as ReportGroupBy;
    }
    return filter;
  }

  /** For services that take explicit startDate/endDate strings (e.g.
   * ExpensesService.getSummary) rather than a ReportFilterDto — resolves the
   * same period/date-range input into concrete ISO strings, defaulting to
   * the current month when nothing is specified. */
  private toDateRange(
    input: Record<string, any>,
    _ctx: AiToolCallContext,
  ): { startDate?: string; endDate?: string } {
    if (input?.startDate && input?.endDate) {
      return { startDate: input.startDate, endDate: input.endDate };
    }
    // ExpensesService.getSummary treats undefined dates as "all time", which
    // is a reasonable default for expense questions; a named period is
    // resolved to concrete bounds so the AI can still scope it.
    const period: ReportPeriod | undefined =
      input?.period && Object.values(ReportPeriod).includes(input.period)
        ? (input.period as ReportPeriod)
        : undefined;
    if (!period) return {};
    const now = new Date();
    let start: Date;
    const end = new Date(now);
    switch (period) {
      case ReportPeriod.TODAY:
        start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        break;
      case ReportPeriod.YESTERDAY:
        start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
        break;
      case ReportPeriod.THIS_WEEK:
        start = new Date(now);
        start.setDate(now.getDate() - now.getDay());
        break;
      case ReportPeriod.THIS_MONTH:
        start = new Date(now.getFullYear(), now.getMonth(), 1);
        break;
      case ReportPeriod.LAST_MONTH:
        start = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        break;
      case ReportPeriod.THIS_YEAR:
        start = new Date(now.getFullYear(), 0, 1);
        break;
      default:
        start = new Date(now.getFullYear(), now.getMonth(), 1);
    }
    return { startDate: start.toISOString(), endDate: end.toISOString() };
  }

  /** Shared JSON-schema builder for tools that accept a date range (a named
   * `period` OR explicit startDate/endDate), plus any extra properties. Keeps
   * the ~10 period-based tool schemas DRY. */
  private periodSchema(extra: Record<string, unknown> = {}): AiToolDefinition['input_schema'] {
    return {
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
        ...extra,
      },
    };
  }
}
