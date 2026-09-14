import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../common/prisma/prisma.service';
import { ReportingService } from '../reporting/reporting.service';
import { AiService } from './ai.service';
import { AiSubscriptionStatus } from '@prisma/client';

/**
 * Runs once a day, before typical store open, and pre-generates a short
 * business brief for every branch with an active AI subscription — so the
 * dashboard's "AI Brief" card can show a real insight instantly instead of
 * making the owner wait on a live model call every time they open the app.
 * Modeled directly on AiBillingRenewalTask's cron pattern.
 */
@Injectable()
export class AiDailyBriefTask {
  private readonly logger = new Logger(AiDailyBriefTask.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly reportingService: ReportingService,
    private readonly aiService: AiService,
  ) {}

  @Cron(CronExpression.EVERY_DAY_AT_6AM)
  async generateDailyBriefs() {
    this.logger.log('Generating daily AI briefs for active AI subscriptions');

    const activeSubscriptions = await this.prisma.aiSubscription.findMany({
      where: { status: AiSubscriptionStatus.ACTIVE },
      include: { branch: { include: { tenant: true } } },
    });

    let succeeded = 0;
    let failed = 0;

    for (const subscription of activeSubscriptions) {
      try {
        const yesterday = new Date();
        yesterday.setUTCDate(yesterday.getUTCDate() - 1);
        const yesterdayStr = yesterday.toISOString().split('T')[0];

        await this.generateBriefForBranch(
          subscription.branchId,
          subscription.branch.tenantId,
          subscription.branch.tenant.name,
          yesterdayStr,
        );
        succeeded++;
      } catch (error: any) {
        failed++;
        this.logger.error(
          `Daily brief failed for branch ${subscription.branchId}: ${error?.message || error}`,
        );
      }
    }

    this.logger.log(`Daily briefs done: ${succeeded} succeeded, ${failed} failed`);
  }

  /**
   * Generates (and caches into DailyBrief) a short business brief for a
   * specific branch and calendar date. Shared by the nightly cron (always
   * called with yesterday's date) and the dashboard's on-demand
   * "brief for this date" read for a date the cron never covered.
   */
  async generateBriefForBranch(
    branchId: string,
    tenantId: string,
    companyName: string,
    dateStr: string,
  ) {
    const summary = await this.reportingService.getDashboardSummary(tenantId, {
      startDate: dateStr,
      endDate: dateStr,
      branchId,
    });

    const isToday = dateStr === new Date().toISOString().split('T')[0];
    const dateLabel = new Date(`${dateStr}T00:00:00.000Z`).toLocaleDateString('en-KE', {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
    });

    const result = await this.aiService.chat({
      user_question:
        `Give me a short 2-3 sentence brief on ${isToday ? "today's" : `${dateLabel}'s`} business performance and one concrete suggestion. ` +
        'This will be shown in a narrow mobile card, so if you need to list specific items, use a short ' +
        'bullet list (max 3 items, one line each) instead of a markdown table.',
      context: 'general',
      ai_task: 'analyze_and_recommend',
      response_style: 'concise',
      includeData: true,
      business_context: {
        business_type: 'retail',
        company: companyName,
        branch: branchId,
        time_range: dateStr,
      },
      data_context: {
        total_sales: summary.sales.totalRevenue,
        transactions: summary.sales.totalSales,
        average_ticket: summary.sales.averageTicket,
        top_products: summary.topProducts.map((product) => ({
          name: product.productName,
          sku: product.sku,
          category: product.categoryName,
          quantity_sold: product.quantitySold,
          revenue: product.revenue,
        })),
        low_stock_count: summary.inventory?.lowStockItems ?? 0,
        out_of_stock_count: summary.inventory?.outOfStockItems ?? 0,
      },
    });

    // tool_access is never set on this request, so the agent tool-calling
    // path never engages and the result is always a plain reply.
    if (result.kind !== 'reply') {
      this.logger.warn(`Brief for branch ${branchId} (${dateStr}) got unexpected result kind: ${result.kind}`);
      return null;
    }

    const date = new Date(`${dateStr}T00:00:00.000Z`);

    return this.prisma.dailyBrief.upsert({
      where: { branchId_date: { branchId, date } },
      create: { branchId, date, content: result.reply, model: result.model },
      update: { content: result.reply, model: result.model },
    });
  }
}
