import { Controller, Get, Post, Body, Param, Query, UseGuards, ParseUUIDPipe } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { CashReconciliationService } from './cash-reconciliation.service';
import { CreateReconciliationDto, ReconciliationQueryDto } from './dto/cash-reconciliation.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@ApiTags('cash-reconciliation')
@Controller({ path: 'cash-flow/reconciliations', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class CashReconciliationController {
  constructor(private readonly reconciliationService: CashReconciliationService) {}

  @Post(':branchId')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('cash_reconciliation.create')
  @ApiOperation({ summary: 'Record an end-of-day (or shift) cash count for a branch' })
  @ApiResponse({ status: 201, description: 'Reconciliation recorded' })
  async createReconciliation(
    @Param('branchId', ParseUUIDPipe) branchId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: CreateReconciliationDto,
  ) {
    return this.reconciliationService.createReconciliation(userId, branchId, dto);
  }

  @Get(':branchId')
  @ApiOperation({ summary: 'Get reconciliation history for a branch' })
  @ApiResponse({ status: 200, description: 'Paginated reconciliation history' })
  async getReconciliations(
    @Param('branchId', ParseUUIDPipe) branchId: string,
    @Query() query: ReconciliationQueryDto,
  ) {
    return this.reconciliationService.getReconciliations(branchId, query);
  }
}
