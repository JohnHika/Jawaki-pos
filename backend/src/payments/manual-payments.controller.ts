import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import {
  CreateManualPaymentRequestDto,
  ManualPaymentListQueryDto,
  RejectManualPaymentDto,
} from './dto/manual-payment.dto';
import { ManualPaymentsService } from './manual-payments.service';

@ApiTags('payments')
@ApiBearerAuth('JWT-auth')
@Controller({ path: 'payments/manual', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class ManualPaymentsController {
  constructor(private readonly manualPayments: ManualPaymentsService) {}

  @Post('request')
  @RequirePermissions('sales.create')
  @ApiOperation({ summary: 'Request approval for a payment taken outside the app' })
  create(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: CreateManualPaymentRequestDto,
  ) {
    return this.manualPayments.createRequest(userId, tenantId, dto);
  }

  @Get()
  @RequirePermissions('payments.view_status')
  @ApiOperation({ summary: 'List manual payment requests (approvers see all, others their own)' })
  list(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @CurrentUser('permissions') permissions: string[] | undefined,
    @Query() query: ManualPaymentListQueryDto,
  ) {
    return this.manualPayments.list(userId, tenantId, permissions ?? [], query);
  }

  @Post(':id/approve')
  @RequirePermissions('payments.manual_approve')
  @ApiOperation({ summary: 'Approve a manual payment request' })
  approve(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
  ) {
    return this.manualPayments.approve(userId, tenantId, id);
  }

  @Post(':id/reject')
  @RequirePermissions('payments.manual_approve')
  @ApiOperation({ summary: 'Reject a manual payment request' })
  reject(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: RejectManualPaymentDto,
  ) {
    return this.manualPayments.reject(userId, tenantId, id, dto);
  }
}
