import {
  Body,
  Controller,
  Get,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { LegacyUserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
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
  // Plan changes are a tenant-ownership decision (billing commitment), not a
  // staff capability: switching the plan changes limits (branches/users) and
  // pricing for the whole company. There is no `subscription.manage` key in
  // the seeded Permission catalog, so this follows the legacy-role pattern
  // (user.role from the JWT) instead of PermissionsGuard — only ADMIN may
  // change the plan.
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(LegacyUserRole.ADMIN)
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
