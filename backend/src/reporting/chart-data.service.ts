import { Injectable } from '@nestjs/common';
import { ReportingService } from './reporting.service';
import { ReportFilterDto, ReportPeriod } from './dto/reporting.dto';
import { ChartDataType, GenerateChartDto, GeneratedChart } from './dto/chart-data.dto';

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

const PERIOD_LABEL: Record<ReportPeriod, string> = {
  [ReportPeriod.TODAY]: 'Today',
  [ReportPeriod.YESTERDAY]: 'Yesterday',
  [ReportPeriod.THIS_WEEK]: 'This Week',
  [ReportPeriod.LAST_WEEK]: 'Last Week',
  [ReportPeriod.THIS_MONTH]: 'This Month',
  [ReportPeriod.LAST_MONTH]: 'Last Month',
  [ReportPeriod.THIS_QUARTER]: 'This Quarter',
  [ReportPeriod.THIS_YEAR]: 'This Year',
  [ReportPeriod.CUSTOM]: 'Custom Range',
};

/**
 * Shapes real DB report data into the generic chart shape mobile's fl_chart
 * widgets render — the chart-visualization counterpart to
 * ReportExportService (which produces downloadable files instead). Kept as
 * its own service since "give me chart data" and "give me a file" are
 * different concerns even though both start from the same ReportingService
 * data.
 */
@Injectable()
export class ChartDataService {
  constructor(private readonly reporting: ReportingService) {}

  async buildChart(tenantId: string, dto: GenerateChartDto): Promise<GeneratedChart> {
    const filter: ReportFilterDto = {
      period: dto.period ?? ReportPeriod.THIS_WEEK,
      branchId: dto.branchId,
    };
    const periodLabel = PERIOD_LABEL[filter.period ?? ReportPeriod.THIS_WEEK];

    switch (dto.chartType) {
      case ChartDataType.SALES_TREND: {
        const trend = await this.reporting.getSalesTrend(tenantId, filter);
        return {
          kind: 'line',
          title: 'Sales Trend',
          subtitle: periodLabel,
          valueLabel: 'KES',
          points: trend.map((t) => ({ label: t.period, value: t.revenue })),
        };
      }

      case ChartDataType.TOP_PRODUCTS: {
        const products = await this.reporting.getTopProducts(tenantId, filter, 10);
        return {
          kind: 'bar',
          title: 'Top Products',
          subtitle: periodLabel,
          valueLabel: 'KES',
          points: products.map((p) => ({ label: p.productName, value: p.revenue })),
        };
      }

      case ChartDataType.PAYMENT_BREAKDOWN: {
        const breakdown = await this.reporting.getPaymentMethodBreakdown(tenantId, filter);
        return {
          kind: 'bar',
          title: 'Payment Method Breakdown',
          subtitle: periodLabel,
          valueLabel: 'KES',
          points: breakdown.map((b) => ({ label: b.method, value: b.amount })),
        };
      }

      case ChartDataType.SALES_HEATMAP: {
        const heatmap = await this.reporting.getSalesHeatmap(tenantId, filter);
        return {
          kind: 'heatmap',
          title: 'Busiest Times',
          subtitle: `${periodLabel} — by day and hour`,
          valueLabel: 'sales',
          cells: heatmap.map((h) => ({
            dayOfWeek: h.dayOfWeek,
            hour: h.hour,
            value: h.salesCount,
          })),
        };
      }

      default:
        throw new Error(`Unknown chart type: ${dto.chartType}`);
    }
  }
}
