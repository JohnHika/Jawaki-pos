import {
  Controller,
  Get,
  Post,
  Put,
  Body,
  Param,
  Query,
  UseGuards,
  Request,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiQuery,
} from '@nestjs/swagger';
import { InventoryService } from './inventory.service';
import {
  StockAdjustmentDto,
  CreateTransferDto,
  ReceiveTransferDto,
  StockQueryDto,
  StockItemResponseDto,
  TransferResponseDto,
  ReceiveBatchDto,
  UpdateBatchDto,
  ExpiryDashboardQueryDto,
  StockWithBatchesResponseDto,
  ExpiryDashboardResponseDto,
  CreateStockRequestDto,
  UpdateStockRequestDto,
  ResolveStockRequestDto,
  StockRequestQueryDto,
  StockRequestResponseDto,
} from './dto/inventory.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { UserRole } from '@prisma/client';

@ApiTags('inventory')
@Controller({ path: 'inventory', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class InventoryController {
  constructor(private readonly inventoryService: InventoryService) {}

  @Get('stock/:branchId')
  @ApiOperation({ summary: 'Get stock levels for a branch' })
  @ApiResponse({ status: 200, description: 'Stock list', type: [StockItemResponseDto] })
  async getStock(
    @Param('branchId') branchId: string,
    @Request() req: any,
    @Query() query: StockQueryDto,
  ) {
    return this.inventoryService.getStock(branchId, req.user.tenantId, query);
  }

  @Get('stock/product/:productId')
  @ApiOperation({ summary: 'Get stock for a product across all branches' })
  @ApiResponse({ status: 200, description: 'Product stock by branch' })
  async getProductStock(@Param('productId') productId: string, @Request() req: any) {
    return this.inventoryService.getProductStock(productId, req.user.tenantId);
  }

  @Post('adjust')
  @UseGuards(RolesGuard)
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  @ApiOperation({ summary: 'Adjust stock levels (Supervisor+ only)' })
  @ApiResponse({ status: 201, description: 'Stock adjusted' })
  async adjustStock(@Request() req: any, @Body() dto: StockAdjustmentDto) {
    return this.inventoryService.adjustStock(req.user.sub, req.user.tenantId, dto);
  }

  @Get('movements/:branchId')
  @ApiOperation({ summary: 'Get stock movement history' })
  @ApiResponse({ status: 200, description: 'Stock movements' })
  @ApiQuery({ name: 'productId', required: false })
  @ApiQuery({ name: 'startDate', required: false })
  @ApiQuery({ name: 'endDate', required: false })
  @ApiQuery({ name: 'page', required: false })
  @ApiQuery({ name: 'limit', required: false })
  async getStockMovements(
    @Param('branchId') branchId: string,
    @Request() req: any,
    @Query('productId') productId?: string,
    @Query('startDate') startDate?: string,
    @Query('endDate') endDate?: string,
    @Query('page') page?: number,
    @Query('limit') limit?: number,
  ) {
    return this.inventoryService.getStockMovements(
      branchId,
      req.user.tenantId,
      productId,
      startDate,
      endDate,
      page,
      limit,
    );
  }

  @Get('low-stock')
  @ApiOperation({ summary: 'Get low stock alerts' })
  @ApiResponse({ status: 200, description: 'Low stock items' })
  @ApiQuery({ name: 'branchId', required: false })
  async getLowStockAlerts(
    @Request() req: any,
    @Query('branchId') branchId?: string,
  ) {
    return this.inventoryService.getLowStockAlerts(req.user.tenantId, branchId);
  }

  // ==================== TRANSFERS ====================

  @Post('transfers')
  @UseGuards(RolesGuard)
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  @ApiOperation({ summary: 'Create a stock transfer request' })
  @ApiResponse({ status: 201, description: 'Transfer created', type: TransferResponseDto })
  async createTransfer(@Request() req: any, @Body() dto: CreateTransferDto) {
    return this.inventoryService.createTransfer(req.user.sub, req.user.tenantId, dto);
  }

  @Get('transfers')
  @ApiOperation({ summary: 'Get stock transfers' })
  @ApiResponse({ status: 200, description: 'Transfer list' })
  @ApiQuery({ name: 'branchId', required: false })
  @ApiQuery({ name: 'status', required: false })
  @ApiQuery({ name: 'page', required: false })
  @ApiQuery({ name: 'limit', required: false })
  async getTransfers(
    @Request() req: any,
    @Query('branchId') branchId?: string,
    @Query('status') status?: string,
    @Query('page') page?: number,
    @Query('limit') limit?: number,
  ) {
    return this.inventoryService.getTransfers(
      req.user.tenantId,
      branchId,
      status,
      page,
      limit,
    );
  }

  @Get('transfers/:id')
  @ApiOperation({ summary: 'Get transfer details' })
  @ApiResponse({ status: 200, description: 'Transfer details', type: TransferResponseDto })
  async getTransfer(@Param('id') id: string, @Request() req: any) {
    return this.inventoryService.getTransfer(id, req.user.tenantId);
  }

  @Post('transfers/:id/send')
  @UseGuards(RolesGuard)
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  @ApiOperation({ summary: 'Send a pending transfer' })
  @ApiResponse({ status: 200, description: 'Transfer sent' })
  async sendTransfer(@Param('id') id: string, @Request() req: any) {
    return this.inventoryService.sendTransfer(id, req.user.sub, req.user.tenantId);
  }

  @Post('transfers/:id/receive')
  @UseGuards(RolesGuard)
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  @ApiOperation({ summary: 'Receive a transfer' })
  @ApiResponse({ status: 200, description: 'Transfer received' })
  async receiveTransfer(
    @Param('id') id: string,
    @Request() req: any,
    @Body() dto: ReceiveTransferDto,
  ) {
    return this.inventoryService.receiveTransfer(id, req.user.sub, req.user.tenantId, dto);
  }

  // ==================== BATCH & EXPIRY MANAGEMENT ====================

  @Post('batches/receive')
  @UseGuards(RolesGuard)
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  @ApiOperation({ summary: 'Receive stock with batch tracking (for medicines)' })
  @ApiResponse({ status: 201, description: 'Batches received successfully' })
  async receiveBatch(@Request() req: any, @Body() dto: ReceiveBatchDto) {
    return this.inventoryService.receiveBatch(req.user.sub, req.user.tenantId, dto);
  }

  @Get('batches/:branchId/:productId')
  @ApiOperation({ summary: 'Get stock with batch details for a product' })
  @ApiResponse({ status: 200, description: 'Stock with batches', type: StockWithBatchesResponseDto })
  async getStockWithBatches(
    @Param('branchId') branchId: string,
    @Param('productId') productId: string,
    @Request() req: any,
  ) {
    return this.inventoryService.getStockWithBatches(branchId, productId, req.user.tenantId);
  }

  @Put('batches/:batchId')
  @UseGuards(RolesGuard)
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  @ApiOperation({ summary: 'Update batch details (block expired, adjust quantity)' })
  @ApiResponse({ status: 200, description: 'Batch updated' })
  async updateBatch(
    @Param('batchId') batchId: string,
    @Request() req: any,
    @Body() dto: UpdateBatchDto,
  ) {
    return this.inventoryService.updateBatch(batchId, req.user.sub, req.user.tenantId, dto);
  }

  @Get('expiry-dashboard')
  @UseGuards(RolesGuard)
  @Roles(UserRole.MANAGER, UserRole.ADMIN)
  @ApiOperation({ summary: 'Expiry Dashboard - View expired and expiring stock (Manager+)' })
  @ApiResponse({ status: 200, description: 'Expiry dashboard data', type: ExpiryDashboardResponseDto })
  async getExpiryDashboard(
    @Request() req: any,
    @Query() query: ExpiryDashboardQueryDto,
  ) {
    return this.inventoryService.getExpiryDashboard(req.user.tenantId, query);
  }

  @Post('batches/block-expired')
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'Auto-block all expired batches (Admin only)' })
  @ApiResponse({ status: 200, description: 'Expired batches blocked' })
  async blockExpiredBatches(@Request() req: any) {
    return this.inventoryService.blockExpiredBatches(req.user.tenantId);
  }

  @Get('batches/fefo/:branchId/:productId')
  @ApiOperation({ summary: 'Get FEFO batch allocation for a quantity (for POS)' })
  @ApiResponse({ status: 200, description: 'Batch allocations using FEFO logic' })
  @ApiQuery({ name: 'quantity', required: true, description: 'Requested quantity' })
  async allocateBatchesFEFO(
    @Param('branchId') branchId: string,
    @Param('productId') productId: string,
    @Query('quantity') quantity: number,
    @Request() req: any,
  ) {
    return this.inventoryService.allocateBatchesFEFO(
      branchId,
      productId,
      Number(quantity),
      req.user.tenantId,
    );
  }

  // ==================== STOCK REQUESTS ====================

  @Post('stock-requests')
  @ApiOperation({ summary: 'Create a stock request (Cashiers/Sellers request stock from managers)' })
  @ApiResponse({ status: 201, description: 'Stock request created', type: StockRequestResponseDto })
  async createStockRequest(@Request() req: any, @Body() dto: CreateStockRequestDto) {
    return this.inventoryService.createStockRequest(req.user.sub, req.user.tenantId, dto);
  }

  @Get('stock-requests')
  @ApiOperation({ summary: 'Get stock requests (filtered by role and branch)' })
  @ApiResponse({ status: 200, description: 'List of stock requests', type: [StockRequestResponseDto] })
  async getStockRequests(@Request() req: any, @Query() query: StockRequestQueryDto) {
    return this.inventoryService.getStockRequests(req.user.sub, req.user.tenantId, query);
  }

  @Get('stock-requests/:id')
  @ApiOperation({ summary: 'Get a single stock request by ID' })
  @ApiResponse({ status: 200, description: 'Stock request details', type: StockRequestResponseDto })
  async getStockRequest(@Param('id') id: string, @Request() req: any) {
    return this.inventoryService.getStockRequest(id, req.user.tenantId);
  }

  @Put('stock-requests/:id')
  @ApiOperation({ summary: 'Update a stock request (requester can edit before approval)' })
  @ApiResponse({ status: 200, description: 'Stock request updated', type: StockRequestResponseDto })
  async updateStockRequest(
    @Param('id') id: string,
    @Request() req: any,
    @Body() dto: UpdateStockRequestDto,
  ) {
    return this.inventoryService.updateStockRequest(id, req.user.sub, req.user.tenantId, dto);
  }

  @Put('stock-requests/:id/resolve')
  @UseGuards(RolesGuard)
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  @ApiOperation({ summary: 'Resolve a stock request (approve/reject/fulfill) - Supervisor+ only' })
  @ApiResponse({ status: 200, description: 'Stock request resolved', type: StockRequestResponseDto })
  async resolveStockRequest(
    @Param('id') id: string,
    @Request() req: any,
    @Body() dto: ResolveStockRequestDto,
  ) {
    return this.inventoryService.resolveStockRequest(id, req.user.sub, req.user.tenantId, dto);
  }

  @Put('stock-requests/:id/cancel')
  @ApiOperation({ summary: 'Cancel a stock request (requester can cancel)' })
  @ApiResponse({ status: 200, description: 'Stock request cancelled', type: StockRequestResponseDto })
  async cancelStockRequest(@Param('id') id: string, @Request() req: any) {
    return this.inventoryService.cancelStockRequest(id, req.user.sub, req.user.tenantId);
  }

  @Get('stock-requests/stats/summary')
  @UseGuards(RolesGuard)
  @Roles(UserRole.SUPERVISOR, UserRole.MANAGER, UserRole.ADMIN)
  @ApiOperation({ summary: 'Get stock request statistics - Supervisor+ only' })
  @ApiResponse({ status: 200, description: 'Stock request statistics' })
  async getStockRequestStats(@Request() req: any, @Query('branchId') branchId?: string) {
    return this.inventoryService.getStockRequestStats(req.user.tenantId, branchId);
  }
}
