import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { LegacyUserRole } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { InventoryService } from '../inventory/inventory.service';
import { NotificationsService } from '../notifications/notifications.service';
import { DailyCloseService } from '../sales/daily-close.service';
import { normalizeOperatingHours, computeOpenStatus } from '../common/operating-hours';

/**
 * Proactive, no-question-asked AI notifications — the app tells the shop
 * something important instead of waiting to be asked. Two checks, both
 * iterating every active branch:
 *
 *  - Morning low-stock alert (fixed time, once a day): mirrors
 *    AiDailyBriefTask's pattern but pushes instead of just pre-generating
 *    dashboard-card data.
 *  - End-of-day cash-up reminder: NOT a fixed time — every branch sets its
 *    own operating hours (see operating-hours.ts), so this runs every 30
 *    minutes and only fires for branches that are *currently* past their
 *    own configured close time and haven't closed today yet — the same
 *    condition the mobile app's in-app EndOfDayPrompt already checks,
 *    just also reachable when the app isn't open.
 *
 * Notifications go to the branch's ADMIN/MANAGER users (role-based, not a
 * full permission-resolution query — this is a reminder, not an
 * authorization boundary, so approximating "who's likely allowed to close
 * the day" by role is an acceptable simplification here).
 */
@Injectable()
export class AiProactiveNotificationsTask {
  private readonly logger = new Logger(AiProactiveNotificationsTask.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly inventory: InventoryService,
    private readonly notifications: NotificationsService,
    private readonly dailyClose: DailyCloseService,
  ) {}

  @Cron(CronExpression.EVERY_DAY_AT_7AM)
  async checkLowStock() {
    this.logger.log('Checking low stock for proactive notifications');
    const branches = await this.prisma.branch.findMany({
      where: { isActive: true },
      select: { id: true, tenantId: true },
    });

    let sent = 0;
    let failed = 0;

    for (const branch of branches) {
      try {
        const alerts = await this.inventory.getLowStockAlerts(branch.tenantId, branch.id);
        if (alerts.length === 0) continue;

        const worst = alerts[0];
        const body =
          alerts.length === 1
            ? `${worst.productName} is low on stock (${worst.currentStock} left).`
            : `${alerts.length} items are low on stock, worst: ${worst.productName} (${worst.currentStock} left).`;

        await this.notifyBranchManagers(branch.id, branch.tenantId, {
          title: 'Low Stock Alert',
          body,
          data: { type: 'low_stock_alert', branchId: branch.id },
        });
        sent++;
      } catch (error: any) {
        failed++;
        this.logger.error(`Low-stock check failed for branch ${branch.id}: ${error?.message || error}`);
      }
    }

    this.logger.log(`Low-stock notifications: ${sent} sent, ${failed} failed`);
  }

  @Cron(CronExpression.EVERY_30_MINUTES)
  async checkEndOfDayDue() {
    const branches = await this.prisma.branch.findMany({
      where: { isActive: true },
      select: { id: true, tenantId: true, timezone: true, settings: true },
    });

    let sent = 0;
    let failed = 0;

    for (const branch of branches) {
      try {
        const rawHours = (branch.settings as Record<string, any>)?.operatingHours;
        const hours = normalizeOperatingHours(rawHours);
        if (!hours) continue; // no configured hours -> nothing to compare against

        const status = computeOpenStatus(hours, branch.timezone || 'Africa/Nairobi');
        // Fires only in the window just after close: still "today" and not
        // about to reopen for many hours (rules out a branch that's simply
        // closed all day, or one on a mid-day break, which also reports
        // is_open_now: false).
        if (!status || status.is_open_now || status.on_break) continue;
        const justClosed =
          status.minutes_until_open === null || status.minutes_until_open > 60;
        if (!justClosed) continue;

        const alreadyClosed = await this.dailyClose.getClose(branch.tenantId, branch.id);
        if (alreadyClosed) continue;

        await this.notifyBranchManagers(branch.id, branch.tenantId, {
          title: 'Close the day?',
          body: "You're past closing time and today's sales haven't been closed yet.",
          data: { type: 'eod_reminder', branchId: branch.id },
        });
        sent++;
      } catch (error: any) {
        failed++;
        this.logger.error(`EOD reminder check failed for branch ${branch.id}: ${error?.message || error}`);
      }
    }

    if (sent > 0 || failed > 0) {
      this.logger.log(`EOD reminders: ${sent} sent, ${failed} failed`);
    }
  }

  private async notifyBranchManagers(
    branchId: string,
    tenantId: string,
    payload: { title: string; body: string; data: Record<string, string> },
  ) {
    const managers = await this.prisma.userBranch.findMany({
      where: {
        branchId,
        user: {
          tenantId,
          isActive: true,
          role: { in: [LegacyUserRole.ADMIN, LegacyUserRole.MANAGER] },
        },
      },
      select: { userId: true },
    });

    for (const { userId } of managers) {
      // NotificationsService.sendToUser already fails soft internally.
      await this.notifications.sendToUser(userId, payload);
    }
  }
}
