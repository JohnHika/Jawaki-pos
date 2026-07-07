import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { AiBillingService } from './ai-billing.service';

/**
 * Runs once a day and auto-charges every subscription that's expiring
 * soon and has a saved Paystack card on file — the "auto subscribe"
 * behavior: customers don't need to pay again manually each month.
 */
@Injectable()
export class AiBillingRenewalTask {
  private readonly logger = new Logger(AiBillingRenewalTask.name);

  constructor(private readonly billingService: AiBillingService) {}

  @Cron(CronExpression.EVERY_DAY_AT_2AM)
  async handleRenewals() {
    this.logger.log('Running AI subscription renewal check');
    try {
      await this.billingService.renewExpiringSubscriptions();
    } catch (error: any) {
      this.logger.error(`Renewal check failed: ${error?.message || error}`);
    }
  }
}
