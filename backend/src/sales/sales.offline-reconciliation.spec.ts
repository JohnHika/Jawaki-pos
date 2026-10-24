import { SalesService } from './sales.service';

describe('SalesService offline sale reconciliation', () => {
  const prisma = {
    sale: { findMany: jest.fn() },
  } as any;
  const service = new SalesService(prisma, {} as any, {} as any, {} as any);

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns only supplied offline IDs already saved for this tenant branch', async () => {
    prisma.sale.findMany.mockResolvedValue([
      { offlineId: 'local-sale-1' },
      { offlineId: null },
    ]);

    await expect(service.reconcileOfflineSales('tenant-1', {
      branchId: 'branch-1',
      offlineIds: ['local-sale-1', 'local-sale-2'],
    })).resolves.toEqual({ offlineIds: ['local-sale-1'] });

    expect(prisma.sale.findMany).toHaveBeenCalledWith({
      where: {
        branchId: 'branch-1',
        branch: { tenantId: 'tenant-1' },
        offlineId: { in: ['local-sale-1', 'local-sale-2'] },
      },
      select: { offlineId: true },
    });
  });

  it('avoids a database query for an empty list', async () => {
    await expect(service.reconcileOfflineSales('tenant-1', {
      branchId: 'branch-1',
      offlineIds: [],
    })).resolves.toEqual({ offlineIds: [] });

    expect(prisma.sale.findMany).not.toHaveBeenCalled();
  });
});
