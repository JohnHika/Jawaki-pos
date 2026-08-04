import {
  Body,
  Controller,
  Get,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { SubscriptionService } from './subscription.service';

@ApiTags('subscription')
@Controller({ path: 'subscription', version: '1' })
export class SubscriptionController {
  constructor(private readonly subscriptionService: SubscriptionService) {}

  @Get('plan')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Get the current subscription plan and status' })
  getPlan(@Req() req: any) {
    return this.subscriptionService.getCurrentPlan(req.user.tenantId);
  }

  @Post('change-plan')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Change the subscription plan (TRIAL/CORE/ENTERPRISE)' })
  changePlan(@Req() req: any, @Body('plan') plan: string) {
    return this.subscriptionService.changePlan(req.user.tenantId, plan);
  }

  @Get('invoices')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'List subscription invoices for this company' })
  listInvoices(@Req() req: any) {
    return this.subscriptionService.listInvoices(req.user.tenantId);
  }
}
