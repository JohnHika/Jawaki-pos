import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  HttpCode,
  NotFoundException,
  Param,
  Post,
  Put,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import {
  PlatformAdminLoginDto,
  ExtendTenantDto,
  CreditTenantDto,
  ListTenantsQueryDto,
  ListInvoicesQueryDto,
  UpdateTenantLicenseDto,
} from './dto/platform-admin.dto';
import {
  ChangePasswordDto,
  DisableTwoFactorDto,
  EnableTwoFactorDto,
  RefreshTokenDto,
} from './dto/platform-staff.dto';
import { PlatformAdminGuard } from './guards/platform-admin.guard';
import { PlatformAdminPublic } from './decorators/platform-admin-public.decorator';
import {
  AllowPasswordChange,
  PlatformAuthenticated,
  RequirePlatformPermission,
} from './decorators/platform-permission.decorator';
import { PlatformAdminAuthService } from './platform-admin-auth.service';
import { PlatformAdminService } from './platform-admin.service';
import { PlatformAuditService, contextFromRequest } from './audit/platform-audit.service';

@ApiTags('platform-admin')
@UseGuards(ThrottlerGuard, PlatformAdminGuard)
@Controller({ path: 'platform-admin', version: '1' })
export class PlatformAdminController {
  constructor(
    private readonly authService: PlatformAdminAuthService,
    private readonly adminService: PlatformAdminService,
    private readonly audit: PlatformAuditService,
  ) {}

  // ------------------------------------------------------------------ auth

  @Post('auth/login')
  @PlatformAdminPublic()
  @HttpCode(200)
  @Throttle({ default: { ttl: 60000, limit: 10 } })
  @ApiOperation({ summary: 'Staff sign-in (password, then authenticator code when enabled)' })
  async login(
    @Body() dto: PlatformAdminLoginDto,
    @Req() req: any,
    @Headers('x-aca-device') device?: string,
  ) {
    return this.authService.login(dto, { ...contextFromRequest(req), device });
  }

  @Post('auth/refresh')
  @PlatformAdminPublic()
  @HttpCode(200)
  @Throttle({ default: { ttl: 60000, limit: 30 } })
  @ApiOperation({ summary: 'Rotate the refresh token and get a new access token' })
  async refresh(@Body() dto: RefreshTokenDto, @Req() req: any) {
    return this.authService.refresh(dto.refreshToken, contextFromRequest(req));
  }

  @Post('auth/logout')
  @HttpCode(200)
  @PlatformAuthenticated()
  @AllowPasswordChange()
  @ApiBearerAuth('JWT-auth')
  async logout(@Req() req: any) {
    return this.authService.logout(req.platformAdmin, contextFromRequest(req));
  }

  @Get('auth/me')
  @PlatformAuthenticated()
  @AllowPasswordChange()
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Current staff profile, role and permissions' })
  async me(@Req() req: any) {
    const admin = await this.authService.findById(req.platformAdmin.id);
    if (!admin) throw new NotFoundException('Platform admin account no longer exists');
    return admin;
  }

  @Post('auth/change-password')
  @HttpCode(200)
  @PlatformAuthenticated()
  @AllowPasswordChange()
  @Throttle({ default: { ttl: 60000, limit: 5 } })
  @ApiBearerAuth('JWT-auth')
  async changePassword(@Body() dto: ChangePasswordDto, @Req() req: any) {
    return this.authService.changePassword(req.platformAdmin, dto, contextFromRequest(req));
  }

  @Get('auth/sessions')
  @PlatformAuthenticated()
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Devices currently signed in to your account' })
  async sessions(@Req() req: any) {
    return {
      items: await this.authService.listSessions(req.platformAdmin.id, req.platformAdmin.sessionId),
    };
  }

  @Post('auth/sessions/revoke-others')
  @HttpCode(200)
  @PlatformAuthenticated()
  @ApiBearerAuth('JWT-auth')
  async revokeOtherSessions(@Req() req: any) {
    return this.authService.revokeOtherSessions(req.platformAdmin, contextFromRequest(req));
  }

  @Delete('auth/sessions/:sessionId')
  @PlatformAuthenticated()
  @ApiBearerAuth('JWT-auth')
  async revokeSession(@Param('sessionId') sessionId: string, @Req() req: any) {
    return this.authService.revokeSession(req.platformAdmin, sessionId, contextFromRequest(req));
  }

  @Post('auth/2fa/setup')
  @HttpCode(200)
  @PlatformAuthenticated()
  @Throttle({ default: { ttl: 60000, limit: 5 } })
  @ApiBearerAuth('JWT-auth')
  async twoFactorSetup(@Req() req: any) {
    return this.authService.startTwoFactorSetup(req.platformAdmin);
  }

  @Post('auth/2fa/enable')
  @HttpCode(200)
  @PlatformAuthenticated()
  @Throttle({ default: { ttl: 60000, limit: 10 } })
  @ApiBearerAuth('JWT-auth')
  async twoFactorEnable(@Body() dto: EnableTwoFactorDto, @Req() req: any) {
    return this.authService.enableTwoFactor(req.platformAdmin, dto.code, contextFromRequest(req));
  }

  @Post('auth/2fa/disable')
  @HttpCode(200)
  @PlatformAuthenticated()
  @Throttle({ default: { ttl: 60000, limit: 5 } })
  @ApiBearerAuth('JWT-auth')
  async twoFactorDisable(@Body() dto: DisableTwoFactorDto, @Req() req: any) {
    return this.authService.disableTwoFactor(req.platformAdmin, dto, contextFromRequest(req));
  }

  // -------------------------------------------------------------- overview

  @Get('overview')
  @RequirePlatformPermission('dashboard.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Home screen: companies, revenue, attention list and fleet' })
  async overview() {
    return this.adminService.getOverview();
  }

  @Get('dashboard')
  @RequirePlatformPermission('dashboard.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Platform-wide metrics: tenants by status, MRR/ARR, failed payments, recent payments' })
  async dashboard() {
    return this.adminService.getDashboard();
  }

  // --------------------------------------------------------------- tenants

  @Get('tenants')
  @RequirePlatformPermission('tenants.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'List tenants with plan, status, period end, invoice counts' })
  async listTenants(@Query() query: ListTenantsQueryDto) {
    return this.adminService.listTenants(query);
  }

  @Get('tenants/:id')
  @RequirePlatformPermission('tenants.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Tenant detail: owner, counts, last 5 invoices, claims' })
  async getTenant(@Param('id') id: string) {
    return this.adminService.getTenantDetail(id);
  }

  @Post('tenants/:id/extend')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.manage')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Push currentPeriodEnd forward (manual goodwill extension)' })
  async extendTenant(@Param('id') id: string, @Body() dto: ExtendTenantDto, @Req() req: any) {
    const result = await this.adminService.extendTenant(id, dto.days, req.platformAdmin);
    await this.audit.log({
      action: 'TENANT_EXTENDED',
      category: 'TENANT',
      severity: 'INFO',
      actor: req.platformAdmin,
      targetType: 'Tenant',
      targetId: id,
      tenantId: id,
      summary: `${req.platformAdmin.email} extended a company by ${dto.days} day(s)`,
      metadata: { days: dto.days, newPeriodEnd: result.currentPeriodEnd },
      ctx: contextFromRequest(req),
    });
    return result;
  }

  @Post('tenants/:id/suspend')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.suspend')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Set tenant subscriptionStatus to SUSPENDED' })
  async suspendTenant(@Param('id') id: string, @Req() req: any) {
    const result = await this.adminService.setSuspended(id, req.platformAdmin);
    await this.audit.log({
      action: 'TENANT_SUSPENDED',
      category: 'TENANT',
      severity: 'WARN',
      actor: req.platformAdmin,
      targetType: 'Tenant',
      targetId: id,
      tenantId: id,
      summary: `${req.platformAdmin.email} suspended a company`,
      ctx: contextFromRequest(req),
    });
    return result;
  }

  @Post('tenants/:id/reactivate')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.suspend')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Set tenant subscriptionStatus back to ACTIVE' })
  async reactivateTenant(@Param('id') id: string, @Req() req: any) {
    const result = await this.adminService.setReactivated(id, req.platformAdmin);
    await this.audit.log({
      action: 'TENANT_REACTIVATED',
      category: 'TENANT',
      severity: 'INFO',
      actor: req.platformAdmin,
      targetType: 'Tenant',
      targetId: id,
      tenantId: id,
      summary: `${req.platformAdmin.email} reactivated a company`,
      ctx: contextFromRequest(req),
    });
    return result;
  }

  @Post('tenants/:id/credit')
  @HttpCode(200)
  @RequirePlatformPermission('billing.manage')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Issue a goodwill credit (negative-amount PAID invoice, provider CREDIT)' })
  async creditTenant(@Param('id') id: string, @Body() dto: CreditTenantDto, @Req() req: any) {
    const invoice = await this.adminService.creditTenant(id, dto.amountKes, dto.reason, req.platformAdmin);
    await this.audit.log({
      action: 'BILLING_CREDIT_ISSUED',
      category: 'BILLING',
      severity: 'WARN',
      actor: req.platformAdmin,
      targetType: 'SubscriptionInvoice',
      targetId: invoice.id,
      tenantId: id,
      summary: `${req.platformAdmin.email} credited KES ${dto.amountKes} — ${dto.reason}`,
      metadata: { amountKes: dto.amountKes, reason: dto.reason },
      ctx: contextFromRequest(req),
    });
    return invoice;
  }

  // -------------------------------------------------------------- licences

  @Get('licenses/preview')
  @RequirePlatformPermission('tenants.license')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({
    summary: 'Dry run: for every company, what switching licence enforcement on would lock today',
  })
  async previewLicenses() {
    return this.adminService.previewLicenses();
  }

  @Get('tenants/:id/license')
  @RequirePlatformPermission('tenants.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'A company’s licence: plan, enforcement, overrides, limits, key' })
  async getTenantLicense(@Param('id') id: string) {
    return this.adminService.getTenantLicense(id);
  }

  @Put('tenants/:id/license')
  @RequirePlatformPermission('tenants.license')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({
    summary: 'Set a company’s licence: enforcement mode, module overrides, expiry, seat limits',
  })
  async updateTenantLicense(
    @Param('id') id: string,
    @Body() dto: UpdateTenantLicenseDto,
    @Req() req: any,
  ) {
    const result = await this.adminService.updateTenantLicense(id, dto, req.platformAdmin);
    await this.audit.log({
      action: 'LICENSE_UPDATED',
      category: 'LICENSE',
      severity: dto.enforcement === 'enforce' ? 'WARN' : 'INFO',
      actor: req.platformAdmin,
      targetType: 'Tenant',
      targetId: id,
      tenantId: id,
      summary: `${req.platformAdmin.email} changed a company's licence`,
      metadata: { ...dto, reissueKey: !!dto.reissueKey },
      ctx: contextFromRequest(req),
    });
    return result;
  }

  // --------------------------------------------------------------- billing

  @Get('invoices')
  @RequirePlatformPermission('billing.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'List subscription invoices (filter by status/tenantId, paginated)' })
  async listInvoices(@Query() query: ListInvoicesQueryDto) {
    return this.adminService.listInvoices(query);
  }

}
