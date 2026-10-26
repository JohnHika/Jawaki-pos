import {
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  Post,
  Put,
  Req,
  ServiceUnavailableException,
  UseGuards,
  Optional,
} from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { LegacyUserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { PrismaService } from '../common/prisma/prisma.service';
import { RecurringBillingService } from './recurring-billing.service';
import { PaystackBillingService } from './paystack-billing.service';
import { UpdateBillingSettingsDto } from './dto/billing.dto';
import { LegalPolicyService } from '../legal/legal-policy.service';
import { JengaPaymentService } from '../payments/jenga-payment.service';

/**
 * Recurring subscription billing: provider checkout, renewal settings,
 * invoices, and entitlements.
 *
 * Route auth follows the subscription controller's legacy-role pattern:
 * plan/billing decisions are tenant-ownership concerns (there is no
 * `billing.manage` key in the seeded Permission catalog), so billing
 * changes stay restricted to the company administrator.
 */
@ApiTags('billing')
@Controller({ path: 'billing', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class BillingController {
  constructor(
    private readonly billing: RecurringBillingService,
    private readonly paystackBilling: PaystackBillingService,
    private readonly jengaPayments: JengaPaymentService,
    private readonly prisma: PrismaService,
    @Optional() private readonly legalPolicies?: LegalPolicyService,
  ) {}

  @Post('paystack/initialize')
  @ApiOperation({ summary: 'Start Paystack checkout for the current monthly invoice' })
  initializePaystackInvoice(@Req() req: any) {
    return this.paystackBilling.initializeInvoicePayment(
      req.user.tenantId,
      req.user.sub,
    );
  }

  @Get('paystack/verify/:reference')
  @ApiOperation({ summary: 'Verify a Paystack monthly subscription payment' })
  verifyPaystackInvoice(@Req() req: any, @Param('reference') reference: string) {
    return this.paystackBilling.verifyInvoicePayment(
      req.user.tenantId,
      reference,
    );
  }

  @Get('mpesa/verify/:invoiceId')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  @ApiOperation({ summary: 'Refresh an M-Pesa subscription renewal status' })
  async verifyMpesaRenewal(@Req() req: any, @Param('invoiceId') invoiceId: string) {
    const invoice = await this.prisma.subscriptionInvoice.findFirst({
      where: { id: invoiceId, tenantId: req.user.tenantId },
      select: {
        id: true,
        status: true,
        provider: true,
        mpesaCheckoutId: true,
      },
    });
    if (!invoice) throw new NotFoundException('Subscription invoice not found');
    if (invoice.status === 'PAID') {
      return { invoiceId: invoice.id, invoiceStatus: 'PAID', status: 'COMPLETED' };
    }
    if (invoice.provider !== 'JENGA_STK' || !invoice.mpesaCheckoutId) {
      return {
        invoiceId: invoice.id,
        invoiceStatus: invoice.status,
        provider: invoice.provider,
        status: invoice.status,
      };
    }

    const payment = await this.jengaPayments.status(invoice.mpesaCheckoutId, true);
    const refreshed = await this.prisma.subscriptionInvoice.findUnique({
      where: { id: invoice.id },
      select: { status: true, provider: true },
    });
    return {
      ...payment,
      invoiceId: invoice.id,
      invoiceStatus: refreshed?.status ?? invoice.status,
      provider: refreshed?.provider ?? null,
    };
  }

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
    if (dto.autoRenewEnabled === true) {
      if (!this.legalPolicies) {
        throw new ServiceUnavailableException('Policy acceptance service is unavailable');
      }
      return this.legalPolicies.accept(
        req.user.tenantId,
        req.user.sub,
        'AUTO_RENEWAL_AUTHORIZATION',
        dto.autoRenewAuthorizationVersion ?? '',
      ).then(() => this.billing.updateBillingSettings(req.user.tenantId, dto));
    }
    return this.billing.updateBillingSettings(req.user.tenantId, dto);
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
