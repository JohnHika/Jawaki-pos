import { BadRequestException, NotFoundException } from '@nestjs/common';
import { FinanceService } from './finance.service';

describe('FinanceService', () => {
  const userId = 'user-1';
  const tenantId = 'tenant-a';
  const branchId = 'branch-a';
  let prisma: any;
  let audit: any;
  let cashFlow: any;
  let service: FinanceService;

  const openRetailReceivable = {
    id: 'retail-1',
    tenantId,
    branchId,
    saleId: 'sale-1',
    customerId: null,
    originalAmount: 100,
    outstandingAmount: 100,
    dueDate: null,
    status: 'OPEN',
    sale: { receiptNumber: 'R-1', customer: null },
    payments: [],
  };

  beforeEach(() => {
    prisma = {
      branch: { findFirst: jest.fn().mockResolvedValue({ id: branchId, tenantId }) },
      peerReceivablePayment: { findUnique: jest.fn().mockResolvedValue(null) },
      $transaction: jest.fn(async (work: any) => work(prisma)),
      $executeRaw: jest.fn(),
      retailReceivable: {
        findFirst: jest.fn().mockResolvedValue(openRetailReceivable),
        update: jest.fn().mockResolvedValue({ ...openRetailReceivable, outstandingAmount: 60, status: 'PARTIAL' }),
        aggregate: jest.fn().mockResolvedValue({ _sum: { outstandingAmount: 17 } }),
      },
      retailReceivablePayment: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 'retail-payment-1', amount: 40, method: 'CASH' }),
      },
      peerReceivable: {
        findFirst: jest.fn(),
        aggregate: jest.fn().mockResolvedValue({ _sum: { outstandingAmount: 23 } }),
      },
      supplierInvoice: {
        aggregate: jest.fn().mockResolvedValue({ _sum: { dueAmount: 31 } }),
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    audit = { record: jest.fn().mockResolvedValue(undefined) };
    cashFlow = { recordEntry: jest.fn().mockResolvedValue(undefined) };
    service = new FinanceService(prisma, audit, cashFlow);
  });

  it('rejects a retail payment against a branch outside the caller tenant', async () => {
    prisma.branch.findFirst.mockResolvedValue(null);

    await expect(service.recordRetailPayment(userId, tenantId, 'retail-1', {
      branchId,
      amount: 40,
      method: 'CASH',
    })).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects a retail payment against a receivable owned by another tenant', async () => {
    prisma.retailReceivable.findFirst.mockResolvedValue(null);

    await expect(service.recordRetailPayment(userId, tenantId, 'foreign-receivable', {
      branchId,
      amount: 40,
      method: 'CASH',
    })).rejects.toBeInstanceOf(NotFoundException);

    expect(prisma.retailReceivablePayment.create).not.toHaveBeenCalled();
    expect(cashFlow.recordEntry).not.toHaveBeenCalled();
  });

  it('rejects retail overpayments before creating a payment or cash entry', async () => {
    await expect(service.recordRetailPayment(userId, tenantId, 'retail-1', {
      branchId,
      amount: 101,
      method: 'CASH',
    })).rejects.toBeInstanceOf(BadRequestException);

    expect(prisma.retailReceivablePayment.create).not.toHaveBeenCalled();
    expect(cashFlow.recordEntry).not.toHaveBeenCalled();
  });

  it('returns an existing same-branch payment for an idempotent offlineId', async () => {
    const existing = {
      id: 'retail-payment-existing',
      receivableId: 'retail-1',
      tenantId,
      branchId,
      receivable: openRetailReceivable,
      amount: 40,
      method: 'MPESA',
    };
    prisma.retailReceivablePayment.findUnique.mockResolvedValue(existing);

    await expect(service.recordRetailPayment(userId, tenantId, 'retail-1', {
      branchId,
      amount: 40,
      method: 'MPESA',
      offlineId: 'offline-payment-1',
    })).resolves.toMatchObject({ id: 'retail-payment-existing', amount: 40, method: 'MPESA' });

    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(cashFlow.recordEntry).not.toHaveBeenCalled();
  });

  it('creates cash ledger only for physical-cash retail collections', async () => {
    await service.recordRetailPayment(userId, tenantId, 'retail-1', {
      branchId,
      amount: 40,
      method: 'CASH',
    });

    expect(cashFlow.recordEntry).toHaveBeenCalledWith(expect.objectContaining({
      tx: prisma,
      branchId,
      type: 'RECEIVABLE_COLLECTION_IN',
      amount: 40,
      referenceType: 'retail_receivable_payment',
    }));
    expect(audit.record).toHaveBeenCalledWith(expect.objectContaining({
      action: 'CREATE',
      entityType: 'retail_receivable_payment',
    }));
  });

  it('does not add a cash ledger entry for an M-Pesa collection', async () => {
    await service.recordRetailPayment(userId, tenantId, 'retail-1', {
      branchId,
      amount: 40,
      method: 'MPESA',
    });

    expect(cashFlow.recordEntry).not.toHaveBeenCalled();
  });

  it('keeps supplier, retail, and peer outstanding totals separate in the overview', async () => {
    await expect(service.getOverview(tenantId, branchId)).resolves.toEqual({
      branchId,
      supplierPayablesOutstanding: 31,
      retailReceivablesOutstanding: 17,
      peerReceivablesOutstanding: 23,
    });
  });
});
