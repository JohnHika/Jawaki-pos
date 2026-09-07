import { Module } from "@nestjs/common";
import { CardBillingController } from "./card-billing.controller";
import { PesapalRecurringService } from "./pesapal-recurring.service";
import { BillingModule } from "./billing.module";
import { PesapalPaymentService } from "../payments/pesapal-payment.service";

/**
 * Pesapal card auto-renew (recurring subscriptions) for tenant billing.
 *
 * RecurringBillingService + SubscriptionRenewalSettler are NOT declared
 * here: BillingModule is their single owner and is imported below, so the
 * renewal cron service (and the cardBilling hook registered onto it at
 * module init) is instantiated exactly once per application.
 */
@Module({
  imports: [BillingModule],
  controllers: [CardBillingController],
  providers: [PesapalPaymentService, PesapalRecurringService],
  exports: [PesapalRecurringService],
})
export class CardBillingModule {}