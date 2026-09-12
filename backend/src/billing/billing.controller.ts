import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Put,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { LegacyUserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { PrismaService } from '../common/prisma/prisma.service';
import { RecurringBillingService } from './recurring-billing.service';
import {
  ConfirmPaymentClaimDto,
  SubmitPaymentDto,
  UpdateBillingSettingsDto,
} from './dto/billing.dto';

/**
 * Recurring subscription billing (Jawaki): settings, manual paybill
 * claims, invoices, and entitlements.
 *
 * Route auth follows the subscription controller's legacy-role pattern:
 * plan/billing decisions are tenant-ownership concerns (there is no
 * `billing.manage` key in the seeded Permission catalog), so admin-only
 * routes use RolesGuard + @Roles(ADMIN) while staff-facing read/claim
 * routes stay behind plain JwtAuthGuard.
 */
@ApiTags('billing')
@Controller({ path: 'billing', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class BillingController {
  constructor(
    private readonly billing: RecurringBillingService,
    private readonly prisma: PrismaService,
  ) {}

  @Get('settings')
  @ApiOperation({ summary: 'Get this company’s recurring billing settings' })
  getSettings(@Req() req: any) {
    return this.billing.getBillingSettings(req.user.tenantId);
  }

  @Put('settings')
  @UseGuards(RolesGuard)
  @Roles(LegacyUserRole.ADMIN)
  @ApiOperation({
    summary: 'Update auto-renew / billing phone (owner only)',
  })
  updateSettings(@Req() req: any, @Body() dto: UpdateBillingSettingsDto) {
    return this.billing.updateBillingSettings(req.user.tenantId, dto);
  }

  @Post('submit-payment')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary:
      'Submit a manual paybill M-Pesa code against the current invoice (staff)',
  })
  submitPayment(@Req() req: any, @Body() dto: SubmitPaymentDto) {
    return this.billing.submitManualPayment(
      req.user.tenantId,
      req.user.sub,
      dto,
    );
  }

  @Get('claims')
  @UseGuards(RolesGuard)
  @Roles(LegacyUserRole.ADMIN)
  @ApiOperation({ summary: 'List manual M-Pesa payment claims awaiting review (owner only)' })
  listClaims(@Req() req: any) {
    return this.prisma.subscriptionPaymentClaim.findMany({
      where: { tenantId: req.user.tenantId, status: 'PENDING' },
      include: {
        invoice: {
          select: { id: true, plan: true, amount: true, currency: true },
        },
      },
      orderBy: { createdAt: 'asc' },
    });
  }

  @Post('claims/:id/confirm')
  @UseGuards(RolesGuard)
  @Roles(LegacyUserRole.ADMIN)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Approve or reject a manual payment claim (owner only)',
  })
  confirmClaim(
    @Req() req: any,
    @Param('id') claimId: string,
    @Body() dto: ConfirmPaymentClaimDto,
  ) {
    return this.billing.confirmManualPayment(
      req.user.tenantId,
      claimId,
      dto.approve,
    );
  }

  @Get('invoices')
  @ApiOperation({ summary: 'List this company’s subscription invoices' })
  listInvoices(@Req() req: any) {
    return this.prisma.subscriptionInvoice.findMany({
      where: { tenantId: req.user.tenantId },
      orderBy: { createdAt: 'desc' },
    });
  }

  @Get('entitlement')
  @ApiOperation({
    summary:
      'Entitlement snapshot: plan, status, days remaining, grace, restricted mode',
  })
  getEntitlement(@Req() req: any) {
    return this.billing.getEntitlement(req.user.tenantId);
  }

  @Get('entitlement/offline')
  @ApiOperation({
    summary:
      'HMAC-signed offline entitlement a device can cache for 7 days offline',
  })
  getOfflineEntitlement(@Req() req: any) {
    return this.billing.buildOfflineEntitlement(req.user.tenantId);
  }
}