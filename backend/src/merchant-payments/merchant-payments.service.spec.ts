import { MerchantPaymentsService } from './merchant-payments.service';

describe('MerchantPaymentsService', () => {
  const actor = { sub: 'cashier-1', tenantId: 'shop-1' };
  const sale = {
    branchId: 'branch-1',
    paymentMethod: 'MPESA',
    paidAmount: 500,
    items: [{ productId: 'product-1', quantity: 1, unitPrice: 500, discount: 0 }],
  } as any;

  function fixtures() {
    const prisma: any = {
      merchantPaymentAccount: {
        findUnique: jest.fn().mockResolvedValue({ status: 'ACTIVE', subaccountCode: 'ACCT_shop1' }),
        upsert: jest.fn(),
      },
      merchantCharge: {
        create: jest.fn().mockResolvedValue({}),
        findFirst: jest.fn(),
        findUnique: jest.fn(),
        update: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      branch: { findFirst: jest.fn().mockResolvedValue({ id: 'branch-1' }) },
      product: { findMany: jest.fn().mockResolvedValue([{
        id: 'product-1', name: 'Rice', basePrice: 500, taxRate: 0,
        trackInventory: false, priceOverrides: [], stock: [],
      }]) },
      customer: { findFirst: jest.fn() },
      tenant: { findUnique: jest.fn().mockResolvedValue({ name: 'Shop One' }) },
      user: { findUnique: jest.fn().mockResolvedValue({ email: 'owner@example.test' }) },
      tenantOnboarding: { findUnique: jest.fn().mockResolvedValue({ id: 'onboarding-1', ownerUserId: 'owner-1' }) },
      tenantOnboardingStep: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 'payment-1' }),
      },
    };
    prisma.$transaction = jest.fn((callback) => callback(prisma));
    const paystack: any = {
      listKenyanBanks: jest.fn().mockResolvedValue([{ code: '001', name: 'Test Bank' }]),
      createMerchantSubaccount: jest.fn().mockResolvedValue({
        subaccount_code: 'ACCT_shop1', account_name: 'SHOP ONE', currency: 'KES', active: true,
      }),
      createMerchantMpesaCharge: jest.fn().mockImplementation(async ({ reference }) => ({
        reference, status: 'pay_offline',
      })),
      verifyTransaction: jest.fn(),
    };
    const sales: any = { createSale: jest.fn().mockResolvedValue({ id: 'sale-1', receiptNumber: 'RCP-1' }) };
    return { prisma, paystack, sales, service: new MerchantPaymentsService(prisma, paystack, sales) };
  }

  it('refuses to charge a customer until that shop has an active payout account', async () => {
    const { prisma, paystack, service } = fixtures();
    prisma.merchantPaymentAccount.findUnique.mockResolvedValue(null);
    await expect(service.startMpesa(actor, {
      requestId: 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
      phoneNumber: '0712345678', customerEmail: 'customer@example.test', sale,
    })).rejects.toThrow('Set up your business payout account');
    expect(paystack.createMerchantMpesaCharge).not.toHaveBeenCalled();
  });

  it('routes a server-priced charge to the shop subaccount', async () => {
    const { prisma, paystack, service } = fixtures();
    const result = await service.startMpesa(actor, {
      requestId: 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
      phoneNumber: '0712345678', customerEmail: 'customer@example.test', sale,
    });
    expect(result.status).toBe('PENDING');
    expect(paystack.createMerchantMpesaCharge).toHaveBeenCalledWith(expect.objectContaining({
      amountKes: 500, subaccountCode: 'ACCT_shop1', tenantId: 'shop-1',
      phone: '254712345678',
    }));
    expect(prisma.merchantCharge.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ tenantId: 'shop-1', subaccountCode: 'ACCT_shop1' }),
    }));
  });

  it('stores only masked bank data after Paystack creates the merchant subaccount', async () => {
    const { prisma, paystack, service } = fixtures();
    prisma.merchantPaymentAccount.findUnique.mockResolvedValue({
      status: 'ACTIVE', provider: 'PAYSTACK', currency: 'KES',
      bankName: 'Test Bank', accountName: 'SHOP ONE', accountLast4: '7890',
    });
    await service.configureAccount({ sub: 'owner-1', tenantId: 'shop-1' }, {
      bankCode: '001', accountNumber: '1234567890', confirmAccountOwnership: true,
    });
    expect(paystack.createMerchantSubaccount).toHaveBeenCalledWith(expect.objectContaining({
      accountNumber: '1234567890', bankCode: '001',
    }));
    const written = prisma.merchantPaymentAccount.upsert.mock.calls[0][0];
    expect(written.create.accountLast4).toBe('7890');
    expect(JSON.stringify(written)).not.toContain('1234567890');
  });

  it('never creates a sale when Paystack confirms the wrong settlement subaccount', async () => {
    const { prisma, paystack, sales, service } = fixtures();
    const charge = {
      id: 'charge-1', tenantId: 'shop-1', reference: 'CBSALE_ref',
      subaccountCode: 'ACCT_shop1', amount: 500, status: 'PENDING',
      providerStatus: null, saleId: null, receiptNumber: null, salePayload: sale,
      cashierId: 'cashier-1',
    };
    prisma.merchantCharge.findFirst.mockResolvedValue(charge);
    prisma.merchantCharge.findUnique.mockResolvedValue(charge);
    prisma.merchantCharge.update.mockImplementation(async ({ data }) => ({ ...charge, ...data }));
    paystack.verifyTransaction.mockResolvedValue({
      reference: 'CBSALE_ref', status: 'success', amount: 50000, currency: 'KES',
      subaccount: { subaccount_code: 'ACCT_other' },
    });
    const result = await service.status(actor, 'CBSALE_ref');
    expect(result.status).toBe('NEEDS_REVIEW');
    expect(sales.createSale).not.toHaveBeenCalled();
  });

  it('records one sale only after exact Paystack verification', async () => {
    const { prisma, paystack, sales, service } = fixtures();
    const charge = {
      id: 'charge-1', tenantId: 'shop-1', reference: 'CBSALE_ref',
      subaccountCode: 'ACCT_shop1', amount: 500, status: 'PENDING',
      providerStatus: null, saleId: null, receiptNumber: null, salePayload: sale,
      cashierId: 'cashier-1',
    };
    prisma.merchantCharge.findFirst.mockResolvedValue(charge);
    prisma.merchantCharge.findUnique.mockResolvedValue(charge);
    prisma.merchantCharge.update.mockImplementation(async ({ data }) => ({ ...charge, ...data }));
    paystack.verifyTransaction.mockResolvedValue({
      reference: 'CBSALE_ref', status: 'success', amount: 50000, currency: 'KES',
      subaccount: { subaccount_code: 'ACCT_shop1' },
    });
    const result = await service.status(actor, 'CBSALE_ref');
    expect(result).toMatchObject({ status: 'COMPLETED', saleId: 'sale-1', receiptNumber: 'RCP-1' });
    expect(sales.createSale).toHaveBeenCalledTimes(1);
    expect(prisma.payment.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ transactionId: 'CBSALE_ref', saleId: 'sale-1' }),
    }));
  });
});
