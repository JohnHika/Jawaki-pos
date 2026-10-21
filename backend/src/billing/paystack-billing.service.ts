import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { PaystackService } from '../ai-billing/paystack.service';
import { RecurringBillingService } from './recurring-billing.service';
import { PLAN_PRICING } from '../subscription/subscription.service';

const SUBSCRIPTION_INVOICE_PRODUCT = 'axon_subscription_invoice';

@Injectable()
export class PaystackBillingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly recurringBilling: RecurringBillingService,
    private readonly config: ConfigService,
  ) {}

  /** Initialize or resume the current monthly subscription invoice checkout. */
  async initializeInvoicePayment(tenantId: string, userId: string) {
    const user = await this.prisma.user.findFirst({
      where: { id: userId, tenantId, isActive: true },
      select: { email: true },
    });
    if (!user?.email) throw new NotFoundException('A billing email is required');

    const invoice = await this.recurringBilling.getInvoiceForPayment(tenantId);
    if (!invoice) {
      throw new BadRequestException('There is no monthly payment due yet');
    }
    if (invoice.status === 'PAID') {
      return {
        status: 'PAID',
        invoiceId: invoice.id,
        reference: invoice.reference,
        amountKes: Number(invoice.amount),
        currency: invoice.currency,
      };
    }
    if (invoice.status === 'PENDING_CONFIRMATION') {
      throw new ConflictException(
        'A manual M-Pesa payment is awaiting review for this invoice',
      );
    }
    if (invoice.provider === 'JENGA_STK' && invoice.mpesaCheckoutId) {
      const stkPayment = await this.prisma.mpesaTransaction.findUnique({
        where: { checkoutRequestId: invoice.mpesaCheckoutId },
        select: { status: true },
      });
      const terminalFailureStatuses = ['failed', 'cancelled', 'canceled'];
      if (
        !stkPayment ||
        !terminalFailureStatuses.includes(stkPayment.status.toLowerCase())
      ) {
        throw new ConflictException(
          'An M-Pesa renewal request is already in progress. Check its status before starting another payment.',
        );
      }
    }
    if (invoice.provider === 'PAYSTACK' && invoice.authorizationUrl && invoice.reference) {
      return {
        status: invoice.status,
        invoiceId: invoice.id,
        reference: invoice.reference,
        authorizationUrl: invoice.authorizationUrl,
        amountKes: Number(invoice.amount),
        currency: invoice.currency,
      };
    }
    if (invoice.provider === 'PAYSTACK_INITIALIZING') {
      throw new ConflictException('Paystack checkout is being prepared. Please try again shortly.');
    }
    if (invoice.provider === 'PAYSTACK' && !invoice.authorizationUrl) {
      throw new ConflictException('Paystack checkout is being prepared. Please try again shortly.');
    }

    const amountKes = Number(invoice.amount);
    if (!Number.isFinite(amountKes) || amountKes <= 0) {
      throw new BadRequestException('Invoice amount is invalid');
    }
    const reference = `AXON-SUB-${tenantId.slice(0, 8).toUpperCase()}-${randomUUID()}`;
    const reservation = await this.prisma.subscriptionInvoice.updateMany({
      where: {
        id: invoice.id,
        status: 'PENDING',
        provider: invoice.provider,
        reference: invoice.reference,
      },
      data: {
        provider: 'PAYSTACK_INITIALIZING',
        reference,
        authorizationUrl: null,
      },
    });
    if (reservation.count !== 1) {
      throw new ConflictException('This invoice payment is already being started. Refresh and try again.');
    }

    try {
      const checkout = await this.paystack.initializeTransaction({
        email: user.email,
        amountKes,
        reference,
        callbackUrl: this.callbackUrl(),
        useEnabledChannels: true,
        metadata: {
          product: SUBSCRIPTION_INVOICE_PRODUCT,
          tenantId,
          invoiceId: invoice.id,
          plan: invoice.plan,
          renewalSequence: invoice.renewalSequence,
        },
      });
      if (checkout.reference !== reference) {
        throw new BadRequestException('Paystack returned an unexpected transaction reference');
      }
      const updated = await this.prisma.subscriptionInvoice.update({
        where: { id: invoice.id },
        data: {
          provider: 'PAYSTACK',
          authorizationUrl: checkout.authorizationUrl,
        },
      });

      return {
        status: updated.status,
        invoiceId: updated.id,
        reference: updated.reference,
        authorizationUrl: updated.authorizationUrl,
        amountKes: Number(updated.amount),
        currency: updated.currency,
      };
    } catch (error) {
      await this.prisma.subscriptionInvoice.updateMany({
        where: {
          id: invoice.id,
          provider: 'PAYSTACK_INITIALIZING',
          reference,
        },
        data: { provider: null, reference: null, authorizationUrl: null },
      });
      throw error;
    }
  }

  /** Verify through Paystack, then settle the invoice and extend the period. */
  async verifyInvoicePayment(tenantId: string, reference: string) {
    const invoice = await this.prisma.subscriptionInvoice.findFirst({
      where: { tenantId, reference, provider: 'PAYSTACK' },
    });
    if (!invoice) {
      throw new BadRequestException('Paystack reference does not match an invoice for this company');
    }
    return this.verifyAndSettle(invoice.id, reference, tenantId);
  }

  /** Unified dashboard webhook dispatches monthly invoice events here. */
  async handleWebhook(event: string, data: any) {
    if (event !== 'charge.success') return { received: true, handled: false };
    const metadata = this.readMetadata(data?.metadata);
    if (metadata?.product !== SUBSCRIPTION_INVOICE_PRODUCT) {
      return { received: true, handled: false };
    }
    const reference = String(data?.reference ?? '').trim();
    const tenantId = String(metadata.tenantId ?? '').trim();
    const invoiceId = String(metadata.invoiceId ?? '').trim();
    if (!reference || !tenantId || !invoiceId) {
      throw new BadRequestException('Paystack subscription notification is missing its invoice reference');
    }
    const invoice = await this.prisma.subscriptionInvoice.findFirst({
      where: { id: invoiceId, tenantId, reference, provider: 'PAYSTACK' },
    });
    if (!invoice) throw new NotFoundException('Paystack invoice was not found');
    return this.verifyAndSettle(invoice.id, reference, tenantId);
  }

  private async verifyAndSettle(invoiceId: string, reference: string, tenantId: string) {
    const invoice = await this.prisma.subscriptionInvoice.findFirst({
      where: { id: invoiceId, tenantId, reference, provider: 'PAYSTACK' },
    });
    if (!invoice) throw new NotFoundException('Paystack invoice was not found');
    if (invoice.status === 'PAID') {
      return { status: 'PAID', invoiceId: invoice.id, reference, paidAt: invoice.paidAt };
    }

    const charge = await this.paystack.verifyTransaction(reference);
    if (charge.reference !== reference) {
      throw new BadRequestException('Paystack returned a different transaction reference');
    }
    if (charge.status !== 'success') {
      if (['failed', 'abandoned'].includes(charge.status.toLowerCase())) {
        await this.prisma.subscriptionInvoice.updateMany({
          where: { id: invoice.id, status: { not: 'PAID' }, reference },
          data: { provider: 'PAYSTACK_FAILED', authorizationUrl: null },
        });
      }
      return { status: charge.status.toUpperCase(), invoiceId: invoice.id, reference };
    }

    const metadata = this.readMetadata(charge.metadata);
    const expectedAmount = Math.round(Number(invoice.amount) * 100);
    if (
      Number(charge.amount) !== expectedAmount ||
      charge.currency?.toUpperCase() !== 'KES' ||
      !metadata ||
      metadata.product !== SUBSCRIPTION_INVOICE_PRODUCT ||
      metadata.tenantId !== tenantId ||
      metadata.invoiceId !== invoice.id
    ) {
      throw new BadRequestException('Paystack payment details do not match this subscription invoice');
    }

    const paidAt = charge.paid_at ? new Date(charge.paid_at) : new Date();
    const periodStart = invoice.periodStart ?? paidAt;
    const periodEnd = invoice.periodEnd ?? this.addMonth(periodStart);

    const result = await this.prisma.$transaction(async (tx) => {
      const claimed = await tx.subscriptionInvoice.updateMany({
        where: { id: invoice.id, tenantId, status: { not: 'PAID' }, reference },
        data: {
          status: 'PAID',
          paidAt,
          provider: 'PAYSTACK',
          periodStart,
          periodEnd,
          authorizationUrl: null,
        },
      });
      if (claimed.count === 0) {
        return tx.subscriptionInvoice.findUnique({ where: { id: invoice.id } });
      }
      await tx.tenant.update({
        where: { id: tenantId },
        data: {
          subscriptionStatus: 'ACTIVE',
          currentPeriodStart: periodStart,
          currentPeriodEnd: periodEnd,
          subscriptionProvider: 'PAYSTACK',
          subscriptionReference: reference,
        },
      });
      return tx.subscriptionInvoice.findUnique({ where: { id: invoice.id } });
    });

    return {
      status: result?.status ?? 'PAID',
      invoiceId: invoice.id,
      reference,
      paidAt,
      plan: PLAN_PRICING[invoice.plan]?.name ?? invoice.plan,
    };
  }

  private callbackUrl(): string | undefined {
    const explicit = this.config.get<string>('PAYSTACK_BILLING_CALLBACK_URL')?.trim();
    if (explicit) return explicit;
    const publicBase = [
      this.config.get<string>('PUBLIC_API_URL'),
      this.config.get<string>('API_PUBLIC_URL'),
      this.config.get<string>('RENDER_EXTERNAL_URL'),
    ].find((value) => value?.trim());
    if (!publicBase) return undefined;
    const normalized = publicBase.trim().replace(/\/+$/, '');
    const apiPrefix = normalized.endsWith('/api/v1')
      ? normalized
      : `${normalized}/api/v1`;
    return `${apiPrefix}/billing/paystack/callback`;
  }

  private readMetadata(value: unknown): Record<string, any> | null {
    if (typeof value === 'string') {
      try {
        const parsed = JSON.parse(value);
        return parsed && typeof parsed === 'object' ? parsed : null;
      } catch {
        return null;
      }
    }
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, any>)
      : null;
  }

  private addMonth(date: Date) {
    const next = new Date(date);
    next.setMonth(next.getMonth() + 1);
    return next;
  }
}
