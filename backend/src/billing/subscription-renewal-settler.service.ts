import { Injectable } from '@nestjs/common';
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

    const periodStart = new Date();
    const periodEnd = this.addMonth(periodStart);

    return this.prisma.$transaction(async (tx) => {
      const paid = await tx.subscriptionInvoice.update({
        where: { id: invoice.id },
        data: {
          status: 'PAID',
          paidAt: new Date(),
          periodStart,
          periodEnd,
          reference: checkoutRequestId,
        },
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