import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { ManualPaymentsService } from './manual-payments.service';

describe('ManualPaymentsService', () => {
  const tenantId = 'tenant-a';
  const branchId = 'branch-a';
  const cashier = 'cashier-1';
  const manager = 'manager-1';
  let prisma: any;
  let audit: any;
  let service: ManualPaymentsService;

  const pending = (overrides: Record<string, unknown> = {}) => ({
    id: 'req-1',
    requestNumber: 'MPR-20261013-ABC123',
    branchId,
    saleId: null,
    requestedById: cashier,
    paymentMethod: 'bank_transfer',
    amount: 500,
    reason: 'Bank transfer',
    status: 'PENDING',
    ...overrides,
  });

  beforeEach(() => {
    prisma = {
      branch: { findFirst: jest.fn().mockResolvedValue({ id: branchId, tenantId }) },
      sale: { findFirst: jest.fn() },
      payment: { create: jest.fn().mockResolvedValue({}) },
      manualPaymentRequest: {
        create: jest.fn(async ({ data }: any) => ({ id: 'req-1', status: 'PENDING', ...data })),
        findFirst: jest.fn().mockResolvedValue(pending()),
        findMany: jest.fn().mockResolvedValue([]),
        findUniqueOrThrow: jest.fn(async () => pending({ status: 'APPROVED', approvedById: manager })),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        update: jest.fn().mockResolvedValue({}),
      },
      $transaction: jest.fn(async (work: any) => work(prisma)),
    };
    audit = { record: jest.fn().mockResolvedValue(undefined) };
    service = new ManualPaymentsService(prisma, audit);
  });

  describe('createRequest', () => {
    const base = { branchId, paymentMethod: ' Bank_Transfer ', amount: 500, reason: ' Slip seen ' };

    it('creates a pending request with a generated number and normalised fields', async () => {
      const result = await service.createRequest(cashier, tenantId, base);

      const data = prisma.manualPaymentRequest.create.mock.calls[0][0].data;
      expect(data.requestNumber).toMatch(/^MPR-\d{8}-[0-9A-F]{6}$/);
      expect(data).toMatchObject({ paymentMethod: 'bank_transfer', reason: 'Slip seen', requestedById: cashier });
      expect(result.status).toBe('PENDING');
      expect(audit.record).toHaveBeenCalledTimes(1);
    });

    it('rejects a branch outside the tenant', async () => {
      prisma.branch.findFirst.mockResolvedValue(null);

      await expect(service.createRequest(cashier, tenantId, base)).rejects.toBeInstanceOf(NotFoundException);
    });

    it('rejects an amount above the linked sale total', async () => {
      prisma.sale.findFirst.mockResolvedValue({ id: 's-1', totalAmount: 300, manualPaymentRequest: null });

      await expect(service.createRequest(cashier, tenantId, { ...base, saleId: 's-1' })).rejects.toThrow(
        'Amount exceeds the sale total',
      );
    });

    it('rejects a sale that already has a request', async () => {
      prisma.sale.findFirst.mockResolvedValue({ id: 's-1', totalAmount: 900, manualPaymentRequest: { id: 'x' } });

      await expect(service.createRequest(cashier, tenantId, { ...base, saleId: 's-1' })).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });
  });

  describe('list', () => {
    it('limits non-approvers to their own requests', async () => {
      await service.list(cashier, tenantId, ['sales.create'], {});

      expect(prisma.manualPaymentRequest.findMany.mock.calls[0][0].where).toMatchObject({ requestedById: cashier });
    });

    it('lets approvers see every request in the tenant', async () => {
      await service.list(manager, tenantId, ['payments.manual_approve'], { status: 'PENDING' as any });

      const where = prisma.manualPaymentRequest.findMany.mock.calls[0][0].where;
      expect(where).not.toHaveProperty('requestedById');
      expect(where).toMatchObject({ status: 'PENDING', branch: { tenantId } });
    });
  });

  describe('approve', () => {
    it('blocks approving your own request', async () => {
      await expect(service.approve(cashier, tenantId, 'req-1')).rejects.toBeInstanceOf(ForbiddenException);
      expect(prisma.manualPaymentRequest.updateMany).not.toHaveBeenCalled();
    });

    it('approves a standalone request without creating a payment', async () => {
      const result = await service.approve(manager, tenantId, 'req-1');

      expect(result.status).toBe('APPROVED');
      expect(prisma.payment.create).not.toHaveBeenCalled();
      expect(audit.record).toHaveBeenCalledWith(expect.objectContaining({ action: 'APPROVE', userId: manager }));
    });

    it('records a completed MANUAL payment for a sale-linked request', async () => {
      prisma.manualPaymentRequest.findFirst.mockResolvedValue(pending({ saleId: 'sale-1' }));

      await service.approve(manager, tenantId, 'req-1');

      expect(prisma.payment.create.mock.calls[0][0].data).toMatchObject({
        saleId: 'sale-1',
        method: 'MANUAL',
        status: 'COMPLETED',
        transactionId: 'MPR-20261013-ABC123',
      });
      expect(prisma.manualPaymentRequest.update.mock.calls[0][0].data.status).toBe('COMPLETED');
    });

    it('refuses a request that was already decided', async () => {
      prisma.manualPaymentRequest.findFirst.mockResolvedValue(pending({ status: 'REJECTED' }));

      await expect(service.approve(manager, tenantId, 'req-1')).rejects.toThrow('already been decided');
    });

    it('loses cleanly when another approver decides first', async () => {
      prisma.manualPaymentRequest.updateMany.mockResolvedValue({ count: 0 });

      await expect(service.approve(manager, tenantId, 'req-1')).rejects.toThrow('already been decided');
      expect(prisma.payment.create).not.toHaveBeenCalled();
    });

    it('returns not found for a request outside the tenant', async () => {
      prisma.manualPaymentRequest.findFirst.mockResolvedValue(null);

      await expect(service.approve(manager, tenantId, 'req-1')).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('reject', () => {
    it('stores the reason and audits the decision', async () => {
      await service.reject(manager, tenantId, 'req-1', { rejectionReason: ' No slip ' });

      expect(prisma.manualPaymentRequest.updateMany.mock.calls[0][0].data).toMatchObject({
        status: 'REJECTED',
        rejectionReason: 'No slip',
        approvedById: manager,
      });
      expect(audit.record).toHaveBeenCalledWith(expect.objectContaining({ action: 'REJECT' }));
    });

    it('blocks rejecting your own request', async () => {
      await expect(service.reject(cashier, tenantId, 'req-1', { rejectionReason: 'oops' })).rejects.toBeInstanceOf(
        ForbiddenException,
      );
    });
  });
});
