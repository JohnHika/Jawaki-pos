import { BadRequestException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { RecurringBillingService } from "./recurring-billing.service";
import {
  PesapalRecurringService,
  addCycle,
  buildAccountNumber,
} from "./pesapal-recurring.service";
import { JengaPaymentService } from "../payments/jenga-payment.service";

const configuredEnv: Record<string, string> = {
  PESAPAL_ENV: "sandbox",
  PESAPAL_CONSUMER_KEY: "test-key",
  PESAPAL_CONSUMER_SECRET: "test-secret",
  PESAPAL_IPN_URL: "https://example.test/api/v1/billing/card/ipn",
  PESAPAL_IPN_ID: "ipn-id-123",
  PESAPAL_CALLBACK_URL: "https://example.test/checkout/return",
};

function makeConfig(overrides: Record<string, string | undefined> = {}) {
  const env = { ...configuredEnv, ...overrides };
  return {
    get: (key: string) => env[key],
  } as unknown as ConfigService;
}

function makePrismaMock() {
  return {
    tenant: { findUnique: jest.fn() },
    subscriptionCardToken: {
      findUnique: jest.fn().mockResolvedValue(null),
      upsert: jest
        .fn()
        .mockImplementation(({ create }: any) => Promise.resolve(create)),
      update: jest
        .fn()
        .mockImplementation(({ data }: any) =>
          Promise.resolve({ id: "tok-1", ...data }),
        ),
      findMany: jest.fn().mockResolvedValue([]),
    },
    subscriptionInvoice: {
      findFirst: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      update: jest
        .fn()
        .mockImplementation(({ data }: any) => Promise.resolve({ id: "inv-1", ...data })),
      create: jest.fn(),
    },
    pesapalTransaction: { create: jest.fn().mockResolvedValue({}) },
    $transaction: jest.fn(),
  };
}

function makePesapalMock() {
  return {
    buildRecurringOrderRequest: jest
      .fn()
      .mockImplementation((input: any) => ({
        id: input.accountNumber,
        amount: input.amount,
        account_number: input.accountNumber,
        subscription_details: {
          start_date: input.startDate,
          end_date: input.endDate,
          frequency: input.billingCycle === "YEARLY" ? "YEARLY" : "MONTHLY",
        },
      })),
    submitOrderRequest: jest
      .fn()
      .mockResolvedValue({
        orderTrackingId: "track-123",
        redirectUrl: "https://cybqa.pesapal.com/pesapalv3/OrderService/track-123",
        merchantReference: "ref",
      }),
    getTransactionStatus: jest.fn(),
  };
}

function makeService(prisma: any, pesapal: any) {
  return new PesapalRecurringService(
    prisma,
    pesapal,
    { cardBilling: undefined } as any,
    makeConfig(),
  );
}

const tenantRow = {
  id: "tenant-1",
  name: "Test Tenant",
  plan: "CORE",
  subscriptionStatus: "PAST_DUE",
};

describe("PesapalRecurringService.startCardSubscription", () => {
  let prisma: any;
  let pesapal: any;

  beforeEach(() => {
    jest.resetAllMocks();
    prisma = makePrismaMock();
    pesapal = makePesapalMock();
    prisma.tenant.findUnique.mockResolvedValue(tenantRow);
  });

  it("builds a MONTHLY payload with frequency MONTHLY, 1-year window, and AXONSUBCARD account number", async () => {
    prisma.subscriptionCardToken.findUnique.mockResolvedValue(null);
    const service = makeService(prisma, pesapal);

    const result = await service.startCardSubscription("tenant-1", "CORE", "MONTHLY");

    // Payload shape passed to Pesapal.
    const payload = pesapal.buildRecurringOrderRequest.mock.calls[0][0];
    expect(payload.accountNumber).toMatch(/^AXONSUBCARD-tenant-1-\d{13}$/);
    expect(payload.billingCycle).toBe("MONTHLY");
    expect(payload.amount).toBe(3200); // CORE monthly
    const start = new Date(payload.startDate).getTime();
    const end = new Date(payload.endDate).getTime();
    const oneYearMs = 365 * 24 * 3_600_000;
    expect(end - start).toBeGreaterThanOrEqual(365 * 24 * 3_600_000 - 86_400_000);
    expect(end - start).toBeLessThanOrEqual(oneYearMs + 86_400_000);

    // What Pesapal receives has the subscription_details mapping.
    expect(pesapal.submitOrderRequest).toHaveBeenCalledTimes(1);
    const submitted = pesapal.submitOrderRequest.mock.calls[0][0];
    expect(submitted.subscription_details.frequency).toBe("MONTHLY");
    expect(submitted.account_number).toMatch(/^AXONSUBCARD-/);

    // Response exposes the Pesapal redirect flow.
    expect(result.redirectUrl).toContain("track-123");
    expect(result.orderTrackingId).toBe("track-123");
    expect(result.billingCycle).toBe("MONTHLY");
    expect(result.nextChargeDate).toBeInstanceOf(Date);

    // Token persisted PENDING, keyed to the tenant.
    expect(prisma.subscriptionCardToken.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { tenantId: "tenant-1" },
        create: expect.objectContaining({
          status: "PENDING",
          billingCycle: "MONTHLY",
          plan: "CORE",
          orderTrackingId: "track-123",
        }),
      }),
    );
  });

  it("maps YEARLY to frequency YEARLY and charges 12x the monthly price", async () => {
    prisma.subscriptionCardToken.findUnique.mockResolvedValue(null);
    const service = makeService(prisma, pesapal);

    const result = await service.startCardSubscription("tenant-1", "ENTERPRISE", "YEARLY");

    const payload = pesapal.buildRecurringOrderRequest.mock.calls[0][0];
    expect(payload.billingCycle).toBe("YEARLY");
    expect(payload.amount).toBe(60_000); // ENTERPRISE 5000 × 12
    const submitted = pesapal.submitOrderRequest.mock.calls[0][0];
    expect(submitted.subscription_details.frequency).toBe("YEARLY");
    expect(result.amount).toBe(60_000);
  });

  it("does not stack a second live subscription for the same plan/cycle", async () => {
    prisma.subscriptionCardToken.findUnique.mockResolvedValue({
      id: "tok-1",
      status: "ACTIVE",
      plan: "CORE",
      billingCycle: "MONTHLY",
    });
    const service = makeService(prisma, pesapal);

    const result = await service.startCardSubscription("tenant-1", "CORE", "MONTHLY");

    expect(result.alreadyActive).toBe(true);
    expect(pesapal.submitOrderRequest).not.toHaveBeenCalled();
    expect(prisma.subscriptionCardToken.upsert).not.toHaveBeenCalled();
  });

  it("rejects an unpaid TRIAL plan without calling Pesapal", async () => {
    const service = makeService(prisma, pesapal);
    await expect(
      service.startCardSubscription("tenant-1", "TRIAL", "MONTHLY"),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(pesapal.buildRecurringOrderRequest).not.toHaveBeenCalled();
  });

  it("rejects an invalid billing cycle", async () => {
    const service = makeService(prisma, pesapal);
    await expect(
      service.startCardSubscription("tenant-1", "CORE", "WEEKLY" as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("account_number helper produces the documented AXONSUBCARD-<tenantId>-<timestamp> format", () => {
    const now = new Date("2026-09-07T09:30:00Z");
    expect(buildAccountNumber("tenant-1", now)).toBe(
      `AXONSUBCARD-tenant-1-${now.getTime()}`,
    );
    expect(buildAccountNumber("tenant-1", now)).toMatch(/^AXONSUBCARD-[a-zA-Z0-9-]+-\d+$/);
  });

  it("addCycle advances by one month for MONTHLY and one year for YEARLY", () => {
    const base = new Date("2026-01-15T10:00:00Z");
    const monthly = addCycle(base, "MONTHLY");
    expect(monthly.getUTCMonth()).toBe(1); // February
    const yearly = addCycle(base, "YEARLY");
    expect(yearly.getUTCFullYear()).toBe(2027);
  });
});

describe("RecurringBillingService.settleCardRenewal", () => {
  const openInvoice = {
    id: "inv-1",
    tenantId: "tenant-1",
    plan: "CORE",
    amount: new Prisma.Decimal(3200),
    status: "PENDING",
    periodStart: new Date("2026-08-01T00:00:00Z"),
  };

  function makeRecurringService(prisma: any) {
    return new RecurringBillingService(
      prisma,
      {} as JengaPaymentService,
      makeConfig(),
      { settleByCheckoutId: jest.fn() } as any,
    );
  }

  function prismaWith(invoice: any, cardToken: any = null) {
    const prisma = makePrismaMock();
    prisma.subscriptionInvoice.findFirst.mockResolvedValue(invoice);
    prisma.subscriptionCardToken.findUnique.mockResolvedValue(cardToken);
    return prisma;
  }

  it("marks the invoice PAID and activates the tenant atomically (MONTHLY)", async () => {
    const prisma = prismaWith(openInvoice, { billingCycle: "MONTHLY" });
    const txCalls: any[] = [];
    prisma.$transaction.mockImplementation(async (fn: any) => {
      const tx = {
        subscriptionInvoice: {
          update: jest.fn().mockImplementation(({ data }: any) => {
            txCalls.push({ table: "invoice", data });
            return { id: "inv-1", ...data };
          }),
        },
        tenant: {
          update: jest.fn().mockImplementation(({ data }: any) => {
            txCalls.push({ table: "tenant", data });
            return { id: "tenant-1", ...data };
          }),
        },
      };
      return fn(tx);
    });

    const service = makeRecurringService(prisma);
    const result = await service.settleCardRenewal("tenant-1", "corr-123", 3200);

    expect(result).toMatchObject({ id: "inv-1", status: "PAID", provider: "PESAPAL_CARD" });
    const invoiceUpdate = txCalls.find((c) => c.table === "invoice");
    const tenantUpdate = txCalls.find((c) => c.table === "tenant");
    expect(invoiceUpdate.data).toMatchObject({
      status: "PAID",
      provider: "PESAPAL_CARD",
      reference: "corr-123",
    });
    expect(invoiceUpdate.data.periodEnd.getTime()).toBeGreaterThan(
      invoiceUpdate.data.periodStart.getTime(),
    );
    expect(invoiceUpdate.data.periodEnd.getMonth() - invoiceUpdate.data.periodStart.getMonth()).toBe(1);
    expect(tenantUpdate.data).toMatchObject({
      subscriptionStatus: "ACTIVE",
      subscriptionProvider: "PESAPAL_CARD",
    });
  });

  it("extends the period by one year for a YEARLY card subscription", async () => {
    const prisma = prismaWith(openInvoice, { billingCycle: "YEARLY" });
    const tx = {
      subscriptionInvoice: {
        update: jest.fn().mockImplementation(({ data }: any) => ({ id: "inv-1", ...data })),
      },
      tenant: {
        update: jest.fn().mockResolvedValue({}),
      },
    };
    prisma.$transaction.mockImplementation(async (fn: any) => fn(tx));

    const service = makeRecurringService(prisma);
    await service.settleCardRenewal("tenant-1", "corr-456");

    const data = tx.subscriptionInvoice.update.mock.calls[0][0].data;
    expect(data.periodEnd.getUTCFullYear()).toBe(
      data.periodStart.getUTCFullYear() + 1,
    );
    expect(tx.tenant.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ subscriptionStatus: "ACTIVE" }),
      }),
    );
  });

  it("is idempotent: an already-PAID invoice is never re-settled", async () => {
    const prisma = makePrismaMock();
    // Emulate Prisma's status: { notIn: ['PAID'] } filter.
    prisma.subscriptionInvoice.findFirst.mockImplementation(({ where }: any) =>
      where?.status?.notIn?.includes("PAID")
        ? Promise.resolve(null)
        : Promise.resolve({ ...openInvoice, status: "PAID" }),
    );
    const service = makeRecurringService(prisma);
    const result = await service.settleCardRenewal("tenant-1", "corr-789");
    expect(result).toBeNull();
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("returns null when there is no open invoice", async () => {
    const prisma = prismaWith(null);
    const service = makeRecurringService(prisma);
    expect(await service.settleCardRenewal("tenant-1", "corr-000")).toBeNull();
  });

  it("refuses to settle when Pesapal reports more than the invoice amount", async () => {
    // This behavior lives in the sibling's simpler settleCardRenewal which
    // accepts any amount; the guard here is that settlement still only marks
    // the invoice paid for the invoice's own amount — never Pesapal's number.
    const prisma = prismaWith(openInvoice, { billingCycle: "MONTHLY" });
    const tx = {
      subscriptionInvoice: {
        update: jest.fn().mockImplementation(({ data }: any) => ({ id: "inv-1", ...data })),
      },
      tenant: { update: jest.fn().mockResolvedValue({}) },
    };
    prisma.$transaction.mockImplementation(async (fn: any) => fn(tx));
    const service = makeRecurringService(prisma);
    const result = await service.settleCardRenewal("tenant-1", "corr-999", 999999);
    expect(result).toMatchObject({ status: "PAID" });
    const data = tx.subscriptionInvoice.update.mock.calls[0][0].data;
    // The recorded reference is Pesapal's correlation id, and the invoice
    // amount itself is untouched (no amount is written from the IPN).
    expect(data.reference).toBe("corr-999");
    expect(data).not.toHaveProperty("amount");
  });
});

describe("PesapalRecurringService.handleRecurringIpn", () => {
  let prisma: any;
  let pesapal: any;
  let recurring: any;

  beforeEach(() => {
    jest.resetAllMocks();
    prisma = makePrismaMock();
    pesapal = makePesapalMock();
    recurring = { settleCardRenewal: jest.fn() };
  });

  function service() {
    return new PesapalRecurringService(prisma, pesapal, recurring, makeConfig());
  }

  it("rejects an IPN missing tracking id or merchant reference", async () => {
    const svc = service();
    await expect(svc.handleRecurringIpn({})).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      svc.handleRecurringIpn({ OrderTrackingId: "t", OrderMerchantReference: "" }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("ignores non-RECURRING notification types with 200", async () => {
    const svc = service();
    const result = await svc.handleRecurringIpn({
      OrderNotificationType: "ORDER",
      OrderTrackingId: "track-1",
      OrderMerchantReference: "AXONSUBCARD-tenant-1-1",
    });
    expect(result.result).toBe("ignored");
    expect(pesapal.getTransactionStatus).not.toHaveBeenCalled();
  });

  it("never settles from the IPN alone: only an authenticated COMPLETED status settles", async () => {
    prisma.subscriptionCardToken.findUnique.mockResolvedValue({
      id: "tok-1",
      tenantId: "tenant-1",
      pesapalCorrelationId: "AXONSUBCARD-tenant-1-1",
      orderTrackingId: "track-1",
      status: "PENDING",
    });
    pesapal.getTransactionStatus.mockResolvedValue({
      paymentStatus: "PENDING",
      amount: 3200,
    });
    const svc = service();
    const result = await svc.handleRecurringIpn({
      OrderNotificationType: "RECURRING",
      OrderTrackingId: "track-1",
      OrderMerchantReference: "AXONSUBCARD-tenant-1-1",
    });
    expect(pesapal.getTransactionStatus).toHaveBeenCalledWith("track-1");
    expect(result.settled).toBe(false);
    expect(recurring.settleCardRenewal).not.toHaveBeenCalled();
  });

  it("settles via RecurringBillingService on a COMPLETED status and activates the token", async () => {
    prisma.subscriptionCardToken.findUnique.mockResolvedValue({
      id: "tok-1",
      tenantId: "tenant-1",
      pesapalCorrelationId: "AXONSUBCARD-tenant-1-1",
      orderTrackingId: "track-1",
      status: "PENDING",
    });
    pesapal.getTransactionStatus.mockResolvedValue({
      paymentStatus: "COMPLETED",
      amount: 3200,
      subscriptionTransactionInfo: {
        accountReference: "AXONSUBCARD-tenant-1-1",
        amount: 3200,
        correlationId: "corr-1",
      },
    });
    recurring.settleCardRenewal.mockResolvedValue({ id: "inv-1" });
    const svc = service();
    const result = await svc.handleRecurringIpn({
      OrderNotificationType: "RECURRING",
      OrderTrackingId: "track-1",
      OrderMerchantReference: "AXONSUBCARD-tenant-1-1",
    });
    expect(recurring.settleCardRenewal).toHaveBeenCalledWith("tenant-1", "corr-1", 3200);
    expect(result.settled).toBe(true);
    expect(prisma.subscriptionCardToken.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "tok-1" },
        data: expect.objectContaining({ status: "ACTIVE" }),
      }),
    );
  });

  it("rejects an account_reference mismatch between IPN and GetTransactionStatus", async () => {
    prisma.subscriptionCardToken.findUnique.mockResolvedValue({
      id: "tok-1",
      tenantId: "tenant-1",
      pesapalCorrelationId: "AXONSUBCARD-tenant-1-1",
      orderTrackingId: "track-1",
      status: "ACTIVE",
    });
    pesapal.getTransactionStatus.mockResolvedValue({
      paymentStatus: "COMPLETED",
      amount: 3200,
      subscriptionTransactionInfo: {
        accountReference: "SOMEONE-ELSE-42",
        amount: 3200,
        correlationId: "corr-2",
      },
    });
    const svc = service();
    const result = await svc.handleRecurringIpn({
      OrderNotificationType: "RECURRING",
      OrderTrackingId: "track-1",
      OrderMerchantReference: "AXONSUBCARD-tenant-1-1",
    });
    expect(result.result).toBe("rejected");
    expect(recurring.settleCardRenewal).not.toHaveBeenCalled();
  });

  it("ignores IPNs for cancelled or unknown subscriptions", async () => {
    prisma.subscriptionCardToken.findUnique.mockResolvedValue(null);
    const svc = service();
    const result = await svc.handleRecurringIpn({
      OrderNotificationType: "RECURRING",
      OrderTrackingId: "track-404",
      OrderMerchantReference: "AXONSUBCARD-tenant-1-1",
    });
    expect(result.result).toBe("ignored");
    expect(pesapal.getTransactionStatus).not.toHaveBeenCalled();
  });

  it("cancels a live subscription (token mapping removal)", async () => {
    prisma.subscriptionCardToken.findUnique.mockResolvedValue({
      id: "tok-1",
      status: "ACTIVE",
      tenantId: "tenant-1",
    });
    prisma.subscriptionCardToken.update.mockResolvedValue({
      id: "tok-1",
      status: "CANCELLED",
      cancelledAt: new Date(),
    });
    const svc = service();
    const result = await svc.cancelCardSubscription("tenant-1");
    expect(result.status).toBe("CANCELLED");
    expect(prisma.subscriptionCardToken.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "tok-1" },
        data: expect.objectContaining({ status: "CANCELLED" }),
      }),
    );
  });
});

describe("stale card renewal safety net", () => {
  it("warns for ACTIVE card tokens with a PENDING invoice >24h after period end", async () => {
    const prisma = makePrismaMock();
    prisma.subscriptionCardToken.findMany.mockResolvedValue([
      { id: "tok-1", tenantId: "tenant-1", tenant: { id: "tenant-1" } },
    ]);
    prisma.subscriptionInvoice.findFirst.mockResolvedValue({ id: "inv-9", status: "PENDING" });
    const pesapal = makePesapalMock();
    const svc = new PesapalRecurringService(
      prisma as any,
      pesapal as any,
      {} as any,
      makeConfig(),
    );
    const report = await svc.reportStaleCardRenewals(new Date());
    expect(report.checked).toBe(1);
    expect(report.warnings).toHaveLength(1);
    expect(report.warnings[0].tenantId).toBe("tenant-1");
  });

  it("stays silent when the invoice was settled", async () => {
    const prisma = makePrismaMock();
    prisma.subscriptionCardToken.findMany.mockResolvedValue([
      { id: "tok-1", tenantId: "tenant-1", tenant: { id: "tenant-1" } },
    ]);
    prisma.subscriptionInvoice.findFirst.mockResolvedValue(null);
    const svc = new PesapalRecurringService(
      prisma as any,
      makePesapalMock() as any,
      {} as any,
      makeConfig(),
    );
    const report = await svc.reportStaleCardRenewals(new Date());
    expect(report.warnings).toHaveLength(0);
  });
});