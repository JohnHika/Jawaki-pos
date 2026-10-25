import { CashEntryType, CashFlowMode } from './dto/cash-flow.dto';
import { CashFlowService } from './cash-flow.service';

describe('CashFlowService', () => {
  const branchId = 'branch-1';
  let prisma: any;
  let service: CashFlowService;
  let positiveManualAdjustment: number;
  let negativeManualAdjustment: number;

  beforeEach(() => {
    positiveManualAdjustment = 0;
    negativeManualAdjustment = -2;
    prisma = {
      branchCashSettings: {
        findUnique: jest.fn().mockResolvedValue({ mode: CashFlowMode.ALL_REVENUE }),
      },
      branch: {
        findUnique: jest.fn().mockResolvedValue({ timezone: 'Africa/Nairobi' }),
      },
      cashLedgerEntry: {
        aggregate: jest.fn(async ({ where }: any) => {
          if (where.amount?.gt !== undefined) {
            return { _sum: { amount: positiveManualAdjustment } };
          }
          if (where.amount?.lt !== undefined) {
            return { _sum: { amount: negativeManualAdjustment } };
          }
          const amounts: Record<string, number> = {
            [CashEntryType.SALE_CASH_IN]: 100,
            [CashEntryType.RECEIVABLE_COLLECTION_IN]: 0,
            [CashEntryType.RESTOCK_OUT]: -25,
            [CashEntryType.EXPENSE_OUT]: -5,
            [CashEntryType.MANUAL_ADJUSTMENT]: -2,
          };
          return { _sum: { amount: amounts[where.type] ?? 0 } };
        }),
        findFirst: jest.fn().mockResolvedValue({ balanceAfter: 321 }),
      },
      sale: {
        aggregate: jest.fn().mockResolvedValue({ _sum: { totalAmount: 1200 } }),
      },
    };
    service = new CashFlowService(prisma);
  });

  it('keeps ALL_REVENUE available cash unchanged and reports till-only physical cash separately', async () => {
    const result = await service.getAvailableCash(branchId);

    expect(result).toMatchObject({
      mode: CashFlowMode.ALL_REVENUE,
      availableCash: 1168,
      expectedPhysicalCash: 68,
      todaysCashIn: 1200,
      todaysCashOut: 32,
    });
    expect(result.breakdown).toMatchObject({
      allRevenue: 1200,
      salesCashIn: 100,
      receivableCollections: 0,
      expectedPhysicalCash: 68,
    });
  });

  it('uses the existing cash-only balance for physical cash in CASH_ONLY mode', async () => {
    prisma.branchCashSettings.findUnique.mockResolvedValue({ mode: CashFlowMode.CASH_ONLY });

    const result = await service.getAvailableCash(branchId);

    expect(result.availableCash).toBe(68);
    expect(result.expectedPhysicalCash).toBe(68);
  });

  it('uses the running till balance for physical cash in RUNNING_BALANCE mode', async () => {
    prisma.branchCashSettings.findUnique.mockResolvedValue({ mode: CashFlowMode.RUNNING_BALANCE });

    const result = await service.getAvailableCash(branchId);

    expect(result.availableCash).toBe(321);
    expect(result.expectedPhysicalCash).toBe(321);
  });

  it('includes positive till adjustments so a repeated overage count is not booked twice', async () => {
    prisma.branchCashSettings.findUnique.mockResolvedValue({ mode: CashFlowMode.CASH_ONLY });
    positiveManualAdjustment = 10;

    const result = await service.getAvailableCash(branchId);

    // A first count of 78 against the original 68 books a +10 adjustment.
    // The next count should expect 78, not 68 (which would book the same
    // overage again on every retry).
    expect(result.expectedPhysicalCash).toBe(78);
    expect(result.availableCash).toBe(78);
    expect(result.todaysCashIn).toBe(110);
    expect(result.breakdown).toMatchObject({ manualAdjustmentIn: 10, manualAdjustmentOut: 2 });
  });

  it('reads cash figures from the caller transaction when one is provided', async () => {
    const tx: any = {
      branchCashSettings: {
        findUnique: jest.fn().mockResolvedValue({ mode: CashFlowMode.CASH_ONLY }),
      },
      branch: {
        findUnique: jest.fn().mockResolvedValue({ timezone: 'Africa/Nairobi' }),
      },
      cashLedgerEntry: {
        aggregate: jest.fn().mockResolvedValue({ _sum: { amount: 0 } }),
      },
      sale: { aggregate: jest.fn() },
    };

    const result = await service.getAvailableCash(branchId, tx);

    expect(result.expectedPhysicalCash).toBe(0);
    expect(tx.cashLedgerEntry.aggregate).toHaveBeenCalled();
    expect(prisma.cashLedgerEntry.aggregate).not.toHaveBeenCalled();
    expect(prisma.branchCashSettings.findUnique).not.toHaveBeenCalled();
  });
});
