import { PaystackBillingService } from "./paystack-billing.service";

describe("PaystackBillingService invoice safety", () => {
  const paidInvoice = {
    id: "invoice-1",
    tenantId: "tenant-1",
    status: "PENDING",
    plan: "CORE",
    amount: 3000,
    currency: "KES",
    reference: "AXON-SUB-tenant1-reference",
    provider: "PAYSTACK",
    authorizationUrl: "https://checkout.paystack.com/example",
    periodStart: new Date("2026-11-01T00:00:00.000Z"),
    periodEnd: new Date("2026-12-01T00:00:00.000Z"),
    renewalSequence: 1,
  };

  function build(invoice = paidInvoice) {
    const prisma: any = {
      subscriptionInvoice: {
        findFirst: jest.fn().mockResolvedValue(invoice),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        update: jest.fn(),
      },
      tenant: { update: jest.fn() },
      user: {
        findFirst: jest.fn().mockResolvedValue({ email: "owner@example.test" }),
      },
    };
    const paystack = {
      initializeTransaction: jest.fn(),
      verifyTransaction: jest.fn().mockResolvedValue({
        status: "success",
        reference: invoice.reference,
        amount: 200000,
        currency: "KES",
        metadata: {
          product: "axon_subscription_invoice",
          tenantId: invoice.tenantId,
          invoiceId: invoice.id,
        },
      }),
    };
    const recurringBilling = {
      getInvoiceForPayment: jest.fn().mockResolvedValue(invoice),
    };
    const config = { get: jest.fn().mockReturnValue(undefined) };
    const service = new PaystackBillingService(
      prisma,
      paystack as any,
      recurringBilling as any,
      config as any,
    );
    return { service, prisma, paystack };
  }

  it("persists a successful but amount-mismatched charge as NEEDS_REVIEW", async () => {
    const { service, prisma } = build();

    await expect(
      service.verifyInvoicePayment("tenant-1", paidInvoice.reference),
    ).resolves.toEqual(
      expect.objectContaining({
        status: "NEEDS_REVIEW",
        invoiceId: paidInvoice.id,
        reference: paidInvoice.reference,
      }),
    );

    expect(prisma.subscriptionInvoice.updateMany).toHaveBeenCalledWith({
      where: {
        id: paidInvoice.id,
        tenantId: paidInvoice.tenantId,
        status: { not: "PAID" },
        reference: paidInvoice.reference,
      },
      data: { status: "NEEDS_REVIEW", authorizationUrl: null },
    });
    expect(prisma.tenant.update).not.toHaveBeenCalled();
  });

  it("does not re-verify a payment already held for review", async () => {
    const invoice = { ...paidInvoice, status: "NEEDS_REVIEW" };
    const { service, paystack } = build(invoice);

    await expect(
      service.verifyInvoicePayment("tenant-1", paidInvoice.reference),
    ).resolves.toEqual(
      expect.objectContaining({
        status: "NEEDS_REVIEW",
        invoiceId: paidInvoice.id,
        reference: paidInvoice.reference,
      }),
    );
    expect(paystack.verifyTransaction).not.toHaveBeenCalled();
  });

  it("refuses to start another checkout while an invoice is under review", async () => {
    const invoice = {
      ...paidInvoice,
      status: "NEEDS_REVIEW",
      authorizationUrl: null,
    };
    const { service, paystack } = build(invoice);

    await expect(
      service.initializeInvoicePayment("tenant-1", "user-1"),
    ).rejects.toThrow("on hold for review");

    expect(paystack.initializeTransaction).not.toHaveBeenCalled();
  });

  describe("reopening a checkout link", () => {
    const minutesAgo = (m: number) => new Date(Date.now() - m * 60 * 1000);

    function buildForLink(issuedAt: Date | null, oldCharge: any = { status: "abandoned" }) {
      const invoice = { ...paidInvoice, authorizationIssuedAt: issuedAt };
      const ctx = build(invoice);
      ctx.paystack.verifyTransaction.mockResolvedValue(oldCharge);
      ctx.paystack.initializeTransaction.mockImplementation(async (input: any) => ({
        reference: input.reference,
        authorizationUrl: "https://checkout.paystack.com/fresh",
      }));
      ctx.prisma.subscriptionInvoice.update.mockImplementation(async ({ data }: any) => ({
        ...invoice,
        ...data,
        reference: ctx.paystack.initializeTransaction.mock.calls[0]?.[0]?.reference,
      }));
      return ctx;
    }

    it("hands back a link issued a few minutes ago", async () => {
      const { service, paystack } = buildForLink(minutesAgo(5));
      const result: any = await service.initializeInvoicePayment("tenant-1", "user-1");
      expect(result.authorizationUrl).toBe("https://checkout.paystack.com/example");
      expect(result.reference).toBe(paidInvoice.reference);
      expect(paystack.initializeTransaction).not.toHaveBeenCalled();
    });

    it.each([
      ["a link older than 30 minutes", minutesAgo(31)],
      ["a link with no recorded issue time", null],
    ])("opens a new checkout instead of reopening %s", async (_label, issuedAt) => {
      const { service, paystack, prisma } = buildForLink(issuedAt as Date | null);
      const result: any = await service.initializeInvoicePayment("tenant-1", "user-1");
      expect(paystack.initializeTransaction).toHaveBeenCalledTimes(1);
      expect(paystack.initializeTransaction).toHaveBeenCalledWith(
        expect.objectContaining({ amountKes: 3000 }),
      );
      expect(result.authorizationUrl).toBe("https://checkout.paystack.com/fresh");
      expect(result.reference).not.toBe(paidInvoice.reference);
      expect(prisma.subscriptionInvoice.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            provider: "PAYSTACK",
            authorizationIssuedAt: expect.any(Date),
          }),
        }),
      );
    });

    it("settles instead of replacing when the old link was paid after all", async () => {
      const { service, paystack, prisma } = buildForLink(minutesAgo(90), {
        status: "success",
        reference: paidInvoice.reference,
        amount: 300000,
        currency: "KES",
        metadata: {
          product: "axon_subscription_invoice",
          tenantId: paidInvoice.tenantId,
          invoiceId: paidInvoice.id,
        },
      });
      prisma.subscriptionInvoice.updateMany.mockResolvedValue({ count: 1 });
      prisma.$transaction = jest.fn(async (fn: any) =>
        fn({
          subscriptionInvoice: {
            updateMany: jest.fn().mockResolvedValue({ count: 1 }),
            findUnique: jest.fn().mockResolvedValue({ status: "PAID" }),
          },
          tenant: { update: jest.fn() },
        }),
      );
      const result: any = await service.initializeInvoicePayment("tenant-1", "user-1");
      expect(result.status).toBe("PAID");
      expect(paystack.initializeTransaction).not.toHaveBeenCalled();
    });

    it("keeps an invoice on hold when the old link was paid with the wrong amount", async () => {
      const { service, paystack } = buildForLink(minutesAgo(90), {
        status: "success",
        reference: paidInvoice.reference,
        amount: 200000,
        currency: "KES",
        metadata: {
          product: "axon_subscription_invoice",
          tenantId: paidInvoice.tenantId,
          invoiceId: paidInvoice.id,
        },
      });
      await expect(
        service.initializeInvoicePayment("tenant-1", "user-1"),
      ).rejects.toThrow("on hold for review");
      expect(paystack.initializeTransaction).not.toHaveBeenCalled();
    });
  });
});
