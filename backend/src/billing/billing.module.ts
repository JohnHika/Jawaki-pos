import { Module } from '@nestjs/common';
import { BillingController } from './billing.controller';
import { BillingCron } from './billing.cron';
import { RecurringBillingService } from './recurring-billing.service';
import { SubscriptionRenewalSettler } from './subscription-renewal-settler.service';
import { SubscriptionGuard } from './subscription.guard';
import { PaymentsModule } from '../payments/payments.module';
import { SubscriptionModule } from '../subscription/subscription.module';

/**
 * Jawaki recurring subscription billing (settings, manual claims, cron,
 * entitlements, restricted-mode guard).
 *
 * This module is the SINGLE owner of RecurringBillingService,
 * SubscriptionRenewalSettler and BillingCron. CardBillingModule (Pesapal
 * card auto-renew) imports this module instead of declaring its own
 * RecurringBillingService provider — the service holds the cron-driven
 * renewal loop AND the cardBilling hook that PesapalRecurringService
 * registers at module init, so it must never be instantiated twice (two
 * instances would also break DI: the Jenga dependency lives in
 * PaymentsModule, which only this module imports).
 *
 * Dependency notes:
 *  - PaymentsModule is imported for JengaPaymentService (renewal STK push);
 *    it exports that provider.
 *  - SubscriptionRenewalSettler is Prisma-only, so JengaPaymentService can
 *    settle completed AXONSUB-* payments through it without a
 *    RecurringBillingService <-> JengaPaymentService circular dependency.
 *  - SubscriptionGuard is exported but ALSO safe to provide locally in
 *    feature modules (sales/expenses/suppliers do this) because it is
 *    stateless (Reflector + PrismaService) — local provision avoids dragging
 *    the Jenga-backed PaymentsModule into their DI graphs.
 */
@Module({
  imports: [PaymentsModule, SubscriptionModule],
  controllers: [BillingController],
  providers: [
    RecurringBillingService,
    SubscriptionRenewalSettler,
    BillingCron,
    SubscriptionGuard,
  ],
  exports: [
    RecurringBillingService,
    SubscriptionRenewalSettler,
    SubscriptionGuard,
  ],
})
export class BillingModule {}