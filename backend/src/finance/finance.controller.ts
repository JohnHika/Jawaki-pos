import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import {
  CreatePeerDebtorDto,
  CreatePeerReceivableDto,
  FinanceBranchQueryDto,
  FinanceStatusQueryDto,
  PayablesQueryDto,
  RecordReceivablePaymentDto,
} from './dto/finance.dto';
import { FinanceService } from './finance.service';

@ApiTags('finance')
@ApiBearerAuth('JWT-auth')
@Controller({ path: 'finance', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class FinanceController {
  constructor(private readonly financeService: FinanceService) {}

  @Get('overview')
  @RequirePermissions('finance.view')
  @ApiOperation({ summary: 'Get branch finance overview' })
  getOverview(@CurrentUser('tenantId') tenantId: string, @Query() query: FinanceBranchQueryDto) {
    return this.financeService.getOverview(tenantId, query.branchId);
  }

  @Get('payables')
  @RequirePermissions('finance.view')
  @ApiOperation({ summary: 'List supplier payables for a branch' })
  getPayables(@CurrentUser('tenantId') tenantId: string, @Query() query: PayablesQueryDto) {
    return this.financeService.getPayables(tenantId, query.branchId, query.status);
  }

  @Get('retail-receivables')
  @RequirePermissions('finance.view')
  @ApiOperation({ summary: 'List retail credit receivables for a branch' })
  getRetailReceivables(@CurrentUser('tenantId') tenantId: string, @Query() query: FinanceStatusQueryDto) {
    return this.financeService.getRetailReceivables(tenantId, query.branchId, query.status);
  }

  @Post('retail-receivables/:id/payments')
  @RequirePermissions('finance.manage_receivables')
  @ApiOperation({ summary: 'Allocate a collection to a retail receivable' })
  recordRetailPayment(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: RecordReceivablePaymentDto,
  ) {
    return this.financeService.recordRetailPayment(userId, tenantId, id, dto);
  }

  @Get('peer-debtors')
  @RequirePermissions('finance.view')
  @ApiOperation({ summary: 'List tenant peer-shop debtors' })
  getPeerDebtors(@CurrentUser('tenantId') tenantId: string) {
    return this.financeService.getPeerDebtors(tenantId);
  }

  @Post('peer-debtors')
  @RequirePermissions('finance.manage_receivables')
  @ApiOperation({ summary: 'Create or update a peer-shop debtor' })
  createPeerDebtor(@CurrentUser('tenantId') tenantId: string, @Body() dto: CreatePeerDebtorDto) {
    return this.financeService.createPeerDebtor(tenantId, dto);
  }

  @Get('peer-receivables')
  @RequirePermissions('finance.view')
  @ApiOperation({ summary: 'List B2B peer-shop receivables for a branch' })
  getPeerReceivables(@CurrentUser('tenantId') tenantId: string, @Query() query: FinanceStatusQueryDto) {
    return this.financeService.getPeerReceivables(tenantId, query.branchId, query.status);
  }

  @Post('peer-receivables')
  @RequirePermissions('finance.manage_receivables')
  @ApiOperation({ summary: 'Create a B2B peer-shop receivable' })
  createPeerReceivable(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: CreatePeerReceivableDto,
  ) {
    return this.financeService.createPeerReceivable(userId, tenantId, dto);
  }

  @Post('peer-receivables/:id/payments')
  @RequirePermissions('finance.manage_receivables')
  @ApiOperation({ summary: 'Allocate a collection to a peer-shop receivable' })
  recordPeerPayment(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: RecordReceivablePaymentDto,
  ) {
    return this.financeService.recordPeerPayment(userId, tenantId, id, dto);
  }
}
