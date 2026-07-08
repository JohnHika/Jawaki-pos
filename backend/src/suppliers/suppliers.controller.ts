import { Controller, Get, Post, Body, Param, UseGuards, ParseUUIDPipe } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { SuppliersService } from './suppliers.service';
import { CreateSupplierDto, CreateSupplierInvoiceDto, RecordSupplierPaymentDto } from './dto/suppliers.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@ApiTags('suppliers')
@Controller({ path: 'suppliers', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class SuppliersController {
  constructor(private readonly suppliersService: SuppliersService) {}

  @Post()
  @ApiOperation({ summary: 'Create or update a supplier' })
  @ApiResponse({ status: 201, description: 'Supplier created' })
  async createSupplier(@CurrentUser('tenantId') tenantId: string, @Body() dto: CreateSupplierDto) {
    return this.suppliersService.createSupplier(tenantId, dto);
  }

  @Get()
  @ApiOperation({ summary: 'List active suppliers' })
  @ApiResponse({ status: 200, description: 'List of suppliers' })
  async getSuppliers(@CurrentUser('tenantId') tenantId: string) {
    return this.suppliersService.getSuppliers(tenantId);
  }

  @Get('debts')
  @ApiOperation({ summary: 'Get supplier balances (invoiced, paid, owed) across the tenant' })
  @ApiResponse({ status: 200, description: 'Supplier debt summary' })
  async getSupplierDebts(@CurrentUser('tenantId') tenantId: string) {
    return this.suppliersService.getSupplierDebts(tenantId);
  }

  @Get(':id/invoices')
  @ApiOperation({ summary: 'Get invoices for a supplier' })
  @ApiResponse({ status: 200, description: 'List of invoices' })
  async getSupplierInvoices(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('tenantId') tenantId: string,
  ) {
    return this.suppliersService.getSupplierInvoices(tenantId, id);
  }

  @Post('invoices')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('suppliers.invoices_create')
  @ApiOperation({ summary: 'Record a supplier invoice (restock purchase)' })
  @ApiResponse({ status: 201, description: 'Invoice recorded, stock updated' })
  async createInvoice(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: CreateSupplierInvoiceDto,
  ) {
    return this.suppliersService.createInvoice(userId, tenantId, dto);
  }

  @Get('invoices/:id')
  @ApiOperation({ summary: 'Get a supplier invoice by ID' })
  @ApiResponse({ status: 200, description: 'Invoice details' })
  async getInvoice(@Param('id', ParseUUIDPipe) id: string, @CurrentUser('tenantId') tenantId: string) {
    return this.suppliersService.getInvoice(id, tenantId);
  }

  @Post('invoices/:id/payments')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('suppliers.payments_record')
  @ApiOperation({ summary: 'Record a payment against a supplier invoice' })
  @ApiResponse({ status: 201, description: 'Payment recorded' })
  async recordPayment(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: RecordSupplierPaymentDto,
  ) {
    return this.suppliersService.recordPayment(userId, tenantId, id, dto);
  }
}
