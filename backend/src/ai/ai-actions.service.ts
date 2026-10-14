import { Injectable } from '@nestjs/common';
import { ExpensesService } from '../expenses/expenses.service';
import { ExpenseCategory } from '../expenses/dto/expenses.dto';
import { FinanceService } from '../finance/finance.service';

/** Context every agent tool call runs under. Mirrors AiToolCallContext. */
export interface AiActionContext {
  tenantId: string;
  branchId?: string;
  userId?: string;
  /** The caller's effective permissions. `undefined` means "not enforced" (tests/internal only). */
  permissions?: string[];
}

export interface AiActionToolDefinition {
  name: string;
  description: string;
  mutating: boolean;
  input_schema: {
    type: 'object';
    properties: Record<string, unknown>;
    required?: string[];
  };
}

/**
 * The permission a user must hold for the agent to use a tool on their behalf.
 *
 * The agent never has more authority than the person talking to it: a cashier
 * cannot ask it for profit figures, and it cannot record a collection for
 * someone who could not record one in the Finance screen. Tools missing from
 * this map (questions, todo list, plans) touch no business data.
 */
export const AI_TOOL_PERMISSIONS: Record<string, string[]> = {
  get_sales_summary: ['reporting.sales_summary'],
  get_top_products: ['reporting.top_products'],
  get_payment_breakdown: ['reporting.payment_breakdown'],
  get_sales_by_category: ['reporting.category_sales'],
  get_sales_trend: ['reporting.sales_trend'],
  get_sales_heatmap: ['reporting.sales_trend'],
  get_staff_performance: ['reporting.cashier_performance'],
  get_branch_comparison: ['reporting.branch_comparison'],
  get_profit_loss: ['reporting.profit_loss'],
  get_profit_by_product: ['reporting.profit_loss'],
  get_profit_by_category: ['reporting.profit_loss'],
  get_expenses_summary: ['reporting.profit_loss'],
  get_inventory_valuation: ['reporting.inventory_report'],
  get_slow_moving_stock: ['reporting.inventory_report'],
  get_restock_suggestions: ['reporting.inventory_report'],
  get_low_stock_items: ['reporting.inventory_report'],
  get_debtors: ['finance.view'],
  get_shop_debts: ['finance.view'],
  add_shop_debt: ['finance.manage_receivables'],
  record_shop_instalment: ['finance.manage_receivables'],
  generate_report: ['reporting.export'],
  generate_chart: ['reporting.dashboard'],
};

/** True when [permissions] allows [toolName]. `undefined` permissions = not enforced. */
export function canUseAiTool(toolName: string, permissions: string[] | undefined): boolean {
  if (permissions === undefined) return true;
  const required = AI_TOOL_PERMISSIONS[toolName];
  if (!required || required.length === 0) return true;
  return required.every((p) => permissions.includes(p));
}

const PAYMENT_METHODS = ['CASH', 'MPESA', 'CARD'] as const;
type PaymentMethod = (typeof PAYMENT_METHODS)[number];

const toCents = (value: number) => Math.round(value * 100);
const fromCents = (cents: number) => cents / 100;
const kes = (value: number) => `KES ${value.toLocaleString('en-KE', { maximumFractionDigits: 2 })}`;

type Validated<T> = { ok: boolean; input?: T; error?: string };

interface ShopDebtInput {
  shopName: string;
  description: string;
  amount: number;
  dueDate?: string;
}
interface InstalmentInput {
  debtorId: string;
  amount: number;
  method: PaymentMethod;
  reference?: string;
}
interface ExpenseInput {
  category: ExpenseCategory;
  amount: number;
  description: string;
  supplier: string;
  paymentMethod?: string;
}

@Injectable()
export class AiActionsService {
  constructor(
    private readonly finance: FinanceService,
    private readonly expenses: ExpensesService,
  ) {}

  /** Names of the action tools this service owns, mutating or not. */
  readonly toolNames = new Set(['get_shop_debts', 'add_shop_debt', 'record_shop_instalment', 'create_expense']);

  getToolDefinitions(): AiActionToolDefinition[] {
    return [
      {
        name: 'get_shop_debts',
        description:
          'Get what other (wholesale) shops owe this business: for each shop the original total, how much has been paid back, the balance, each open debt with its due date, and the most recent instalment. Call this first to find a shop\'s debtorId before recording an instalment or answering "how much does shop X still owe".',
        mutating: false,
        input_schema: { type: 'object', properties: {} },
      },
      {
        name: 'add_shop_debt',
        description:
          'Record goods or money another shop now owes this business (e.g. "Shop X took 100 cartons worth KES 150,000 on credit"). Creates the shop if it is new. The user is asked to confirm before anything is saved.',
        mutating: true,
        input_schema: {
          type: 'object',
          properties: {
            shopName: { type: 'string', description: 'Name of the shop that owes the money.' },
            description: { type: 'string', description: 'What the debt is for, e.g. "100 cartons of soap".' },
            amount: { type: 'number', description: 'Total amount owed in KES.' },
            dueDate: { type: 'string', description: 'Optional ISO date the shop promised to pay by.' },
          },
          required: ['shopName', 'description', 'amount'],
        },
      },
      {
        name: 'record_shop_instalment',
        description:
          'Record an instalment a shop has paid towards what it owes. The amount is deducted from that shop\'s debts, oldest due first, and logged with today\'s date. Use get_shop_debts first to get the debtorId. The user is asked to confirm before anything is saved.',
        mutating: true,
        input_schema: {
          type: 'object',
          properties: {
            debtorId: { type: 'string', description: 'debtorId from get_shop_debts.' },
            amount: { type: 'number', description: 'Amount collected in KES. Must not exceed the shop\'s balance.' },
            method: { type: 'string', enum: [...PAYMENT_METHODS], description: 'How it was paid.' },
            reference: { type: 'string', description: 'Optional reference such as an M-Pesa code.' },
          },
          required: ['debtorId', 'amount', 'method'],
        },
      },
      {
        name: 'create_expense',
        description:
          'Record a business expense (rent, transport, supplies…) for this branch. It goes into the normal expense approval flow. The user is asked to confirm before anything is saved.',
        mutating: true,
        input_schema: {
          type: 'object',
          properties: {
            category: { type: 'string', enum: Object.values(ExpenseCategory), description: 'Expense category.' },
            amount: { type: 'number', description: 'Amount in KES.' },
            description: { type: 'string', description: 'What it was for.' },
            supplier: { type: 'string', description: 'Who was paid.' },
            paymentMethod: { type: 'string', description: 'Optional: cash, M-Pesa, bank…' },
          },
          required: ['category', 'amount', 'description', 'supplier'],
        },
      },
    ];
  }

  // ---------------------------------------------------------------- reads

  async executeRead(name: string, _input: Record<string, any>, ctx: AiActionContext): Promise<unknown> {
    if (name !== 'get_shop_debts') throw new Error(`Unknown action tool: ${name}`);
    if (!ctx.branchId) throw new Error('No branch selected, so shop debts cannot be loaded.');
    const [shops, debts] = await Promise.all([
      this.finance.getPeerDebtors(ctx.tenantId),
      this.finance.getPeerReceivables(ctx.tenantId, ctx.branchId),
    ]);
    return shops.map((shop) => {
      const mine = debts.filter((d) => d.debtor.id === shop.id);
      const original = mine.reduce((s, d) => s + toCents(d.originalAmount), 0);
      const outstanding = mine.reduce((s, d) => s + toCents(d.outstandingAmount), 0);
      const lastPayment = mine
        .flatMap((d) => d.payments)
        .sort((a, b) => new Date(b.paidAt).getTime() - new Date(a.paidAt).getTime())[0];
      return {
        debtorId: shop.id,
        shop: shop.name,
        originalTotal: fromCents(original),
        paidSoFar: fromCents(original - outstanding),
        balance: fromCents(outstanding),
        openDebts: mine
          .filter((d) => d.outstandingAmount > 0)
          .map((d) => ({ description: d.description, balance: d.outstandingAmount, dueDate: d.dueDate })),
        lastInstalment: lastPayment
          ? { amount: lastPayment.amount, method: lastPayment.method, paidAt: lastPayment.paidAt }
          : null,
      };
    });
  }

  // ------------------------------------------------------------ mutations

  /** Checks a proposed mutating call BEFORE the user is asked to confirm it. */
  validate(name: string, input: Record<string, any>): Validated<Record<string, any>> {
    const text = (v: unknown) => (typeof v === 'string' ? v.trim() : '');
    const money = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.round(v * 100) / 100 : 0);

    if (name === 'add_shop_debt') {
      const value: ShopDebtInput = {
        shopName: text(input?.shopName),
        description: text(input?.description),
        amount: money(input?.amount),
        dueDate: text(input?.dueDate) || undefined,
      };
      if (!value.shopName) return { ok: false, error: 'shopName is required.' };
      if (!value.description) return { ok: false, error: 'description is required.' };
      if (!value.amount) return { ok: false, error: 'amount must be a number greater than zero.' };
      if (value.dueDate && Number.isNaN(Date.parse(value.dueDate))) {
        return { ok: false, error: 'dueDate must be an ISO date like 2026-12-31.' };
      }
      return { ok: true, input: { ...value } };
    }

    if (name === 'record_shop_instalment') {
      const method = text(input?.method).toUpperCase() as PaymentMethod;
      const value: InstalmentInput = {
        debtorId: text(input?.debtorId),
        amount: money(input?.amount),
        method,
        reference: text(input?.reference) || undefined,
      };
      if (!value.debtorId) return { ok: false, error: 'debtorId is required — call get_shop_debts to find it.' };
      if (!value.amount) return { ok: false, error: 'amount must be a number greater than zero.' };
      if (!PAYMENT_METHODS.includes(method)) {
        return { ok: false, error: `method must be one of ${PAYMENT_METHODS.join(', ')}.` };
      }
      return { ok: true, input: { ...value } };
    }

    if (name === 'create_expense') {
      const category = text(input?.category).toUpperCase() as ExpenseCategory;
      const value: ExpenseInput = {
        category,
        amount: money(input?.amount),
        description: text(input?.description),
        supplier: text(input?.supplier),
        paymentMethod: text(input?.paymentMethod) || undefined,
      };
      if (!Object.values(ExpenseCategory).includes(category)) {
        return { ok: false, error: `category must be one of ${Object.values(ExpenseCategory).join(', ')}.` };
      }
      if (!value.amount) return { ok: false, error: 'amount must be a number greater than zero.' };
      if (!value.description) return { ok: false, error: 'description is required.' };
      if (!value.supplier) return { ok: false, error: 'supplier is required.' };
      return { ok: true, input: { ...value } };
    }

    return { ok: false, error: `${name} is not an action tool.` };
  }

  /** Plain-language line shown on the confirmation card. */
  async describe(name: string, input: Record<string, any>, ctx: AiActionContext): Promise<string | null> {
    if (name === 'add_shop_debt') {
      return `Record that ${input.shopName} owes ${kes(input.amount)} for "${input.description}"${
        input.dueDate ? `, due ${new Date(input.dueDate).toDateString()}` : ''
      }?`;
    }
    if (name === 'record_shop_instalment') {
      const shops = await this.finance.getPeerDebtors(ctx.tenantId);
      const shop = shops.find((s) => s.id === input.debtorId)?.name ?? "the selected shop";
      return `Record an instalment of ${kes(input.amount)} (${String(input.method).toLowerCase()}) from ${shop} and deduct it from what they owe, oldest debt first?`;
    }
    if (name === 'create_expense') {
      return `Record a ${String(input.category).toLowerCase()} expense of ${kes(input.amount)} paid to ${input.supplier} for "${input.description}"?`;
    }
    return null;
  }

  /**
   * Runs a confirmed action. Re-validates the input and re-checks the caller's
   * permission here, because the pending call is echoed back by the client and
   * must never be trusted on its own.
   */
  async executeMutation(
    name: string,
    rawInput: Record<string, any>,
    ctx: AiActionContext,
    idempotencyKey: string,
  ): Promise<unknown> {
    if (!canUseAiTool(name, ctx.permissions)) {
      throw new Error('You do not have permission to do this.');
    }
    const checked = this.validate(name, rawInput);
    if (!checked.ok) throw new Error(checked.error);
    if (!ctx.userId) throw new Error('No user context available to attribute this action.');
    if (!ctx.branchId) throw new Error('No branch selected for this action.');

    if (name === 'add_shop_debt') return this.addShopDebt(checked.input as ShopDebtInput, ctx);
    if (name === 'record_shop_instalment') {
      return this.recordInstalment(checked.input as InstalmentInput, ctx, idempotencyKey);
    }
    if (name === 'create_expense') return this.createExpense(checked.input as ExpenseInput, ctx, idempotencyKey);
    throw new Error(`${name} is not an action tool.`);
  }

  private async addShopDebt(input: ShopDebtInput, ctx: AiActionContext) {
    const shop = await this.finance.createPeerDebtor(ctx.tenantId, { name: input.shopName } as any);
    const debt = await this.finance.createPeerReceivable(ctx.userId!, ctx.tenantId, {
      branchId: ctx.branchId!,
      debtorId: shop.id,
      description: input.description,
      amount: input.amount,
      dueDate: input.dueDate,
    } as any);
    return { shop: shop.name, debtId: (debt as any).id, amount: input.amount };
  }

  private async recordInstalment(input: InstalmentInput, ctx: AiActionContext, key: string) {
    const debts = (await this.finance.getPeerReceivables(ctx.tenantId, ctx.branchId!)).filter(
      (d) => d.debtor.id === input.debtorId && toCents(d.outstandingAmount) > 0,
    );
    if (debts.length === 0) throw new Error('That shop has nothing outstanding at this branch.');
    const owed = debts.reduce((s, d) => s + toCents(d.outstandingAmount), 0);
    let remaining = toCents(input.amount);
    if (remaining > owed) {
      throw new Error(`That is more than the shop owes (${kes(fromCents(owed))}). Nothing was recorded.`);
    }

    // Oldest due first; undated debts last; then oldest created.
    const ordered = [...debts].sort((a, b) => {
      const ad = a.dueDate ? new Date(a.dueDate).getTime() : Infinity;
      const bd = b.dueDate ? new Date(b.dueDate).getTime() : Infinity;
      if (ad !== bd) return ad - bd;
      return new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime();
    });
    const allocations: Array<{ receivableId: string; amount: number }> = [];
    for (const debt of ordered) {
      if (remaining <= 0) break;
      const applied = Math.min(remaining, toCents(debt.outstandingAmount));
      allocations.push({ receivableId: debt.id, amount: fromCents(applied) });
      remaining -= applied;
    }

    const result = await this.finance.recordPeerBulkPayment(ctx.userId!, ctx.tenantId, {
      branchId: ctx.branchId!,
      method: input.method,
      reference: input.reference,
      allocations,
      offlineId: `ai-${key}`,
    } as any);
    return {
      shop: debts[0].debtor.name,
      collected: result.totalAmount,
      balanceAfter: fromCents(owed - toCents(result.totalAmount)),
      debtsTouched: result.count,
    };
  }

  private async createExpense(input: ExpenseInput, ctx: AiActionContext, key: string) {
    const expense: any = await this.expenses.createExpense(ctx.userId!, ctx.tenantId, {
      category: input.category,
      amount: input.amount,
      branchId: ctx.branchId!,
      supplier: input.supplier,
      description: input.description,
      date: new Date().toISOString(),
      paymentMethod: input.paymentMethod,
      offlineId: `ai-${key}`,
    } as any);
    return { expenseId: expense.id, amount: input.amount, status: expense.status };
  }
}
