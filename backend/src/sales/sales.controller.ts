import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  UseGuards,
  Request,
  HttpCode,
  HttpStatus,
  ParseUUIDPipe,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiQuery,
} from '@nestjs/swagger';
import { SalesService } from './sales.service';
import {
  CreateSaleDto,
  CreateRefundDto,
  SalesQueryDto,
  SaleResponseDto,
  PaginatedSalesDto,
  DailySummaryDto,
  ReconcileOfflineSalesDto,
} from './dto/sales.dto';
import {
  BulkCreateSalesDto,
  BulkVoidSalesDto,
} from './dto/bulk-sales.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { SubscriptionGuard } from '../billing/subscription.guard';

@ApiTags('sales')
@Controller({ path: 'sales', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class SalesController {
  constructor(private readonly salesService: SalesService) {}

  @Post()
  @UseGuards(SubscriptionGuard, PermissionsGuard)
  @RequirePermissions('sales.create')
  @ApiOperation({ summary: 'Create a new sale' })
  @ApiResponse({ status: 201, description: 'Sale created', type: SaleResponseDto })
  async createSale(@Request() req: any, @Body() dto: CreateSaleDto) {
    return this.salesService.createSale(req.user.sub, req.user.tenantId, dto);
  }

  @Get()
  @UseGuards(PermissionsGuard)
  @RequirePermissions('sales.view')
  @ApiOperation({ summary: 'Get sales with filtering and pagination' })
  @ApiResponse({ status: 200, description: 'Paginated sales', type: PaginatedSalesDto })
  async getSales(@Request() req: any, @Query() query: SalesQueryDto) {
    const canViewAll = req.user.permissions?.includes('sales.view_all') === true;
    return this.salesService.getSales(
      req.user.tenantId,
      canViewAll ? query : { ...query, userId: req.user.sub },
    );
  }

  @Post('offline-reconciliation')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('sync.push')
  @ApiOperation({ summary: 'Check which device sales are already on the server' })
  async reconcileOfflineSales(
    @Request() req: any,
    @Body() dto: ReconcileOfflineSalesDto,
  ) {
    return this.salesService.reconcileOfflineSales(req.user.tenantId, dto);
  }

  @Get('summary/:branchId')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('reporting.sales_summary')
  @ApiOperation({ summary: 'Get the current business-day sales summary for a branch' })
  @ApiResponse({ status: 200, description: 'Current business-day summary', type: DailySummaryDto })
  async getTodayDailySummary(
    @Param('branchId', ParseUUIDPipe) branchId: string,
    @Request() req: any,
  ) {
    return this.salesService.getTodayDailySummary(branchId, req.user.tenantId);
  }

  @Get('summary/:branchId/:date')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('reporting.sales_summary')
  @ApiOperation({ summary: 'Get daily sales summary for a branch' })
  @ApiResponse({ status: 200, description: 'Daily summary', type: DailySummaryDto })
  async getDailySummary(
    @Param('branchId') branchId: string,
    @Param('date') date: string,
    @Request() req: any,
  ) {
    return this.salesService.getDailySummary(branchId, date, req.user.tenantId);
  }

  @Get('credit')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('customers.credit_view')
  @ApiOperation({ summary: 'Get credit sales with outstanding balances' })
  @ApiResponse({ status: 200, description: 'Credit sales with outstanding balances' })
  async getCreditSales(
    @Request() req: any,
    @Query() query: SalesQueryDto,
  ) {
    const canViewAll = req.user.permissions?.includes('sales.view_all') === true;
    return this.salesService.getCreditSalesWithOutstandingBalance(
      req.user.tenantId,
      canViewAll ? query : { ...query, userId: req.user.sub },
    );
  }

  @Get('receipt/:receiptNumber')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('sales.view')
  @ApiOperation({ summary: 'Get sale by receipt number' })
  @ApiResponse({ status: 200, description: 'Sale details', type: SaleResponseDto })
  async getReceipt(@Param('receiptNumber') receiptNumber: string, @Request() req: any) {
    const canViewAll = req.user.permissions?.includes('sales.view_all') === true;
    return this.salesService.getReceipt(
      receiptNumber,
      req.user.tenantId,
      canViewAll ? undefined : req.user.sub,
    );
  }

  @Get(':id')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('sales.view')
  @ApiOperation({ summary: 'Get sale by ID' })
  @ApiResponse({ status: 200, description: 'Sale details', type: SaleResponseDto })
  async getSale(@Param('id') id: string, @Request() req: any) {
    const canViewAll = req.user.permissions?.includes('sales.view_all') === true;
    return this.salesService.getSale(
      id,
      req.user.tenantId,
      canViewAll ? undefined : req.user.sub,
    );
  }

  @Post(':id/void')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('sales.void')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Void a sale (Supervisor+ only)' })
  @ApiResponse({ status: 200, description: 'Sale voided' })
  async voidSale(
    @Param('id') id: string,
    @Request() req: any,
    @Body() body: { reason: string },
  ) {
    return this.salesService.voidSale(id, req.user.sub, req.user.tenantId, body.reason);
  }

  @Post('refund')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('sales.refund')
  @ApiOperation({ summary: 'Create a refund (Supervisor+ only)' })
  @ApiResponse({ status: 201, description: 'Refund created' })
  async createRefund(@Request() req: any, @Body() dto: CreateRefundDto) {
    return this.salesService.createRefund(req.user.sub, req.user.tenantId, dto);
  }

  // ==================== BULK SALES ENDPOINTS ====================

  @Post('bulk')
  // Bulk sync can flood the ledger/receipt sequence, so it requires the
  // dedicated bulk_create capability rather than the any-cashier sales
  // create. Mirrors the bulk/void route below. SubscriptionGuard blocks
  // offline-queue flushes when the tenant is PAST_DUE beyond grace (GETs
  // stay open, so historical data is never blocked).
  @UseGuards(SubscriptionGuard, PermissionsGuard)
  @RequirePermissions('sales.bulk_create')
  @ApiOperation({ summary: 'Bulk create sales (e.g., offline sync)' })
  @ApiResponse({ status: 201, description: 'Sales created', type: [SaleResponseDto] })
  async bulkCreateSales(@Request() req: any, @Body() dto: BulkCreateSalesDto) {
    return this.salesService.bulkCreateSales(req.user.sub, req.user.tenantId, dto.sales);
  }

  @Post('bulk/void')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('sales.bulk_void')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Bulk void sales (Supervisor+ only)' })
  @ApiResponse({ status: 200, description: 'Sales voided' })
  async bulkVoidSales(@Request() req: any, @Body() dto: BulkVoidSalesDto) {
    return this.salesService.bulkVoidSales(req.user.sub, req.user.tenantId, dto.ids, dto.reason);
  }
}
