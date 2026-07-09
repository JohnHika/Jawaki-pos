import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../common/prisma/prisma.service';
import { ReportingService } from '../reporting/reporting.service';
import { AiService } from './ai.service';
import { AiSubscriptionStatus } from '@prisma/client';
import { ReportPeriod } from '../reporting/dto/reporting.dto';

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
        await this.generateBriefForBranch(
          subscription.branchId,
          subscription.branch.tenantId,
          subscription.branch.tenant.name,
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

  private async generateBriefForBranch(
    branchId: string,
    tenantId: string,
    companyName: string,
  ) {
    const summary = await this.reportingService.getDashboardSummary(tenantId, {
      period: ReportPeriod.YESTERDAY,
      branchId,
    });

    const { reply, model } = await this.aiService.chat({
      user_question:
        "Give me a short 2-3 sentence brief on yesterday's business performance and one concrete suggestion for today.",
      context: 'general',
      ai_task: 'analyze_and_recommend',
      response_style: 'concise',
      includeData: true,
      business_context: {
        business_type: 'retail',
        company: companyName,
        branch: branchId,
        time_range: 'yesterday',
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

    const today = new Date();
    const date = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));

    await this.prisma.dailyBrief.upsert({
      where: { branchId_date: { branchId, date } },
      create: { branchId, date, content: reply, model },
      update: { content: reply, model },
    });
  }
}
