import {
  Controller,
  Get,
  Headers,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import { timingSafeEqual } from 'crypto';
import { PrismaService } from './common/prisma/prisma.service';
import { BillingCron } from './billing/billing.cron';
import { AiBillingRenewalTask } from './ai-billing/ai-billing-renewal.task';
import { AiDailyBriefTask } from './ai/ai-daily-brief.task';
import { AiProactiveNotificationsTask } from './ai/ai-proactive-notifications.task';

type CronCadence = 'daily' | 'half-hourly';

/**
 * Vercel's scheduler makes authenticated HTTP requests; unlike a traditional
 * server, a function instance cannot be relied on to stay alive for timers.
 * The execution ledger also makes duplicate deliveries for the same UTC slot
 * safe, which matters for billing jobs.
 */
@Controller({ path: 'api/cron', version: VERSION_NEUTRAL })
export class VercelCronController {
  private readonly logger = new Logger(VercelCronController.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly billingCron: BillingCron,
    private readonly aiBillingRenewalTask: AiBillingRenewalTask,
    private readonly aiDailyBriefTask: AiDailyBriefTask,
    private readonly aiProactiveNotificationsTask: AiProactiveNotificationsTask,
  ) {}

  @Get('billing-renewals')
  billingRenewals(@Headers('authorization') authorization?: string) {
    return this.run('billing-renewals', 'daily', authorization, () =>
      this.billingCron.handleRenewalCycle(),
    );
  }

  @Get('ai-billing-renewals')
  aiBillingRenewals(@Headers('authorization') authorization?: string) {
    return this.run('ai-billing-renewals', 'daily', authorization, () =>
      this.aiBillingRenewalTask.handleRenewals(),
    );
  }

  @Get('low-stock-alerts')
  lowStockAlerts(@Headers('authorization') authorization?: string) {
    return this.run('low-stock-alerts', 'daily', authorization, () =>
      this.aiProactiveNotificationsTask.checkLowStock(),
    );
  }

  @Get('end-of-day-reminders')
  endOfDayReminders(@Headers('authorization') authorization?: string) {
    return this.run('end-of-day-reminders', 'half-hourly', authorization, () =>
      this.aiProactiveNotificationsTask.checkEndOfDayDue(),
    );
  }

  @Get('daily-briefs')
  dailyBriefs(@Headers('authorization') authorization?: string) {
    return this.run('daily-briefs', 'daily', authorization, () =>
      this.aiDailyBriefTask.generateDailyBriefs(),
    );
  }

  private async run(
    name: string,
    cadence: CronCadence,
    authorization: string | undefined,
    task: () => Promise<unknown>,
  ) {
    const secret = process.env.CRON_SECRET;
    const expected = secret ? Buffer.from(`Bearer ${secret}`) : Buffer.alloc(0);
    const supplied = Buffer.from(authorization ?? '');
    if (
      expected.length === 0 ||
      supplied.length !== expected.length ||
      !timingSafeEqual(supplied, expected)
    ) {
      throw new UnauthorizedException();
    }

    const runId = this.getRunId(name, cadence);
    const acquired = await this.prisma.$queryRaw<Array<{ id: string }>>`
      INSERT INTO "scheduled_task_runs"
        ("id", "status", "startedAt", "leaseExpiresAt")
      VALUES (${runId}, 'RUNNING', NOW(), NOW() + INTERVAL '15 minutes')
      ON CONFLICT ("id") DO UPDATE
        SET "status" = 'RUNNING',
            "startedAt" = NOW(),
            "leaseExpiresAt" = NOW() + INTERVAL '15 minutes',
            "completedAt" = NULL,
            "lastError" = NULL
        WHERE "scheduled_task_runs"."status" = 'RUNNING'
          AND "scheduled_task_runs"."leaseExpiresAt" < NOW()
      RETURNING "id"
    `;

    if (acquired.length === 0) {
      this.logger.log(`Skipping duplicate or active cron delivery: ${runId}`);
      return { ok: true, skipped: true };
    }

    try {
      await task();
      await this.prisma.scheduledTaskRun.update({
        where: { id: runId },
        data: { status: 'COMPLETED', completedAt: new Date() },
      });
      return { ok: true, skipped: false };
    } catch (error) {
      await this.prisma.scheduledTaskRun
        .update({
          where: { id: runId },
          data: {
            status: 'FAILED',
            lastError: String(error).slice(0, 2000),
          },
        })
        .catch((updateError) => {
          this.logger.error(`Could not record cron failure for ${runId}: ${updateError}`);
        });
      this.logger.error(`Cron task ${runId} failed`, error);
      throw new ServiceUnavailableException(`Scheduled task ${name} failed`);
    }
  }

  private getRunId(name: string, cadence: CronCadence): string {
    const slot = new Date();
    if (cadence === 'half-hourly') {
      slot.setUTCMinutes(slot.getUTCMinutes() < 30 ? 0 : 30, 0, 0);
    } else {
      slot.setUTCHours(0, 0, 0, 0);
    }
    return `${name}:${slot.toISOString()}`;
  }
}
