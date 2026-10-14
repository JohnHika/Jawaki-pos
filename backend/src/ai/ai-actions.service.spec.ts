import { AI_TOOL_PERMISSIONS, AiActionsService, canUseAiTool } from './ai-actions.service';

describe('canUseAiTool', () => {
  it('lets a tool through only when every required permission is held', () => {
    expect(canUseAiTool('get_profit_loss', ['reporting.profit_loss'])).toBe(true);
    expect(canUseAiTool('get_profit_loss', ['reporting.sales_summary'])).toBe(false);
    expect(canUseAiTool('record_shop_instalment', ['finance.view'])).toBe(false);
  });

  it('leaves tools that touch no business data open to everyone', () => {
    expect(canUseAiTool('ask_user_question', [])).toBe(true);
    expect(canUseAiTool('todo_write', [])).toBe(true);
  });

  it('is not enforced when permissions are undefined (internal callers)', () => {
    expect(canUseAiTool('get_profit_loss', undefined)).toBe(true);
  });

  it('gates every finance action behind a finance permission', () => {
    for (const name of ['get_shop_debts', 'add_shop_debt', 'record_shop_instalment']) {
      expect(AI_TOOL_PERMISSIONS[name]).toEqual([expect.stringMatching(/^finance\./)]);
    }
  });
});

describe('AiActionsService', () => {
  const ctx = {
    tenantId: 't1',
    branchId: 'b1',
    userId: 'u1',
    permissions: ['finance.view', 'finance.manage_receivables'],
  };
  let finance: any;
  let expenses: any;
  let service: AiActionsService;

  const debt = (id: string, outstanding: number, due: string | null, shop = 'd1') => ({
    id,
    debtor: { id: shop, name: 'Shop X' },
    description: `Debt ${id}`,
    originalAmount: outstanding,
    outstandingAmount: outstanding,
    dueDate: due,
    createdAt: '2026-01-01T00:00:00Z',
    payments: [],
  });

  beforeEach(() => {
    finance = {
      getPeerDebtors: jest.fn().mockResolvedValue([{ id: 'd1', name: 'Shop X' }]),
      getPeerReceivables: jest.fn().mockResolvedValue([
        debt('late', 2000, '2026-03-01T00:00:00Z'),
        debt('early', 1000, '2026-01-15T00:00:00Z'),
        debt('other-shop', 9999, null, 'd2'),
      ]),
      recordPeerBulkPayment: jest.fn(async (_u: string, _t: string, dto: any) => ({
        count: dto.allocations.length,
        totalAmount: dto.allocations.reduce((s: number, a: any) => s + a.amount, 0),
      })),
      createPeerDebtor: jest.fn().mockResolvedValue({ id: 'd9', name: 'New Shop' }),
      createPeerReceivable: jest.fn().mockResolvedValue({ id: 'debt-1' }),
    };
    expenses = { createExpense: jest.fn().mockResolvedValue({ id: 'e1', status: 'PENDING' }) };
    service = new AiActionsService(finance, expenses);
  });

  it('deducts an instalment from the oldest-due debt first, to the cent', async () => {
    const result: any = await service.executeMutation(
      'record_shop_instalment',
      { debtorId: 'd1', amount: 1500.5, method: 'cash' },
      ctx,
      'tool-1',
    );

    const dto = finance.recordPeerBulkPayment.mock.calls[0][2];
    expect(dto.allocations).toEqual([
      { receivableId: 'early', amount: 1000 },
      { receivableId: 'late', amount: 500.5 },
    ]);
    expect(dto.method).toBe('CASH');
    expect(dto.offlineId).toBe('ai-tool-1');
    expect(result.collected).toBe(1500.5);
    expect(result.balanceAfter).toBe(1499.5);
  });

  it('never touches another shop\'s debts', async () => {
    await service.executeMutation('record_shop_instalment', { debtorId: 'd1', amount: 3000, method: 'MPESA' }, ctx, 'k');
    const ids = finance.recordPeerBulkPayment.mock.calls[0][2].allocations.map((a: any) => a.receivableId);
    expect(ids).not.toContain('other-shop');
  });

  it('refuses an instalment larger than the balance and records nothing', async () => {
    await expect(
      service.executeMutation('record_shop_instalment', { debtorId: 'd1', amount: 3000.01, method: 'CASH' }, ctx, 'k'),
    ).rejects.toThrow(/more than the shop owes/);
    expect(finance.recordPeerBulkPayment).not.toHaveBeenCalled();
  });

  it('refuses a forged confirmation from a user without the permission', async () => {
    await expect(
      service.executeMutation(
        'record_shop_instalment',
        { debtorId: 'd1', amount: 100, method: 'CASH' },
        { ...ctx, permissions: ['finance.view'] },
        'k',
      ),
    ).rejects.toThrow(/permission/);
    expect(finance.recordPeerBulkPayment).not.toHaveBeenCalled();
  });

  it('rejects an unknown tool name that a client tried to smuggle in', async () => {
    await expect(service.executeMutation('delete_everything', {}, ctx, 'k')).rejects.toThrow(/not an action tool/);
  });

  it('validates input before the user is asked to confirm', () => {
    expect(service.validate('record_shop_instalment', { debtorId: 'd1', amount: -5, method: 'CASH' }).ok).toBe(false);
    expect(service.validate('record_shop_instalment', { debtorId: 'd1', amount: 5, method: 'BARTER' }).ok).toBe(false);
    expect(service.validate('add_shop_debt', { shopName: 'X', description: 'soap', amount: 100, dueDate: 'soon' }).ok).toBe(false);
    expect(service.validate('create_expense', { category: 'NOPE', amount: 5, description: 'd', supplier: 's' }).ok).toBe(false);
    const good = service.validate('create_expense', { category: 'transport', amount: 250, description: 'fuel', supplier: 'Shell' });
    expect(good.ok).toBe(true);
    expect(good.input?.category).toBe('TRANSPORT');
  });

  it('records a new shop debt and creates the shop if needed', async () => {
    const result: any = await service.executeMutation(
      'add_shop_debt',
      { shopName: 'New Shop', description: '100 cartons', amount: 150000 },
      ctx,
      'k',
    );
    expect(finance.createPeerDebtor).toHaveBeenCalledWith('t1', { name: 'New Shop' });
    expect(finance.createPeerReceivable.mock.calls[0][2]).toMatchObject({ debtorId: 'd9', amount: 150000, branchId: 'b1' });
    expect(result.debtId).toBe('debt-1');
  });

  it('names the shop on the confirmation card', async () => {
    const text = await service.describe('record_shop_instalment', { debtorId: 'd1', amount: 5000, method: 'CASH' }, ctx);
    expect(text).toContain('Shop X');
    expect(text).toContain('5,000');
  });

  it('reports each shop\'s original total, paid-so-far and balance', async () => {
    finance.getPeerReceivables.mockResolvedValue([
      { ...debt('a', 600, null), originalAmount: 1000, payments: [{ amount: 400, method: 'CASH', paidAt: '2026-02-01T10:00:00Z' }] },
    ]);
    const shops: any = await service.executeRead('get_shop_debts', {}, ctx);
    expect(shops[0]).toMatchObject({ originalTotal: 1000, paidSoFar: 400, balance: 600 });
    expect(shops[0].lastInstalment.amount).toBe(400);
  });
});
