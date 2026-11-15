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
});
