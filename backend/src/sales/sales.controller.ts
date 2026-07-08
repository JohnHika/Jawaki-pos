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
} from './dto/sales.dto';
import {
  BulkCreateSalesDto,
  BulkVoidSalesDto,
} from './dto/bulk-sales.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';

@ApiTags('sales')
@Controller({ path: 'sales', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class SalesController {
  constructor(private readonly salesService: SalesService) {}

  @Post()
  @ApiOperation({ summary: 'Create a new sale' })
  @ApiResponse({ status: 201, description: 'Sale created', type: SaleResponseDto })
  async createSale(@Request() req: any, @Body() dto: CreateSaleDto) {
    return this.salesService.createSale(req.user.sub, req.user.tenantId, dto);
  }

  @Get()
  @ApiOperation({ summary: 'Get sales with filtering and pagination' })
  @ApiResponse({ status: 200, description: 'Paginated sales', type: PaginatedSalesDto })
  async getSales(@Request() req: any, @Query() query: SalesQueryDto) {
    return this.salesService.getSales(req.user.tenantId, query);
  }

  @Get('summary/:branchId/:date')
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
  @ApiOperation({ summary: 'Get credit sales with outstanding balances' })
  @ApiResponse({ status: 200, description: 'Credit sales with outstanding balances' })
  async getCreditSales(
    @Request() req: any,
    @Query() query: SalesQueryDto,
  ) {
    return this.salesService.getCreditSalesWithOutstandingBalance(req.user.tenantId, query);
  }

  @Get('receipt/:receiptNumber')
  @ApiOperation({ summary: 'Get sale by receipt number' })
  @ApiResponse({ status: 200, description: 'Sale details', type: SaleResponseDto })
  async getReceipt(@Param('receiptNumber') receiptNumber: string, @Request() req: any) {
    return this.salesService.getReceipt(receiptNumber, req.user.tenantId);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get sale by ID' })
  @ApiResponse({ status: 200, description: 'Sale details', type: SaleResponseDto })
  async getSale(@Param('id') id: string, @Request() req: any) {
    return this.salesService.getSale(id, req.user.tenantId);
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
