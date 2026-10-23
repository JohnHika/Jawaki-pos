import { ForbiddenException } from '@nestjs/common';
import { AccountabilityService, AssessSaleParams } from './accountability.service';

function build(opts: {
  settings?: Record<string, unknown>;
  permissions?: string[];
  customer?: { id: string; name: string; creditLimit: number | null } | null;
  receivables?: Array<{ outstandingAmount: number; dueDate: Date | null }>;
}) {
  const prisma: any = {
    tenant: { findUnique: jest.fn().mockResolvedValue({ settings: { accountability: opts.settings ?? {} } }) },
    customer: { findFirst: jest.fn().mockResolvedValue(opts.customer ?? null) },
    retailReceivable: { findMany: jest.fn().mockResolvedValue(opts.receivables ?? []) },
    accountabilityAlert: { create: jest.fn().mockResolvedValue({}) },
    user: { findUnique: jest.fn().mockResolvedValue({ firstName: 'Faith', lastName: 'Atieno' }) },
    product: { findMany: jest.fn().mockResolvedValue([]) },
  };
  const audit: any = { record: jest.fn() };
  const notifications: any = { sendToTenantRoles: jest.fn() };
  const permissions: any = { getEffectivePermissions: jest.fn().mockResolvedValue(opts.permissions ?? []) };
  return {
    service: new AccountabilityService(prisma, audit, notifications, permissions),
    prisma,
    audit,
    notifications,
  };
}

const sale = (over: Partial<AssessSaleParams> = {}): AssessSaleParams => ({
  userId: 'cashier-1',
  tenantId: 't1',
  branchId: 'b1',
  customerId: null,
  overallDiscount: 0,
  creditAmount: 0,
  enforce: true,
  lines: [
    { productId: 'p1', name: 'Sufuria', quantity: 1, unitPrice: 250, discount: 0, costPrice: 300, minPrice: null },
  ],
  ...over,
});

describe('AccountabilityService.assessSale', () => {
  it('flags a below-cost sale but lets it through in the default FLAG mode', async () => {
    const { service } = build({});
    const r = await service.assessSale(sale());
    expect(r.violations.map((v) => v.code)).toEqual(['BELOW_COST']);
    expect(r.blocked).toBe(false);
  });

  it('blocks a live below-cost sale in BLOCK mode for a cashier', async () => {
    const { service } = build({ settings: { priceGuard: { mode: 'BLOCK' } } });
    const r = await service.assessSale(sale());
    expect(r.blocked).toBe(true);
  });

  it('never blocks a sale that came from the offline queue — it already happened at the counter', async () => {
    const { service } = build({ settings: { priceGuard: { mode: 'BLOCK' } } });
    const r = await service.assessSale(sale({ enforce: false }));
    expect(r.violations).toHaveLength(1);
    expect(r.blocked).toBe(false);
  });

  it('lets someone holding sales.price_override sell below cost even in BLOCK mode', async () => {
    const { service } = build({
      settings: { priceGuard: { mode: 'BLOCK' } },
      permissions: ['sales.price_override'],
    });
    const r = await service.assessSale(sale());
    expect(r.violations).toHaveLength(1);
    expect(r.blocked).toBe(false);
  });

  it('blocks credit over the customer limit in BLOCK mode and reports the numbers', async () => {
    const { service } = build({
      settings: { credit: { mode: 'BLOCK' } },
      customer: { id: 'c1', name: 'Mama Njeri', creditLimit: 5000 },
      receivables: [{ outstandingAmount: 4500, dueDate: null }],
    });
    const r = await service.assessSale(
      sale({ customerId: 'c1', creditAmount: 1000, lines: [] }),
    );
    expect(r.blocked).toBe(true);
    expect(r.violations[0].code).toBe('CREDIT_LIMIT_EXCEEDED');
    expect(r.violations[0].message).toMatch(/Mama Njeri/);
  });

  it('measures how overdue a customer is from their oldest unpaid balance', async () => {
    const { service } = build({
      settings: { credit: { mode: 'FLAG', blockWhenOverdueDays: 30 } },
      customer: { id: 'c1', name: 'Mama Njeri', creditLimit: null },
      receivables: [
        { outstandingAmount: 100, dueDate: new Date(Date.now() - 10 * 86_400_000) },
        { outstandingAmount: 100, dueDate: new Date(Date.now() - 50 * 86_400_000) },
      ],
    });
    const r = await service.assessSale(sale({ customerId: 'c1', creditAmount: 100, lines: [] }));
    expect(r.violations.map((v) => v.code)).toContain('CREDIT_OVERDUE');
  });

  it('does not query anything when both guards are OFF', async () => {
    const { service, prisma } = build({
      settings: { priceGuard: { mode: 'OFF' }, credit: { mode: 'OFF' } },
    });
    const r = await service.assessSale(sale());
    expect(r).toEqual({ violations: [], blocked: false });
    expect(prisma.customer.findFirst).not.toHaveBeenCalled();
  });

  it('lets the sale through if the check itself blows up — the till must not stop', async () => {
    const { service, prisma } = build({});
    prisma.tenant.findUnique.mockRejectedValue(new Error('db down'));
    const r = await service.assessSale(sale());
    expect(r).toEqual({ violations: [], blocked: false });
  });
});

describe('AccountabilityService.refuse', () => {
  it('throws a structured 403 listing only the blocking reasons', () => {
    const { service } = build({});
    try {
      service.refuse([
        { code: 'BELOW_COST', severity: 'HIGH', message: 'Too cheap', blockable: true },
        { code: 'DISCOUNT_LIMIT', severity: 'LOW', message: 'Fine', blockable: false },
      ]);
      fail('should have thrown');
    } catch (e: any) {
      expect(e).toBeInstanceOf(ForbiddenException);
      const body = e.getResponse();
      expect(body.code).toBe('ACCOUNTABILITY_BLOCKED');
      expect(body.violations).toHaveLength(1);
      expect(body.message).toBe('Too cheap');
    }
  });
});

describe('AccountabilityService.raise', () => {
  const alert = (severity: 'LOW' | 'MEDIUM' | 'HIGH') => ({
    tenantId: 't1',
    type: 'VOID',
    severity,
    title: 'Sale voided',
    body: 'Faith voided a sale',
  });

  it('stores every alert but only pushes HIGH ones to the owner', async () => {
    const { service, prisma, notifications } = build({});
    await service.raise(alert('MEDIUM'));
    expect(prisma.accountabilityAlert.create).toHaveBeenCalledTimes(1);
    expect(notifications.sendToTenantRoles).not.toHaveBeenCalled();

    await service.raise(alert('HIGH'));
    expect(prisma.accountabilityAlert.create).toHaveBeenCalledTimes(2);
    expect(notifications.sendToTenantRoles).toHaveBeenCalledTimes(1);
    expect(notifications.sendToTenantRoles.mock.calls[0][1]).toEqual(['ADMIN']);
  });

  it('respects the owner turning push off', async () => {
    const { service, notifications } = build({ settings: { alerts: { pushHigh: false } } });
    await service.raise(alert('HIGH'));
    expect(notifications.sendToTenantRoles).not.toHaveBeenCalled();
  });

  it('never throws, so a failed alert cannot undo the sale it describes', async () => {
    const { service, prisma } = build({});
    prisma.accountabilityAlert.create.mockRejectedValue(new Error('db down'));
    await expect(service.raise(alert('HIGH'))).resolves.toBeUndefined();
  });
});

describe('AccountabilityService.flagSale', () => {
  it('writes one alert per violation naming who did it and which receipt', async () => {
    const { service, prisma } = build({});
    await service.flagSale(
      { tenantId: 't1', branchId: 'b1', userId: 'u1', saleId: 's1', receiptNumber: 'R-001' },
      [
        { code: 'BELOW_COST', severity: 'HIGH', message: 'Sufuria sold below cost', blockable: true },
        { code: 'DISCOUNT_LIMIT', severity: 'MEDIUM', message: 'Discount over limit', blockable: true },
      ],
    );
    expect(prisma.accountabilityAlert.create).toHaveBeenCalledTimes(2);
    const first = prisma.accountabilityAlert.create.mock.calls[0][0].data;
    expect(first.type).toBe('BELOW_COST');
    expect(first.body).toContain('Faith Atieno');
    expect(first.body).toContain('R-001');
    expect(first.entityId).toBe('s1');
  });
});

describe('AccountabilityService.updateSettings', () => {
  it('merges a partial change over the stored rules and audits the before/after', async () => {
    const { service, prisma, audit } = build({ settings: { priceGuard: { mode: 'FLAG', minMarginPercent: 5 } } });
    prisma.tenant.update = jest.fn().mockResolvedValue({});

    const merged = await service.updateSettings('t1', 'owner', { priceGuard: { mode: 'BLOCK' } });

    expect(merged.priceGuard.mode).toBe('BLOCK');
    expect(merged.priceGuard.minMarginPercent).toBe(5); // untouched
    const saved = prisma.tenant.update.mock.calls[0][0].data.settings.accountability;
    expect(saved.priceGuard.mode).toBe('BLOCK');
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'ACCOUNTABILITY_SETTINGS_UPDATED', userId: 'owner' }),
    );
  });
});

describe('AccountabilityService.tillRules', () => {
  it('gives the till each product floor (the higher of minimum price and cost + margin) and what this user may override', async () => {
    const { service, prisma } = build({
      settings: { priceGuard: { minMarginPercent: 10 } },
      permissions: ['sales.discount'],
    });
    prisma.product.findMany.mockResolvedValue([
      { id: 'a', costPrice: 100, minPrice: null }, // 110 from margin
      { id: 'b', costPrice: 100, minPrice: 150 }, // explicit minimum wins
      { id: 'c', costPrice: null, minPrice: 80 }, // minimum only
    ]);

    const rules = await service.tillRules('t1', 'u1');

    expect(rules.can).toEqual({ discount: true, overridePrice: false, overrideCredit: false });
    expect(rules.floors).toEqual([
      { productId: 'a', cost: 100, floor: 110 },
      { productId: 'b', cost: 100, floor: 150 },
      { productId: 'c', cost: 0, floor: 80 },
    ]);
    expect(rules.priceGuard.mode).toBe('FLAG');
  });
});
