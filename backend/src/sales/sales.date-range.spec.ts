import { SalesService } from './sales.service';

describe('SalesService date-range filtering', () => {
  const tenantId = 'tenant-a';
  let prisma: any;
  let service: SalesService;

  const whereOfLastQuery = () => prisma.sale.findMany.mock.calls.at(-1)[0].where;

  beforeEach(() => {
    prisma = {
      branch: { findFirst: jest.fn().mockResolvedValue({ timezone: 'Africa/Nairobi' }) },
      sale: {
        findMany: jest.fn().mockResolvedValue([]),
        count: jest.fn().mockResolvedValue(0),
      },
    };
    service = new SalesService(prisma, {} as any, {} as any, {} as any);
  });

  it('a one-day range covers the whole day in the shop timezone', async () => {
    await service.getSales(tenantId, { startDate: '2026-10-13', endDate: '2026-10-13' } as any);

    const { gte, lte } = whereOfLastQuery().createdAt;
    // Nairobi is UTC+3: 13 Oct 00:00 local = 12 Oct 21:00 UTC.
    expect(gte.toISOString()).toBe('2026-10-12T21:00:00.000Z');
    expect(lte.toISOString()).toBe('2026-10-13T20:59:59.999Z');
  });

  it("includes a sale made late on the range's last day (the old midnight cut-off dropped it)", async () => {
    await service.getSales(tenantId, { startDate: '2026-10-06', endDate: '2026-10-13' } as any);

    const { lte } = whereOfLastQuery().createdAt;
    const saleAtFivePmNairobi = new Date('2026-10-13T14:00:00.000Z');
    expect(saleAtFivePmNairobi.getTime()).toBeLessThanOrEqual(lte.getTime());
  });

  it('does not leak into the next day', async () => {
    await service.getSales(tenantId, { startDate: '2026-10-13', endDate: '2026-10-13' } as any);

    const { lte } = whereOfLastQuery().createdAt;
    expect(new Date('2026-10-13T21:00:00.000Z').getTime()).toBeGreaterThan(lte.getTime());
  });

  it("uses the branch's own timezone when a branch is given", async () => {
    prisma.branch.findFirst.mockResolvedValue({ timezone: 'Europe/London' });

    await service.getSales(tenantId, {
      branchId: 'branch-uk',
      startDate: '2026-12-01',
      endDate: '2026-12-01',
    } as any);

    const { gte, lte } = whereOfLastQuery().createdAt;
    expect(gte.toISOString()).toBe('2026-12-01T00:00:00.000Z');
    expect(lte.toISOString()).toBe('2026-12-01T23:59:59.999Z');
    expect(prisma.branch.findFirst).toHaveBeenCalledWith({
      where: { id: 'branch-uk', tenantId },
      select: { timezone: true },
    });
  });

  it('keeps exact timestamps untouched', async () => {
    await service.getSales(tenantId, {
      startDate: '2026-10-13T08:00:00.000Z',
      endDate: '2026-10-13T09:30:00.000Z',
    } as any);

    const { gte, lte } = whereOfLastQuery().createdAt;
    expect(gte.toISOString()).toBe('2026-10-13T08:00:00.000Z');
    expect(lte.toISOString()).toBe('2026-10-13T09:30:00.000Z');
    expect(prisma.branch.findFirst).not.toHaveBeenCalled();
  });

  it('supports an open-ended range and no range at all', async () => {
    await service.getSales(tenantId, { startDate: '2026-10-13' } as any);
    expect(whereOfLastQuery().createdAt.lte).toBeUndefined();
    expect(whereOfLastQuery().createdAt.gte).toBeInstanceOf(Date);

    await service.getSales(tenantId, {} as any);
    expect(whereOfLastQuery().createdAt).toBeUndefined();
  });

  it('applies the same fix to the credit-sales listing', async () => {
    await service.getCreditSalesWithOutstandingBalance(tenantId, {
      startDate: '2026-10-13',
      endDate: '2026-10-13',
    } as any);

    const { lte } = whereOfLastQuery().createdAt;
    expect(lte.toISOString()).toBe('2026-10-13T20:59:59.999Z');
  });
});
