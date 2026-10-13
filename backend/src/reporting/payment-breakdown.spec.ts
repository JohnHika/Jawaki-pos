import { ReportingService } from './reporting.service';

describe('ReportingService.getPaymentMethodBreakdown', () => {
  const build = (paymentRows: any[], saleRows: any[]) => {
    const prisma: any = {
      payment: { groupBy: jest.fn().mockResolvedValue(paymentRows) },
      sale: { groupBy: jest.fn().mockResolvedValue(saleRows) },
    };
    return { service: new ReportingService(prisma, {} as any), prisma };
  };

  it('counts plain cash sales that have no Payment row', async () => {
    const { service, prisma } = build(
      [{ method: 'MPESA', _count: { id: 2 }, _sum: { amount: 1910 } }],
      [{ paymentMethod: 'CASH', _count: { id: 1 }, _sum: { totalAmount: 450 } }],
    );

    const out = await service.getPaymentMethodBreakdown('t1', { startDate: '2026-10-14', endDate: '2026-10-14' } as any);

    expect(out.find((r) => r.method === 'CASH')).toMatchObject({ transactionsCount: 1, amount: 450 });
    expect(out.find((r) => r.method === 'MPESA')).toMatchObject({ transactionsCount: 2, amount: 1910 });
    expect(out.reduce((s, r) => s + r.percentage, 0)).toBeCloseTo(100);
    // Only sales without a Payment row, and never credit/split ones, are folded in.
    const where = prisma.sale.groupBy.mock.calls[0][0].where;
    expect(where.payments).toEqual({ none: {} });
    expect(where.paymentMethod.notIn).toEqual(expect.arrayContaining(['CREDIT', 'SPLIT']));
  });

  it('merges a method that appears in both sources', async () => {
    const { service } = build(
      [{ method: 'CASH', _count: { id: 1 }, _sum: { amount: 180 } }],
      [{ paymentMethod: 'CASH', _count: { id: 1 }, _sum: { totalAmount: 450 } }],
    );
    const out = await service.getPaymentMethodBreakdown('t1', { startDate: '2026-10-14', endDate: '2026-10-14' } as any);
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ method: 'CASH', transactionsCount: 2, amount: 630, percentage: 100 });
  });
});
