import { CashFlowMode } from './dto/cash-flow.dto';
import { CashReconciliationService } from './cash-reconciliation.service';

describe('CashReconciliationService', () => {
  const userId = 'user-1';
  const tenantId = 'tenant-1';
  const branchId = 'branch-1';
  let prisma: any;
  let audit: any;
  let cashFlow: any;
  let service: CashReconciliationService;

  beforeEach(() => {
    prisma = {
      branch: {
        findFirst: jest.fn().mockResolvedValue({ id: branchId, tenantId, timezone: 'Africa/Nairobi' }),
      },
      cashReconciliation: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn(async ({ data }: any) => ({ id: 'reconciliation-1', ...data })),
      },
    };
    audit = { record: jest.fn().mockResolvedValue(undefined) };
    cashFlow = {
      getAvailableCash: jest.fn().mockResolvedValue({
        mode: CashFlowMode.ALL_REVENUE,
        availableCash: 1168,
        expectedPhysicalCash: 68,
      }),
      recordEntry: jest.fn().mockResolvedValue(undefined),
    };
    service = new CashReconciliationService(prisma, audit, cashFlow);
  });

  it('compares the physical count to cash-only expected cash in ALL_REVENUE mode', async () => {
    const result = await service.createReconciliation(userId, tenantId, branchId, {
      countedCash: 58,
      notes: 'Till count',
    });

    expect(result).toMatchObject({
      expectedCash: 68,
      countedCash: 58,
      discrepancy: -10,
      cashMode: CashFlowMode.ALL_REVENUE,
    });
    expect(cashFlow.recordEntry).toHaveBeenCalledWith(expect.objectContaining({
      branchId,
      amount: -10,
      referenceType: 'cash_reconciliation',
    }));
    expect(audit.record).toHaveBeenCalledWith(expect.objectContaining({
      newValues: { expectedCash: 68, countedCash: 58, discrepancy: -10 },
    }));
  });
});
