import {
  Controller,
  Get,
  Query,
  UseGuards,
  Param,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiResponse, ApiQuery } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
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
} from './dto/reporting.dto';

@ApiTags('Reporting')
@ApiBearerAuth()
@Controller('reports')
@UseGuards(JwtAuthGuard, RolesGuard)
export class ReportingController {
  constructor(private reportingService: ReportingService) {}

  @Get('dashboard')
  @Roles('MANAGER', 'ADMIN')
  @ApiOperation({ summary: 'Get dashboard summary' })
  @ApiResponse({ status: 200, type: DashboardSummaryDto })
  async getDashboard(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<DashboardSummaryDto> {
    return this.reportingService.getDashboardSummary(user.tenantId, filter);
  }

  @Get('sales/summary')
  @Roles('SUPERVISOR', 'MANAGER', 'ADMIN')
  @ApiOperation({ summary: 'Get sales summary' })
  @ApiResponse({ status: 200, type: SalesSummaryDto })
  async getSalesSummary(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<SalesSummaryDto> {
    return this.reportingService.getSalesSummary(user.tenantId, filter);
  }

  @Get('sales/trend')
  @Roles('SUPERVISOR', 'MANAGER', 'ADMIN')
  @ApiOperation({ summary: 'Get sales trend over time' })
  @ApiResponse({ status: 200, type: [SalesTrendDto] })
  async getSalesTrend(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<SalesTrendDto[]> {
    return this.reportingService.getSalesTrend(user.tenantId, filter);
  }

  @Get('products/top')
  @Roles('SUPERVISOR', 'MANAGER', 'ADMIN')
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
  @Roles('SUPERVISOR', 'MANAGER', 'ADMIN')
  @ApiOperation({ summary: 'Get sales by category' })
  @ApiResponse({ status: 200, type: [CategorySalesDto] })
  async getCategorySales(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<CategorySalesDto[]> {
    return this.reportingService.getCategorySales(user.tenantId, filter);
  }

  @Get('cashiers')
  @Roles('MANAGER', 'ADMIN')
  @ApiOperation({ summary: 'Get cashier performance' })
  @ApiResponse({ status: 200, type: [CashierPerformanceDto] })
  async getCashierPerformance(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<CashierPerformanceDto[]> {
    return this.reportingService.getCashierPerformance(user.tenantId, filter);
  }

  @Get('payments')
  @Roles('SUPERVISOR', 'MANAGER', 'ADMIN')
  @ApiOperation({ summary: 'Get payment method breakdown' })
  @ApiResponse({ status: 200, type: [PaymentMethodBreakdownDto] })
  async getPaymentMethodBreakdown(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<PaymentMethodBreakdownDto[]> {
    return this.reportingService.getPaymentMethodBreakdown(user.tenantId, filter);
  }

  @Get('branches')
  @Roles('MANAGER', 'ADMIN')
  @ApiOperation({ summary: 'Get branch comparison' })
  @ApiResponse({ status: 200, type: [BranchComparisonDto] })
  async getBranchComparison(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<BranchComparisonDto[]> {
    return this.reportingService.getBranchComparison(user.tenantId, filter);
  }

  @Get('inventory')
  @Roles('SUPERVISOR', 'MANAGER', 'ADMIN')
  @ApiOperation({ summary: 'Get inventory report' })
  @ApiResponse({ status: 200, type: InventoryReportDto })
  async getInventoryReport(
    @CurrentUser() user: any,
    @Query('branchId') branchId?: string,
  ): Promise<InventoryReportDto> {
    return this.reportingService.getInventoryReport(user.tenantId, branchId);
  }

  @Get('inventory/movements')
  @Roles('SUPERVISOR', 'MANAGER', 'ADMIN')
  @ApiOperation({ summary: 'Get stock movement summary' })
  @ApiResponse({ status: 200, type: StockMovementSummaryDto })
  async getStockMovementSummary(
    @CurrentUser() user: any,
    @Query() filter: ReportFilterDto,
  ): Promise<StockMovementSummaryDto> {
    return this.reportingService.getStockMovementSummary(user.tenantId, filter);
  }
}
