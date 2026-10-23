import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { SubscriptionGuard } from '../billing/subscription.guard';
import { ConfigureMerchantPayoutDto, StartMerchantMpesaDto } from './dto/merchant-payments.dto';
import { MerchantPaymentsService } from './merchant-payments.service';

@ApiTags('merchant-payments')
@ApiBearerAuth('JWT-auth')
@Controller({ path: 'merchant-payments', version: '1' })
@UseGuards(JwtAuthGuard)
export class MerchantPaymentsController {
  constructor(private readonly payments: MerchantPaymentsService) {}

  @Get('account')
  account(@CurrentUser() actor: { sub: string; tenantId: string }) {
    return this.payments.account(actor);
  }

  @Get('banks')
  banks() {
    return this.payments.banks();
  }

  @Get('charges')
  recentCharges(@CurrentUser() actor: { sub: string; tenantId: string }) {
    return this.payments.recentCharges(actor);
  }

  @Post('account')
  configureAccount(
    @CurrentUser() actor: { sub: string; tenantId: string },
    @Body() body: ConfigureMerchantPayoutDto,
  ) {
    return this.payments.configureAccount(actor, body);
  }

  @Post('mpesa')
  @UseGuards(SubscriptionGuard, PermissionsGuard)
  @RequirePermissions('sales.create')
  startMpesa(
    @CurrentUser() actor: { sub: string; tenantId: string },
    @Body() body: StartMerchantMpesaDto,
  ) {
    return this.payments.startMpesa(actor, body);
  }

  @Get('mpesa/:reference')
  status(
    @CurrentUser() actor: { sub: string; tenantId: string },
    @Param('reference') reference: string,
  ) {
    return this.payments.status(actor, reference);
  }
}
