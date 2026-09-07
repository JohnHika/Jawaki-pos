import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { RecurringBillingService } from './recurring-billing.service';

/**
 * Daily subscription renewal tick.
 *
 * 07:00 Africa/Nairobi = 04:00 UTC (EAT is UTC+3, no DST): the client sees
 * the renewal on their phone first thing in the morning, and the STK push
 * lands while they are at the shop. Cron expressions in @nestjs/schedule
 * run in the process timezone; since the server runs in UTC the expression
 * is written in UTC minutes: '0 4 * * *'.
 */
@Injectable()
export class BillingCron {
  private readonly logger = new Logger(BillingCron.name);

  constructor(private readonly recurringBillingService: RecurringBillingService) {}

  @Cron('0 4 * * *')
  async handleRenewalCycle() {
    this.logger.log('Running daily subscription renewal cycle (07:00 EAT)');
    try {
      const summary = await this.recurringBillingService.runRenewalCycle();
      this.logger.log(
        `Renewal cycle complete: ${summary.charged.length} charged, ` +
          `${summary.renewed.length} renewed, ${summary.suspended.length} suspended, ` +
          `${summary.skipped.length} skipped`,
      );
    } catch (error: any) {
      this.logger.error(
        `Renewal cycle failed: ${error?.message ?? error}`,
        error?.stack,
      );
    }
  }
}