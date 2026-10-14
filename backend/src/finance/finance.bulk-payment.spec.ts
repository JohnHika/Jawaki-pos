import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { FinanceService } from './finance.service';

describe('FinanceService.recordRetailBulkPayment', () => {
  const userId = 'user-1';
  const tenantId = 'tenant-a';
  const branchId = 'branch-a';
  let prisma: any;
  let audit: any;
  let cashFlow: any;
  let service: FinanceService;
  let receivables: Record<string, { outstandingAmount: number; status: string }>;
  let paymentSeq: number;

  const dto = (overrides: Record<string, unknown> = {}) => ({
    branchId,
    method: 'CASH' as const,
    allocations: [
      { receivableId: 'r-2', amount: 40 },
      { receivableId: 'r-1', amount: 100 },
    ],
    ...overrides,
  });

  beforeEach(() => {
    receivables = {
      'r-1': { outstandingAmount: 100, status: 'OPEN' },
      'r-2': { outstandingAmount: 70, status: 'OPEN' },
    };
    paymentSeq = 0;
    prisma = {
      branch: { findFirst: jest.fn().mockResolvedValue({ id: branchId, tenantId }) },
      $transaction: jest.fn(async (work: any) => work(prisma)),
      $executeRaw: jest.fn(),
      retailReceivable: {
        findFirst: jest.fn(async ({ where }: any) => {
          const row = receivables[where.id];
          return row ? { id: where.id, tenantId, branchId, ...row } : null;
        }),
        update: jest.fn(async ({ where, data }: any) => {
          receivables[where.id] = { ...receivables[where.id], ...data };
        }),
      },
      retailReceivablePayment: {
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn(async ({ data }: any) => ({ id: `p-${++paymentSeq}`, ...data })),
      },
    };
    audit = { record: jest.fn().mockResolvedValue(undefined) };
    cashFlow = { recordEntry: jest.fn().mockResolvedValue(undefined) };
    service = new FinanceService(prisma, audit, cashFlow);
  });

  it('applies every allocation, updates balances and returns the total', async () => {
    const result = await service.recordRetailBulkPayment(userId, tenantId, dto());

    expect(result.count).toBe(2);
    expect(result.totalAmount).toBe(140);
    expect(receivables['r-1']).toMatchObject({ outstandingAmount: 0, status: 'PAID' });
    expect(receivables['r-2']).toMatchObject({ outstandingAmount: 30, status: 'PARTIAL' });
    expect(cashFlow.recordEntry).toHaveBeenCalledTimes(2);
    expect(audit.record).toHaveBeenCalledTimes(1);
  });

  it('locks receivables in a stable order regardless of request order', async () => {
    await service.recordRetailBulkPayment(userId, tenantId, dto());

    const locked = prisma.retailReceivable.findFirst.mock.calls.map((call: any[]) => call[0].where.id);
    expect(locked).toEqual(['r-1', 'r-2']);
  });

  it('does not record cash movements for non-cash methods', async () => {
    await service.recordRetailBulkPayment(userId, tenantId, dto({ method: 'MPESA', reference: 'QWE123' }));

    expect(cashFlow.recordEntry).not.toHaveBeenCalled();
  });

  it('rejects duplicate receivables in one batch', async () => {
    await expect(
      service.recordRetailBulkPayment(
        userId,
        tenantId,
        dto({ allocations: [{ receivableId: 'r-1', amount: 10 }, { receivableId: 'r-1', amount: 10 }] }),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('fails the whole batch when one allocation exceeds its balance', async () => {
    await expect(
      service.recordRetailBulkPayment(
        userId,
        tenantId,
        dto({ allocations: [{ receivableId: 'r-1', amount: 100 }, { receivableId: 'r-2', amount: 71 }] }),
      ),
    ).rejects.toThrow('Payment amount exceeds outstanding balance');
    // Rolled back by the surrounding transaction in production; no audit entry is written.
    expect(audit.record).not.toHaveBeenCalled();
  });

  it('rejects a branch outside the caller tenant', async () => {
    prisma.branch.findFirst.mockResolvedValue(null);

    await expect(service.recordRetailBulkPayment(userId, tenantId, dto())).rejects.toBeInstanceOf(NotFoundException);
  });

  it('replays an already-applied batch without paying twice', async () => {
    prisma.retailReceivablePayment.findMany.mockResolvedValue([
      { id: 'p-a', tenantId, branchId, receivableId: 'r-1', amount: 100, method: 'CASH', offlineId: 'k:r-1' },
      { id: 'p-b', tenantId, branchId, receivableId: 'r-2', amount: 40, method: 'CASH', offlineId: 'k:r-2' },
    ]);

    const result = await service.recordRetailBulkPayment(userId, tenantId, dto({ offlineId: 'k' }));

    expect(result.totalAmount).toBe(140);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('refuses a reused key that only matches part of the batch', async () => {
    prisma.retailReceivablePayment.findMany.mockResolvedValue([
      { id: 'p-a', tenantId, branchId, receivableId: 'r-1', amount: 100, method: 'CASH', offlineId: 'k:r-1' },
    ]);

    await expect(service.recordRetailBulkPayment(userId, tenantId, dto({ offlineId: 'k' }))).rejects.toBeInstanceOf(
      ConflictException,
    );
  });
});

describe('FinanceService.recordPeerBulkPayment', () => {
  const userId = 'user-1';
  const tenantId = 'tenant-a';
  const branchId = 'branch-a';

  it('splits one shop instalment across its debts using the peer ledgers', async () => {
    const debts: Record<string, { outstandingAmount: number; status: string }> = {
      'd-1': { outstandingAmount: 5000, status: 'OPEN' },
      'd-2': { outstandingAmount: 2000, status: 'OPEN' },
    };
    let seq = 0;
    const prisma: any = {
      branch: { findFirst: jest.fn().mockResolvedValue({ id: branchId, tenantId }) },
      $transaction: jest.fn(async (work: any) => work(prisma)),
      $executeRaw: jest.fn(),
      peerReceivable: {
        findFirst: jest.fn(async ({ where }: any) => ({ id: where.id, tenantId, branchId, ...debts[where.id] })),
        update: jest.fn(async ({ where, data }: any) => {
          debts[where.id] = { ...debts[where.id], ...data };
        }),
      },
      peerReceivablePayment: {
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn(async ({ data }: any) => ({ id: `pp-${++seq}`, ...data })),
      },
      retailReceivable: { findFirst: jest.fn(), update: jest.fn() },
      retailReceivablePayment: { findMany: jest.fn(), create: jest.fn() },
    };
    const audit: any = { record: jest.fn().mockResolvedValue(undefined) };
    const cashFlow: any = { recordEntry: jest.fn().mockResolvedValue(undefined) };
    const service = new FinanceService(prisma, audit, cashFlow);

    const result = await service.recordPeerBulkPayment(userId, tenantId, {
      branchId,
      method: 'CASH',
      allocations: [
        { receivableId: 'd-1', amount: 5000 },
        { receivableId: 'd-2', amount: 500 },
      ],
    } as any);

    expect(result.totalAmount).toBe(5500);
    expect(debts['d-1']).toMatchObject({ outstandingAmount: 0, status: 'PAID' });
    expect(debts['d-2']).toMatchObject({ outstandingAmount: 1500, status: 'PARTIAL' });
    expect(prisma.retailReceivable.update).not.toHaveBeenCalled();
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ entityType: 'peer_receivable_bulk_payment' }),
    );
  });
});
