import { MerchantPaymentsService } from './merchant-payments.service';

describe('MerchantPaymentsService', () => {
  const actor = {
    sub: 'cashier-1',
    tenantId: 'shop-1',
    permissions: ['roles.update'],
  };
  const sale = {
    branchId: 'branch-1',
    paymentMethod: 'MPESA',
    paidAmount: 500,
    items: [{ productId: 'product-1', quantity: 1, unitPrice: 500, discount: 0 }],
  } as any;

  function fixtures() {
    const prisma: any = {
      merchantPaymentAccount: {
        findUnique: jest.fn().mockResolvedValue({ status: 'ACTIVE', subaccountCode: 'ACCT_shop1', accountName: 'SHOP ONE' }),
        upsert: jest.fn(),
      },
      merchantCharge: {
        create: jest.fn().mockResolvedValue({}),
        aggregate: jest.fn().mockResolvedValue({ _sum: { amount: 0 } }),
        findFirst: jest.fn(),
        findUnique: jest.fn(),
        update: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      retailReceivable: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'receivable-1', outstandingAmount: 500, status: 'OPEN',
        }),
      },
      peerReceivable: { findFirst: jest.fn() },
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
      $queryRaw: jest.fn().mockResolvedValue([]),
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
    const sales: any = {
      quoteMerchantMpesaSale: jest.fn(async (_userId, _tenantId, saleInput) => ({
        amount: 500,
        sale: saleInput,
      })),
      createSale: jest.fn().mockResolvedValue({ id: 'sale-1', receiptNumber: 'RCP-1' }),
    };
    const finance: any = {
      recordRetailPayment: jest.fn().mockResolvedValue({ id: 'retail-payment-1' }),
      recordPeerPayment: jest.fn().mockResolvedValue({ id: 'peer-payment-1' }),
    };
    return {
      prisma,
      paystack,
      sales,
      finance,
      service: new MerchantPaymentsService(prisma, paystack, sales, undefined, finance),
    };
  }

  function mockCharge(prisma: any, charge: any) {
    prisma.merchantCharge.findFirst.mockImplementation(async () => charge);
    prisma.merchantCharge.findUnique.mockImplementation(async () => ({
      ...charge,
    }));
    prisma.merchantCharge.updateMany.mockImplementation(
      async ({ data }: any) => {
        Object.assign(charge, data);
        return { count: 1 };
      },
    );
    prisma.merchantCharge.update.mockImplementation(async ({ data }: any) => {
      Object.assign(charge, data);
      return { ...charge };
    });
  }

  it('refuses to charge a customer until that shop has an active payout account', async () => {
    const { prisma, paystack, service } = fixtures();
    prisma.merchantPaymentAccount.findUnique.mockResolvedValue(null);
    await expect(service.startMpesa(actor, {
      requestId: 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
      phoneNumber: '0712345678', customerEmail: 'customer@example.test', sale,
    })).rejects.toThrow('Add your business payout account in Customer payments');
    expect(paystack.createMerchantMpesaCharge).not.toHaveBeenCalled();
  });

  it('blocks M-Pesa when an old payout record has no resolved account holder', async () => {
    const { prisma, paystack, service } = fixtures();
    prisma.merchantPaymentAccount.findUnique.mockResolvedValue({
      status: 'ACTIVE', subaccountCode: 'ACCT_shop1', accountName: null,
    });

    await expect(service.startMpesa(actor, {
      requestId: 'cccccccc-cccc-4ccc-accc-cccccccccccc',
      phoneNumber: '0712345678', customerEmail: 'customer@example.test', sale,
    })).rejects.toThrow('Paystack has not verified this business payout account yet');

    expect(paystack.createMerchantMpesaCharge).not.toHaveBeenCalled();
  });

  it('marks legacy bank details without a Paystack account name as unverified', async () => {
    const { prisma, service } = fixtures();
    prisma.merchantPaymentAccount.findUnique.mockResolvedValue({
      status: 'ACTIVE', bankName: 'Test Bank', accountLast4: '7890', accountName: null,
    });

    await expect(service.account(actor)).resolves.toMatchObject({
      status: 'PENDING_VERIFICATION',
      bankName: 'Test Bank',
      accountHolderVerified: false,
    });
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
      phone: '+254712345678',
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
    await service.configureAccount({
      sub: 'owner-1', tenantId: 'shop-1', permissions: ['roles.update'],
    }, {
      bankCode: '001', accountNumber: '1234567890', confirmAccountOwnership: true,
    });
    expect(paystack.createMerchantSubaccount).toHaveBeenCalledWith(expect.objectContaining({
      accountNumber: '1234567890', bankCode: '001',
    }));
    const written = prisma.merchantPaymentAccount.upsert.mock.calls[0][0];
    expect(written.create.accountLast4).toBe('7890');
    expect(JSON.stringify(written)).not.toContain('1234567890');
    expect(written.create.bankName).toBe('Test Bank');
    expect(written.create.accountName).toBe('SHOP ONE');
  });

  it('does not activate a payout route if Paystack cannot resolve the account holder', async () => {
    const { prisma, paystack, service } = fixtures();
    paystack.createMerchantSubaccount.mockResolvedValue({
      subaccount_code: 'ACCT_shop1', currency: 'KES', active: true,
    });

    await expect(service.configureAccount({
      sub: 'owner-1', tenantId: 'shop-1', permissions: ['roles.update'],
    }, {
      bankCode: '001', accountNumber: '1234567890', confirmAccountOwnership: true,
    })).rejects.toThrow('could not confirm the account holder name');

    expect(prisma.merchantPaymentAccount.upsert).not.toHaveBeenCalled();
  });

  it('routes a requested debt payment through the merchant subaccount', async () => {
    const { prisma, paystack, service } = fixtures();
    const result = await service.startReceivableMpesa(actor, {
      requestId: 'bbbbbbbb-bbbb-4bbb-abbb-bbbbbbbbbbbb',
      receivableType: 'retail',
      receivableId: 'receivable-1',
      branchId: 'branch-1',
      amount: 250,
      phoneNumber: '0712345678',
      customerEmail: 'customer@example.test',
    });
    expect(result).toMatchObject({ status: 'PENDING', entityType: 'RECEIVABLE', amount: 250 });
    expect(paystack.createMerchantMpesaCharge).toHaveBeenCalledWith(expect.objectContaining({
      amountKes: 250,
      subaccountCode: 'ACCT_shop1',
      tenantId: 'shop-1',
      phone: '+254712345678',
    }));
    expect(prisma.merchantCharge.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({
        purpose: 'RECEIVABLE',
        receivableId: 'receivable-1',
        receivableType: 'retail',
        requestId: 'bbbbbbbb-bbbb-4bbb-abbb-bbbbbbbbbbbb',
      }),
    }));
  });

  it('allocates a debt payment only after Paystack verifies the merchant settlement', async () => {
    const { prisma, paystack, finance, service } = fixtures();
    const charge = {
      id: 'charge-debt-1', tenantId: 'shop-1', reference: 'CBDUE_ref',
      subaccountCode: 'ACCT_shop1', amount: 250, status: 'PENDING',
      providerStatus: null, purpose: 'RECEIVABLE', receivableType: 'retail',
      receivableId: 'receivable-1', receivablePaymentId: null,
      saleId: null, receiptNumber: null, salePayload: {}, branchId: 'branch-1',
      cashierId: 'cashier-1',
    };
    mockCharge(prisma, charge);
    paystack.verifyTransaction.mockResolvedValue({
      reference: 'CBDUE_ref', status: 'success', amount: 25000, currency: 'KES',
      subaccount: { subaccount_code: 'ACCT_shop1' },
    });

    const result = await service.status(actor, 'CBDUE_ref');
    expect(result).toMatchObject({
      status: 'COMPLETED',
      purpose: 'RECEIVABLE',
      receivablePaymentId: 'retail-payment-1',
    });
    expect(finance.recordRetailPayment).toHaveBeenCalledWith(
      'cashier-1',
      'shop-1',
      'receivable-1',
      expect.objectContaining({
        amount: 250,
        method: 'MPESA',
        reference: 'CBDUE_ref',
        offlineId: 'paystack-CBDUE_ref',
      }),
      true,
    );
    expect(prisma.merchantCharge.update).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ status: 'COMPLETED', receivablePaymentId: 'retail-payment-1' }),
    }));
  });

  it('never creates a sale when Paystack confirms the wrong settlement subaccount', async () => {
    const { prisma, paystack, sales, service } = fixtures();
    const charge = {
      id: 'charge-1', tenantId: 'shop-1', reference: 'CBSALE_ref',
      subaccountCode: 'ACCT_shop1', amount: 500, status: 'PENDING',
      providerStatus: null, saleId: null, receiptNumber: null, salePayload: sale,
      cashierId: 'cashier-1',
    };
    mockCharge(prisma, charge);
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
    mockCharge(prisma, charge);
    paystack.verifyTransaction.mockResolvedValue({
      reference: 'CBSALE_ref', status: 'success', amount: 50000, currency: 'KES',
      subaccount: { subaccount_code: 'ACCT_shop1' },
    });
    const result = await service.status(actor, 'CBSALE_ref');
    expect(result).toMatchObject({ status: 'COMPLETED', saleId: 'sale-1', receiptNumber: 'RCP-1' });
    expect(sales.createSale).toHaveBeenCalledTimes(1);
    expect(sales.createSale).toHaveBeenCalledWith(
      'cashier-1',
      'shop-1',
      sale,
      { verifiedMerchantMpesa: true },
    );
    expect(prisma.payment.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ transactionId: 'CBSALE_ref', saleId: 'sale-1' }),
    }));
  });
});
