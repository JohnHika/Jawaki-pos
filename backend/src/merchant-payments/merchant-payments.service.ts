import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  Injectable,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  MerchantPaymentAccount,
  PaymentMethod,
  PaymentStatus,
  Prisma,
  ReceivablePaymentMethod,
} from '@prisma/client';
import { randomBytes } from 'crypto';
import { PaystackService } from '../ai-billing/paystack.service';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateSaleDto } from '../sales/dto/sales.dto';
import { SalesService } from '../sales/sales.service';
import {
  ConfigureMerchantPayoutDto,
  StartMerchantMpesaDto,
  StartMerchantReceivableMpesaDto,
} from './dto/merchant-payments.dto';
import { LegalPolicyService } from '../legal/legal-policy.service';
import { FinanceService } from '../finance/finance.service';

type Actor = { sub: string; tenantId: string; permissions?: string[] };

@Injectable()
export class MerchantPaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly sales: SalesService,
    @Optional() private readonly legalPolicies?: LegalPolicyService,
    @Optional() private readonly finance?: FinanceService,
  ) {}

  async account(actor: Actor) {
    const row = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId },
    });
    if (!row) return { status: 'NOT_CONFIGURED', provider: 'PAYSTACK', currency: 'KES' };
    const payout = await this.refreshPayoutVerification(row);
    const accountName = payout.row.accountName?.trim() || null;
    return {
      status: payout.status,
      provider: payout.row.provider,
      currency: payout.row.currency,
      bankCode: payout.row.bankCode,
      bankName: payout.row.bankName,
      accountName,
      accountHolderVerified: Boolean(accountName),
      paystackVerified: payout.paystackVerified,
      accountLast4: payout.row.accountLast4,
      updatedAt: payout.row.updatedAt,
    };
  }

  async banks() {
    return this.paystack.listKenyanBanks();
  }

  async configureAccount(actor: Actor, dto: ConfigureMerchantPayoutDto) {
    if (!actor.permissions?.includes('roles.update')) {
      throw new ForbiddenException('You do not have permission to change payout details');
    }
    await this.legalPolicies?.assertCurrentAcceptance(actor.tenantId, 'MERCHANT_PAYMENT_TERMS');
    if (dto.confirmAccountOwnership !== true) {
      throw new BadRequestException('Confirm that this payout account belongs to your business');
    }
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: actor.tenantId }, select: { name: true },
    });
    const owner = await this.prisma.user.findUnique({
      where: { id: actor.sub }, select: { email: true },
    });
    if (!tenant || !owner) throw new NotFoundException('Business owner was not found');

    const availableBanks = await this.paystack.listKenyanBanks();
    const bank = availableBanks.find((item) => item.code === dto.bankCode);
    if (!bank) throw new BadRequestException('Select a supported Kenyan bank');

    const existing = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId },
    });
    const payoutDetails = {
      businessName: tenant.name,
      bankCode: bank.code,
      accountNumber: dto.accountNumber,
      contactEmail: owner.email,
    };
    // Reuse an existing Paystack subaccount when a merchant changes banks so
    // an old settlement route is not left active as an orphan.
    const subaccount = existing && this.paystack.updateMerchantSubaccount
      ? await this.paystack.updateMerchantSubaccount(existing.subaccountCode, payoutDetails)
      : await this.paystack.createMerchantSubaccount(payoutDetails);
    const subaccountCode = subaccount.subaccount_code || existing?.subaccountCode;
    if (!subaccountCode || subaccount.active === false ||
        (subaccount.currency && subaccount.currency !== 'KES')) {
      throw new ServiceUnavailableException(
        'Paystack did not confirm a usable KES payout account. No payment route was changed.',
      );
    }

    let providerAccount = subaccount;
    if (typeof providerAccount.is_verified !== 'boolean' &&
        typeof this.paystack.getMerchantSubaccount === 'function') {
      try {
        providerAccount = await this.paystack.getMerchantSubaccount(subaccountCode);
      } catch {
        // Preserve the submitted bank details, but keep M-Pesa locked until
        // Paystack's verification state can be confirmed.
      }
    }
    const accountName = providerAccount.account_name?.trim() || null;
    // Older non-production adapters may not expose Paystack's verification
    // endpoint. In production the explicit is_verified flag is authoritative.
    const paystackVerified = typeof this.paystack.getMerchantSubaccount !== 'function'
      ? Boolean(accountName)
      : providerAccount.subaccount_code === subaccountCode &&
        providerAccount.is_verified === true && providerAccount.active !== false;
    if (typeof this.paystack.getMerchantSubaccount !== 'function' && !accountName) {
      throw new ServiceUnavailableException(
        'Paystack could not confirm the account holder name. Check the bank and account number before accepting customer payments.',
      );
    }
    const accountStatus = providerAccount.active === false
      ? 'INACTIVE'
      : paystackVerified ? 'ACTIVE' : 'PENDING_VERIFICATION';

    await this.prisma.$transaction(async (tx) => {
      await tx.merchantPaymentAccount.upsert({
        where: { tenantId: actor.tenantId },
        create: {
          tenantId: actor.tenantId,
          subaccountCode,
          bankCode: bank.code,
          bankName: bank.name,
          accountName,
          accountLast4: dto.accountNumber.slice(-4),
          currency: 'KES',
          status: accountStatus,
        },
        update: {
          subaccountCode,
          bankCode: bank.code,
          bankName: bank.name,
          accountName,
          accountLast4: dto.accountNumber.slice(-4),
          currency: 'KES',
          status: accountStatus,
        },
      });
      const onboarding = await tx.tenantOnboarding.findUnique({
        where: { tenantId: actor.tenantId }, select: { id: true },
      });
      if (onboarding) {
        await tx.tenantOnboardingStep.updateMany({
          where: { onboardingId: onboarding.id, key: 'activate_payment' },
          data: paystackVerified
            ? { status: 'COMPLETED', completedAt: new Date(), deferredAt: null }
            : { status: 'PENDING', completedAt: null, deferredAt: null },
        });
      }
    });
    return this.account(actor);
  }

  async startMpesa(actor: Actor, input: StartMerchantMpesaDto) {
    const prior = await this.prisma.merchantCharge.findUnique({
      where: { tenantId_requestId: { tenantId: actor.tenantId, requestId: input.requestId } },
    });
    if (prior) return this.presentStart(prior);
    const account = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId },
    });
    if (!account) {
      throw new ConflictException(
        'Add your business payout account in Customer payments to accept M-Pesa sales.',
      );
    }
    const payout = await this.refreshPayoutVerification(account);
    if (!payout.paystackVerified || payout.status !== 'ACTIVE') {
      throw new ConflictException(
        'Paystack has not verified this business payout account yet. Finish verification in Customer payments to accept M-Pesa sales.',
      );
    }
    if (input.sale.paymentMethod !== PaymentMethod.MPESA || input.sale.tenders?.length) {
      throw new BadRequestException('This checkout accepts one M-Pesa payment for one sale');
    }
    const amount = await this.quoteSale(actor.tenantId, input.sale);
    if (Math.abs((input.sale.paidAmount ?? amount) - amount) > 0.01) {
      throw new BadRequestException('The sale total changed. Refresh the cart before requesting payment');
    }
    const phone = this.normalizePhone(input.phoneNumber);
    const paystackEmail = this.paystack.getMerchantPayerEmail?.() || 'billing@archeaxon.com';
    const reference = `CBSALE-${randomBytes(12).toString('hex')}`;
    const salePayload: CreateSaleDto = {
      ...input.sale,
      paymentMethod: PaymentMethod.MPESA,
      paidAmount: amount,
      offlineId: `paystack-${reference}`,
    };
    try {
      await this.prisma.merchantCharge.create({
        data: {
          tenantId: actor.tenantId,
          requestId: input.requestId,
          branchId: salePayload.branchId,
          cashierId: actor.sub,
          reference,
          subaccountCode: payout.row.subaccountCode,
          amount: new Prisma.Decimal(amount),
          phone,
          paystackEmail,
          salePayload: salePayload as unknown as Prisma.InputJsonValue,
        },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const concurrent = await this.prisma.merchantCharge.findUnique({
          where: { tenantId_requestId: { tenantId: actor.tenantId, requestId: input.requestId } },
        });
        if (concurrent) return this.presentStart(concurrent);
      }
      throw error;
    }

    try {
      const prompt = await this.paystack.createMerchantMpesaCharge({
        email: paystackEmail,
        amountKes: amount,
        phone,
        reference,
        subaccountCode: payout.row.subaccountCode,
        tenantId: actor.tenantId,
      });
      if (prompt.reference !== reference) {
        await this.prisma.merchantCharge.update({
          where: { reference }, data: { status: 'NEEDS_REVIEW', providerStatus: 'reference_mismatch' },
        });
        throw new ServiceUnavailableException('Paystack returned an unexpected payment reference');
      }
      await this.prisma.merchantCharge.update({
        where: { reference }, data: { providerStatus: prompt.status },
      });
      return { reference, status: 'PENDING', amount, message: prompt.display_text ?? 'Approve the M-Pesa prompt on the customer phone' };
    } catch (error) {
      // A network timeout can happen after Paystack accepted a charge. Keep
      // this reference queryable so a retry cannot prompt the customer twice.
      if (error instanceof ServiceUnavailableException) throw error;
      if (error instanceof HttpException && error.getStatus() >= 400 && error.getStatus() < 500) {
        await this.prisma.merchantCharge.update({
          where: { reference }, data: { status: 'FAILED', providerStatus: 'initiation_rejected' },
        });
        throw new BadRequestException(error.message);
      }
      await this.prisma.merchantCharge.update({
        where: { reference }, data: { providerStatus: 'initiation_unknown' },
      });
      return { reference, status: 'PENDING', amount,
        message: 'Payment request could not be confirmed yet. Check this reference before retrying.' };
    }
  }

  async startReceivableMpesa(actor: Actor, input: StartMerchantReceivableMpesaDto) {
    const prior = await this.prisma.merchantCharge.findUnique({
      where: { tenantId_requestId: { tenantId: actor.tenantId, requestId: input.requestId } },
    });
    if (prior) {
      if (prior.purpose !== 'RECEIVABLE' || prior.receivableId !== input.receivableId ||
          prior.receivableType !== input.receivableType) {
        throw new ConflictException('This payment request key was already used for a different request');
      }
      return this.presentStart(prior);
    }

    const account = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId },
    });
    if (!account) {
      throw new ConflictException(
        'Add your business payout account in Customer payments to accept M-Pesa debt payments.',
      );
    }
    const payout = await this.refreshPayoutVerification(account);
    if (!payout.paystackVerified || payout.status !== 'ACTIVE') {
      throw new ConflictException(
        'Paystack has not verified this business payout account yet. Finish verification in Customer payments to accept M-Pesa debt payments.',
      );
    }
    const receivable = input.receivableType === 'retail'
      ? await this.prisma.retailReceivable.findFirst({
          where: { id: input.receivableId, tenantId: actor.tenantId, branchId: input.branchId },
          select: { id: true, outstandingAmount: true, status: true },
        })
      : await this.prisma.peerReceivable.findFirst({
          where: { id: input.receivableId, tenantId: actor.tenantId, branchId: input.branchId },
          select: { id: true, outstandingAmount: true, status: true },
        });
    if (!receivable) throw new NotFoundException('Receivable was not found for this business');
    if (receivable.status === 'PAID' || receivable.status === 'WRITTEN_OFF') {
      throw new ConflictException('This receivable is already closed');
    }
    if (input.amount > Number(receivable.outstandingAmount)) {
      throw new BadRequestException('Payment amount exceeds outstanding balance');
    }

    const phone = this.normalizePhone(input.phoneNumber);
    const paystackEmail = this.paystack.getMerchantPayerEmail?.() || 'billing@archeaxon.com';
    const reference = `CBDUE-${randomBytes(12).toString('hex')}`;
    try {
      await this.prisma.merchantCharge.create({
        data: {
          tenantId: actor.tenantId,
          requestId: input.requestId,
          branchId: input.branchId,
          cashierId: actor.sub,
          reference,
          subaccountCode: payout.row.subaccountCode,
          amount: new Prisma.Decimal(input.amount),
          phone,
          paystackEmail,
          salePayload: {},
          purpose: 'RECEIVABLE',
          receivableType: input.receivableType,
          receivableId: input.receivableId,
        },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const concurrent = await this.prisma.merchantCharge.findUnique({
          where: { tenantId_requestId: { tenantId: actor.tenantId, requestId: input.requestId } },
        });
        if (concurrent) return this.presentStart(concurrent);
      }
      throw error;
    }

    try {
      const prompt = await this.paystack.createMerchantMpesaCharge({
        email: paystackEmail,
        amountKes: input.amount,
        phone,
        reference,
        subaccountCode: payout.row.subaccountCode,
        tenantId: actor.tenantId,
      });
      if (prompt.reference !== reference) {
        await this.prisma.merchantCharge.update({
          where: { reference }, data: { status: 'NEEDS_REVIEW', providerStatus: 'reference_mismatch' },
        });
        throw new ServiceUnavailableException('Paystack returned an unexpected payment reference');
      }
      await this.prisma.merchantCharge.update({
        where: { reference }, data: { providerStatus: prompt.status },
      });
      return {
        reference,
        status: 'PENDING',
        amount: input.amount,
        entityType: 'RECEIVABLE',
        message: prompt.display_text ?? 'Approve the M-Pesa prompt on the customer phone',
      };
    } catch (error) {
      if (error instanceof ServiceUnavailableException) throw error;
      if (error instanceof HttpException && error.getStatus() >= 400 && error.getStatus() < 500) {
        await this.prisma.merchantCharge.update({
          where: { reference }, data: { status: 'FAILED', providerStatus: 'initiation_rejected' },
        });
        throw new BadRequestException(error.message);
      }
      await this.prisma.merchantCharge.update({
        where: { reference }, data: { providerStatus: 'initiation_unknown' },
      });
      return {
        reference,
        status: 'PENDING',
        amount: input.amount,
        entityType: 'RECEIVABLE',
        message: 'Payment request could not be confirmed yet. Check this reference before retrying.',
      };
    }
  }

  async status(actor: Actor, reference: string) {
    const charge = await this.prisma.merchantCharge.findFirst({
      where: { tenantId: actor.tenantId, reference },
    });
    if (!charge) throw new NotFoundException('Payment was not found for this business');
    if (charge.status === 'COMPLETED' || charge.status === 'FAILED') return this.presentCharge(charge);
    return this.verifyAndSettle(reference);
  }

  async recentCharges(actor: Actor) {
    const charges = await this.prisma.merchantCharge.findMany({
      where: { tenantId: actor.tenantId, status: { in: ['PENDING', 'SETTLING', 'NEEDS_REVIEW'] } },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    return charges.map((charge) => ({ ...this.presentCharge(charge), createdAt: charge.createdAt }));
  }

  async handleWebhook(event: string, data: { reference?: string }) {
    if (event !== 'charge.success' || !data?.reference) return { received: true, handled: false };
    const charge = await this.prisma.merchantCharge.findUnique({ where: { reference: data.reference } });
    if (!charge) return { received: true, handled: false };
    await this.verifyAndSettle(charge.reference);
    return { received: true, handled: true };
  }

  private async refreshPayoutVerification(row: MerchantPaymentAccount) {
    const legacyVerified = row.status === 'ACTIVE' && Boolean(row.accountName?.trim());
    if (typeof this.paystack.getMerchantSubaccount !== 'function') {
      return {
        row,
        status: row.status === 'ACTIVE' && !legacyVerified
          ? 'PENDING_VERIFICATION'
          : row.status,
        paystackVerified: legacyVerified,
      };
    }

    try {
      const providerAccount = await this.paystack.getMerchantSubaccount(row.subaccountCode);
      if (providerAccount.subaccount_code !== row.subaccountCode ||
          typeof providerAccount.is_verified !== 'boolean') {
        return {
          row,
          status: row.status === 'ACTIVE' ? 'PENDING_VERIFICATION' : row.status,
          paystackVerified: false,
        };
      }

      const paystackVerified = providerAccount.is_verified && providerAccount.active !== false;
      const status = providerAccount.active === false
        ? 'INACTIVE'
        : paystackVerified ? 'ACTIVE' : 'PENDING_VERIFICATION';
      const accountName = providerAccount.account_name?.trim() || row.accountName;
      const changed = status !== row.status || accountName !== row.accountName;
      const updated = changed
        ? await this.prisma.merchantPaymentAccount.update({
            where: { tenantId: row.tenantId },
            data: { status, accountName },
          })
        : row;
      if (status !== row.status) {
        const onboarding = await this.prisma.tenantOnboarding.findUnique({
          where: { tenantId: row.tenantId },
          select: { id: true },
        });
        if (onboarding) {
          await this.prisma.tenantOnboardingStep.updateMany({
            where: { onboardingId: onboarding.id, key: 'activate_payment' },
            data: status === 'ACTIVE'
              ? { status: 'COMPLETED', completedAt: new Date(), deferredAt: null }
              : { status: 'PENDING', completedAt: null, deferredAt: null },
          });
        }
      }
      return { row: updated, status, paystackVerified };
    } catch {
      // Do not authorize a new charge from stale local state when Paystack's
      // current verification status cannot be confirmed.
      return {
        row,
        status: row.status === 'ACTIVE' ? 'PENDING_VERIFICATION' : row.status,
        paystackVerified: false,
      };
    }
  }

  private async verifyAndSettle(reference: string) {
    const charge = await this.prisma.merchantCharge.findUnique({ where: { reference } });
    if (!charge) throw new NotFoundException('Payment was not found');
    if (charge.status === 'COMPLETED' || charge.status === 'FAILED') return this.presentCharge(charge);

    let verified: Awaited<ReturnType<PaystackService['verifyTransaction']>>;
    try {
      verified = await this.paystack.verifyTransaction(reference);
    } catch {
      return this.presentCharge(charge);
    }
    if (verified.reference !== reference ||
        verified.currency !== 'KES' ||
        verified.amount !== Math.round(Number(charge.amount) * 100)) {
      const reviewed = await this.prisma.merchantCharge.update({
        where: { reference }, data: { status: 'NEEDS_REVIEW', providerStatus: 'verification_mismatch' },
      });
      return this.presentCharge(reviewed);
    }
    if (verified.status !== 'success') {
      const finalFailure = ['failed', 'abandoned', 'reversed'].includes(verified.status);
      const updated = await this.prisma.merchantCharge.update({
        where: { reference },
        data: { status: finalFailure ? 'FAILED' : 'PENDING', providerStatus: verified.status },
      });
      return this.presentCharge(updated);
    }
    const providerSubaccount = typeof verified.subaccount === 'string'
      ? verified.subaccount : verified.subaccount?.subaccount_code;
    if (providerSubaccount !== charge.subaccountCode) {
      const reviewed = await this.prisma.merchantCharge.update({
        where: { reference }, data: { status: 'NEEDS_REVIEW', providerStatus: 'settlement_mismatch' },
      });
      return this.presentCharge(reviewed);
    }

    const stale = new Date(Date.now() - 60_000);
    const claimed = await this.prisma.merchantCharge.updateMany({
      where: {
        id: charge.id,
        OR: [
          { status: { in: ['PENDING', 'NEEDS_REVIEW'] } },
          { status: 'SETTLING', updatedAt: { lt: stale } },
        ],
      },
      data: { status: 'SETTLING', providerStatus: 'success' },
    });
    if (!claimed.count) {
      const current = await this.prisma.merchantCharge.findUnique({ where: { reference } });
      return this.presentCharge(current!);
    }

    try {
      if (charge.purpose === 'RECEIVABLE') {
        if (!this.finance || !charge.receivableId ||
            (charge.receivableType !== 'retail' && charge.receivableType !== 'peer')) {
          throw new Error('Receivable charge details are incomplete');
        }
        const paymentDto = {
          branchId: charge.branchId,
          amount: Number(charge.amount),
          method: ReceivablePaymentMethod.MPESA,
          reference,
          notes: 'Paystack M-Pesa debt collection',
          offlineId: `paystack-${reference}`,
        };
        const payment = charge.receivableType === 'retail'
          ? await this.finance.recordRetailPayment(
              charge.cashierId, charge.tenantId, charge.receivableId, paymentDto,
            )
          : await this.finance.recordPeerPayment(
              charge.cashierId, charge.tenantId, charge.receivableId, paymentDto,
            );
        const completed = await this.prisma.merchantCharge.update({
          where: { reference },
          data: { status: 'COMPLETED', receivablePaymentId: payment.id },
        });
        return this.presentCharge(completed);
      }

      const sale = await this.sales.createSale(
        charge.cashierId,
        charge.tenantId,
        charge.salePayload as unknown as CreateSaleDto,
        { verifiedMerchantMpesa: true },
      );
      const completed = await this.prisma.$transaction(async (tx) => {
        const payment = await tx.payment.findFirst({
          where: { saleId: sale.id, transactionId: reference }, select: { id: true },
        });
        if (!payment) {
          await tx.payment.create({
            data: {
              saleId: sale.id,
              method: PaymentMethod.MPESA,
              amount: charge.amount,
              status: PaymentStatus.COMPLETED,
              transactionId: reference,
              paidAt: new Date(),
            },
          });
        }
        return tx.merchantCharge.update({
          where: { reference },
          data: { status: 'COMPLETED', saleId: sale.id, receiptNumber: sale.receiptNumber },
        });
      });
      return this.presentCharge(completed);
    } catch {
      // The customer's payment is real. Preserve it for reconciliation if
      // stock or a database error prevents receipt creation after the charge.
      const reviewed = await this.prisma.merchantCharge.update({
        where: { reference }, data: { status: 'NEEDS_REVIEW', providerStatus: 'paid_receipt_pending' },
      });
      return this.presentCharge(reviewed);
    }
  }

  private async quoteSale(tenantId: string, sale: CreateSaleDto): Promise<number> {
    const branch = await this.prisma.branch.findFirst({
      where: { id: sale.branchId, tenantId, isActive: true }, select: { id: true },
    });
    if (!branch) throw new NotFoundException('Branch was not found for this business');
    if (sale.customerId) {
      const customer = await this.prisma.customer.findFirst({
        where: { id: sale.customerId, tenantId }, select: { id: true },
      });
      if (!customer) throw new BadRequestException('Customer was not found for this business');
    }
    const ids = sale.items.map((item) => item.productId);
    if (new Set(ids).size !== ids.length) throw new BadRequestException('Combine duplicate cart lines before payment');
    const products = await this.prisma.product.findMany({
      where: { tenantId, id: { in: ids } },
      include: {
        priceOverrides: { where: { branchId: sale.branchId, isActive: true } },
        stock: { where: { branchId: sale.branchId } },
      },
    });
    if (products.length !== ids.length) throw new BadRequestException('A product in this cart is unavailable');
    let subtotal = 0;
    let tax = 0;
    for (const item of sale.items) {
      const product = products.find((entry) => entry.id === item.productId)!;
      const unitPrice = item.unitPrice ?? Number(product.priceOverrides[0]?.price ?? product.basePrice);
      const line = unitPrice * item.quantity - (item.discount ?? 0);
      if (line < 0) throw new BadRequestException('Item discount exceeds its price');
      if (product.trackInventory && Number(product.stock[0]?.quantity ?? 0) < item.quantity) {
        throw new ConflictException(`${product.name} is out of stock`);
      }
      subtotal += line;
      tax += line * Number(product.taxRate) / 100;
    }
    const total = Math.round((subtotal + tax - (sale.discountAmount ?? 0)) * 100) / 100;
    if (total < 3 || total > 9_999_999) throw new BadRequestException('Sale amount is outside supported Paystack limits');
    return total;
  }

  private normalizePhone(value: string) {
    const digits = value.replace(/\D/g, '');
    if (digits.startsWith('0')) return `+254${digits.slice(1)}`;
    if (digits.startsWith('254')) return `+${digits}`;
    return `+254${digits}`;
  }

  private presentCharge(charge: {
    reference: string; status: string; providerStatus: string | null;
    amount: Prisma.Decimal; saleId: string | null; receiptNumber: string | null;
    purpose?: string; receivableType?: string | null; receivableId?: string | null;
    receivablePaymentId?: string | null;
  }) {
    return {
      reference: charge.reference,
      status: charge.status,
      providerStatus: charge.providerStatus,
      amount: Number(charge.amount),
      purpose: charge.purpose ?? 'SALE',
      receivableType: charge.receivableType ?? null,
      receivableId: charge.receivableId ?? null,
      receivablePaymentId: charge.receivablePaymentId ?? null,
      saleId: charge.saleId,
      receiptNumber: charge.receiptNumber,
    };
  }

  private presentStart(charge: {
    reference: string; status: string; amount: Prisma.Decimal;
    purpose?: string; receivableType?: string | null; receivableId?: string | null;
  }) {
    return {
      reference: charge.reference,
      status: charge.status,
      amount: Number(charge.amount),
      purpose: charge.purpose ?? 'SALE',
      receivableType: charge.receivableType ?? null,
      receivableId: charge.receivableId ?? null,
      message: 'This payment request already exists. Check its status before retrying.',
    };
  }
}
