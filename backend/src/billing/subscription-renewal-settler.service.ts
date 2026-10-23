import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';

/**
 * Settles a completed subscription renewal payment into its invoice and
 * activates the tenant's new period.
 *
 * This lives in its own provider (Prisma-only, no payment-gateway
 * dependency) so that BOTH RecurringBillingService and JengaPaymentService
 * can call it without creating a RecurringBillingService <-> JengaPaymentService
 * circular dependency: Jenga detects a completed AXONSUB-* charge inside its
 * authenticated status query and settles here directly, while the billing
 * service keeps its public settleRenewalPayment() entry point delegating to
 * the same logic.
 */
@Injectable()
export class SubscriptionRenewalSettler {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Marks the invoice whose auto-charge STK push used `checkoutRequestId`
   * as PAID and activates the tenant's new period, atomically in one
   * transaction. Idempotent: an already-PAID invoice returns null and the
   * caller's status query remains unaffected.
   */
  async settleByCheckoutId(checkoutRequestId: string) {
    const invoice = await this.prisma.subscriptionInvoice.findFirst({
      where: { mpesaCheckoutId: checkoutRequestId },
    });
    if (!invoice || invoice.status === 'PAID') return null;

    // The Jenga service already checks its authenticated paid amount against
    // the M-Pesa transaction. Bind that verified transaction back to the
    // expected invoice as a second guard against stale or mismatched IDs.
    const transaction = await this.prisma.mpesaTransaction.findUnique({
      where: { checkoutRequestId },
      select: { status: true, amount: true, accountReference: true },
    });
    const expectedReferencePrefix = `AXONSUB-${invoice.tenantId.slice(0, 8)}-`;
    if (
      !transaction ||
      transaction.status !== 'completed' ||
      invoice.currency !== 'KES' ||
      !new Prisma.Decimal(transaction.amount).equals(invoice.amount) ||
      !invoice.reference ||
      transaction.accountReference !== invoice.reference ||
      !invoice.reference.startsWith(expectedReferencePrefix)
    ) {
      return null;
    }

    const periodStart = new Date();
    const periodEnd = this.addMonth(periodStart);

    return this.prisma.$transaction(async (tx) => {
      const claimed = await tx.subscriptionInvoice.updateMany({
        where: {
          id: invoice.id,
          status: { in: ['PENDING', 'PENDING_CONFIRMATION'] },
          mpesaCheckoutId: checkoutRequestId,
          amount: invoice.amount,
          currency: 'KES',
        },
        data: {
          status: 'PAID',
          paidAt: new Date(),
          periodStart,
          periodEnd,
          reference: checkoutRequestId,
        },
      });
      if (claimed.count !== 1) return null;

      const paid = await tx.subscriptionInvoice.findUnique({
        where: { id: invoice.id },
      });
      await tx.tenant.update({
        where: { id: invoice.tenantId },
        data: {
          subscriptionStatus: 'ACTIVE',
          currentPeriodStart: periodStart,
          currentPeriodEnd: periodEnd,
          subscriptionProvider: 'JENGA_STK',
          subscriptionReference: checkoutRequestId,
        },
      });
      return paid;
    });
  }

  private addMonth(d: Date) {
    const next = new Date(d);
    next.setMonth(next.getMonth() + 1);
    return next;
  }
}
