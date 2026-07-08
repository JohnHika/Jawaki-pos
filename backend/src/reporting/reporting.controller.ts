import {
  Controller,
  Get,
  Query,
  UseGuards,
  Param,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiResponse, ApiQuery } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { ReportingService } from './reporting.service';
import {
  ReportFilterDto,
  SalesSummaryDto,
  SalesTrendDto,
  TopProductDto,
  CategorySalesDto,
  CashierPerformanceDto,
  PaymentMethodBreakdownDto,
  BranchComparisonDto,
  InventoryReportDto,
  StockMovementSummaryDto,
  DashboardSummaryDto,
  DailyProfitAndLossDto,
} from './dto/reporting.dto';

@ApiTags('Reporting')
@ApiBearerAuth()
@Controller('reports')
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class ReportingController {
  constructor(private reportingService: ReportingService) {}

  @Get('dashboard')
  @RequirePermissions('reporting.dashboard')
  @ApiOperation({ summary: 'Get dashboard summary' })
  @ApiResponse({ status: 200, type: DashboardSummaryDto })
  async getDashboard(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<DashboardSummaryDto> {
    return this.reportingService.getDashboardSummary(user.tenantId, filter);
  }

  @Get('sales/summary')
  @RequirePermissions('reporting.sales_summary')
  @ApiOperation({ summary: 'Get sales summary' })
  @ApiResponse({ status: 200, type: SalesSummaryDto })
  async getSalesSummary(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<SalesSummaryDto> {
    return this.reportingService.getSalesSummary(user.tenantId, filter);
  }

  @Get('sales/trend')
  @RequirePermissions('reporting.sales_trend')
  @ApiOperation({ summary: 'Get sales trend over time' })
  @ApiResponse({ status: 200, type: [SalesTrendDto] })
  async getSalesTrend(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<SalesTrendDto[]> {
    return this.reportingService.getSalesTrend(user.tenantId, filter);
  }

  @Get('products/top')
  @RequirePermissions('reporting.top_products')
  @ApiOperation({ summary: 'Get top selling products' })
  @ApiResponse({ status: 200, type: [TopProductDto] })
  @ApiQuery({ name: 'limit', required: false, type: Number })
  async getTopProducts(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
    @Query('limit') limit?: number,
  ): Promise<TopProductDto[]> {
    return this.reportingService.getTopProducts(user.tenantId, filter, limit || 10);
  }

  @Get('categories')
  @RequirePermissions('reporting.category_sales')
  @ApiOperation({ summary: 'Get sales by category' })
  @ApiResponse({ status: 200, type: [CategorySalesDto] })
  async getCategorySales(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<CategorySalesDto[]> {
    return this.reportingService.getCategorySales(user.tenantId, filter);
  }

  @Get('cashiers')
  @RequirePermissions('reporting.cashier_performance')
  @ApiOperation({ summary: 'Get cashier performance' })
  @ApiResponse({ status: 200, type: [CashierPerformanceDto] })
  async getCashierPerformance(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<CashierPerformanceDto[]> {
    return this.reportingService.getCashierPerformance(user.tenantId, filter);
  }

  @Get('payments')
  @RequirePermissions('reporting.payment_breakdown')
  @ApiOperation({ summary: 'Get payment method breakdown' })
  @ApiResponse({ status: 200, type: [PaymentMethodBreakdownDto] })
  async getPaymentMethodBreakdown(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<PaymentMethodBreakdownDto[]> {
    return this.reportingService.getPaymentMethodBreakdown(user.tenantId, filter);
  }

  @Get('branches')
  @RequirePermissions('reporting.branch_comparison')
  @ApiOperation({ summary: 'Get branch comparison' })
  @ApiResponse({ status: 200, type: [BranchComparisonDto] })
  async getBranchComparison(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<BranchComparisonDto[]> {
    return this.reportingService.getBranchComparison(user.tenantId, filter);
  }

  @Get('inventory')
  @RequirePermissions('reporting.inventory_report')
  @ApiOperation({ summary: 'Get inventory report' })
  @ApiResponse({ status: 200, type: InventoryReportDto })
  async getInventoryReport(
    @CurrentUser() user: any,
    @Query('branchId') branchId?: string,
  ): Promise<InventoryReportDto> {
    return this.reportingService.getInventoryReport(user.tenantId, branchId);
  }

  @Get('inventory/movements')
  @RequirePermissions('reporting.inventory_report')
  @ApiOperation({ summary: 'Get stock movement summary' })
  @ApiResponse({ status: 200, type: StockMovementSummaryDto })
  async getStockMovementSummary(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<StockMovementSummaryDto> {
    return this.reportingService.getStockMovementSummary(user.tenantId, filter);
  }

  @Get('profit-loss/:branchId/:date')
  @RequirePermissions('reporting.profit_loss')
  @ApiOperation({ summary: 'Get daily profit and loss report with expense integration' })
  @ApiResponse({ status: 200, type: DailyProfitAndLossDto })
  async getDailyProfitAndLoss(
    @Param('branchId') branchId: string,
    @Param('date') date: string,
    @CurrentUser() user: any,
  ): Promise<DailyProfitAndLossDto> {
    return this.reportingService.getDailyProfitAndLoss(branchId, date, user.tenantId);
  }

  @Get('profit-loss')
  @RequirePermissions('reporting.profit_loss')
  @ApiOperation({ summary: 'Get profit and loss trend over a date range' })
  @ApiResponse({ status: 200, type: [DailyProfitAndLossDto] })
  async getProfitAndLossRange(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<DailyProfitAndLossDto[]> {
    return this.reportingService.getProfitAndLossRange(user.tenantId, filter);
  }
}
