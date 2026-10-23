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
import { LegacyUserRole, PaymentMethod, PaymentStatus, Prisma } from '@prisma/client';
import { randomBytes } from 'crypto';
import { PaystackService } from '../ai-billing/paystack.service';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateSaleDto } from '../sales/dto/sales.dto';
import { SalesService } from '../sales/sales.service';
import { ConfigureMerchantPayoutDto, StartMerchantMpesaDto } from './dto/merchant-payments.dto';
import { LegalPolicyService } from '../legal/legal-policy.service';

type Actor = { sub: string; tenantId: string };

@Injectable()
export class MerchantPaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly sales: SalesService,
    @Optional() private readonly legalPolicies?: LegalPolicyService,
  ) {}

  async account(actor: Actor) {
    const row = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId },
    });
    if (!row) return { status: 'NOT_CONFIGURED', provider: 'PAYSTACK', currency: 'KES' };
    return {
      status: row.status,
      provider: row.provider,
      currency: row.currency,
      bankName: row.bankName,
      accountName: row.accountName,
      accountLast4: row.accountLast4,
      updatedAt: row.updatedAt,
    };
  }

  async banks() {
    return this.paystack.listKenyanBanks();
  }

  async configureAccount(actor: Actor, dto: ConfigureMerchantPayoutDto) {
    await this.assertOwner(actor);
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

    // The full account number is sent to Paystack and never persisted here.
    const subaccount = await this.paystack.createMerchantSubaccount({
      businessName: tenant.name,
      bankCode: bank.code,
      accountNumber: dto.accountNumber,
      contactEmail: owner.email,
    });
    if (!subaccount.subaccount_code || subaccount.active === false ||
        (subaccount.currency && subaccount.currency !== 'KES')) {
      throw new ServiceUnavailableException(
        'Paystack did not confirm a usable KES payout account. No payment route was changed.',
      );
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.merchantPaymentAccount.upsert({
        where: { tenantId: actor.tenantId },
        create: {
          tenantId: actor.tenantId,
          subaccountCode: subaccount.subaccount_code,
          bankCode: bank.code,
          bankName: bank.name,
          accountName: subaccount.account_name?.trim() || null,
          accountLast4: dto.accountNumber.slice(-4),
          currency: 'KES',
          status: 'ACTIVE',
        },
        update: {
          subaccountCode: subaccount.subaccount_code,
          bankCode: bank.code,
          bankName: bank.name,
          accountName: subaccount.account_name?.trim() || null,
          accountLast4: dto.accountNumber.slice(-4),
          currency: 'KES',
          status: 'ACTIVE',
        },
      });
      const onboarding = await tx.tenantOnboarding.findUnique({
        where: { tenantId: actor.tenantId }, select: { id: true },
      });
      if (onboarding) {
        await tx.tenantOnboardingStep.updateMany({
          where: { onboardingId: onboarding.id, key: 'activate_payment' },
          data: { status: 'COMPLETED', completedAt: new Date(), deferredAt: null },
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
    if (!account || account.status !== 'ACTIVE') {
      throw new ConflictException('Set up your business payout account before accepting M-Pesa sales');
    }
    if (input.sale.paymentMethod !== PaymentMethod.MPESA || input.sale.tenders?.length) {
      throw new BadRequestException('This checkout accepts one M-Pesa payment for one sale');
    }
    const amount = await this.quoteSale(actor.tenantId, input.sale);
    if (Math.abs((input.sale.paidAmount ?? amount) - amount) > 0.01) {
      throw new BadRequestException('The sale total changed. Refresh the cart before requesting payment');
    }
    const phone = this.normalizePhone(input.phoneNumber);
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
          subaccountCode: account.subaccountCode,
          amount: new Prisma.Decimal(amount),
          phone,
          customerEmail: input.customerEmail.trim().toLowerCase(),
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
        email: input.customerEmail.trim().toLowerCase(),
        amountKes: amount,
        phone,
        reference,
        subaccountCode: account.subaccountCode,
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
      const sale = await this.sales.createSale(
        charge.cashierId,
        charge.tenantId,
        charge.salePayload as unknown as CreateSaleDto,
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

  private async assertOwner(actor: Actor) {
    const onboarding = await this.prisma.tenantOnboarding.findUnique({
      where: { tenantId: actor.tenantId }, select: { ownerUserId: true },
    });
    if (onboarding?.ownerUserId === actor.sub) return;
    // Older workspaces predate TenantOnboarding; their original admin can
    // still set a payout account without a platform-admin intervention.
    if (!onboarding) {
      const user = await this.prisma.user.findFirst({
        where: { id: actor.sub, tenantId: actor.tenantId }, select: { role: true },
      });
      if (user?.role === LegacyUserRole.ADMIN) return;
    }
    throw new ForbiddenException('Only the business owner can change payout details');
  }

  private normalizePhone(value: string) {
    const digits = value.replace(/\D/g, '');
    return digits.startsWith('0') ? `254${digits.slice(1)}` : digits;
  }

  private presentCharge(charge: {
    reference: string; status: string; providerStatus: string | null;
    amount: Prisma.Decimal; saleId: string | null; receiptNumber: string | null;
  }) {
    return {
      reference: charge.reference,
      status: charge.status,
      providerStatus: charge.providerStatus,
      amount: Number(charge.amount),
      saleId: charge.saleId,
      receiptNumber: charge.receiptNumber,
    };
  }

  private presentStart(charge: {
    reference: string; status: string; amount: Prisma.Decimal;
  }) {
    return {
      reference: charge.reference,
      status: charge.status,
      amount: Number(charge.amount),
      message: 'This payment request already exists. Check its status before retrying.',
    };
  }
}
