import {
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  Post,
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
  MarkInvoicePaidDto,
  ListTenantsQueryDto,
  ListInvoicesQueryDto,
} from './dto/platform-admin.dto';
import { PlatformAdminGuard } from './guards/platform-admin.guard';
import { PlatformAdminPublic } from './decorators/platform-admin-public.decorator';
import {
  PlatformAdminAuthService,
  PlatformAdminBootstrapService,
} from './platform-admin-auth.service';
import { PlatformAdminService } from './platform-admin.service';

@ApiTags('platform-admin')
@UseGuards(ThrottlerGuard, PlatformAdminGuard)
@Controller({ path: 'platform-admin', version: '1' })
export class PlatformAdminController {
  constructor(
    private readonly authService: PlatformAdminAuthService,
    private readonly adminService: PlatformAdminService,
  ) {}

  @Post('auth/login')
  @PlatformAdminPublic()
  @Throttle({ default: { ttl: 60000, limit: 10 } })
  @ApiOperation({ summary: 'Platform admin login (Jawaki staff only)' })
  async login(@Body() dto: PlatformAdminLoginDto) {
    return this.authService.login(dto.email, dto.password);
  }

  @Get('auth/me')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Current platform admin profile' })
  async me(@Req() req: any) {
    const admin = await this.authService.findById(req.platformAdmin.id);
    if (!admin) throw new NotFoundException('Platform admin account no longer exists');
    return admin;
  }

  @Get('dashboard')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Platform-wide metrics: tenants by status, MRR/ARR, failed payments, recent payments' })
  async dashboard() {
    return this.adminService.getDashboard();
  }

  @Get('tenants')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'List tenants with plan, status, period end, invoice counts' })
  async listTenants(@Query() query: ListTenantsQueryDto) {
    return this.adminService.listTenants(query);
  }

  @Get('tenants/:id')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Tenant detail: owner, counts, last 5 invoices, claims' })
  async getTenant(@Param('id') id: string) {
    return this.adminService.getTenantDetail(id);
  }

  @Post('tenants/:id/extend')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Push currentPeriodEnd forward (manual goodwill extension)' })
  async extendTenant(@Param('id') id: string, @Body() dto: ExtendTenantDto, @Req() req: any) {
    return this.adminService.extendTenant(id, dto.days, req.platformAdmin);
  }

  @Post('tenants/:id/suspend')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Set tenant subscriptionStatus to SUSPENDED' })
  async suspendTenant(@Param('id') id: string, @Req() req: any) {
    return this.adminService.setSuspended(id, req.platformAdmin);
  }

  @Post('tenants/:id/reactivate')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Set tenant subscriptionStatus back to ACTIVE' })
  async reactivateTenant(@Param('id') id: string, @Req() req: any) {
    return this.adminService.setReactivated(id, req.platformAdmin);
  }

  @Post('tenants/:id/credit')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Issue a goodwill credit (negative-amount PAID invoice, provider CREDIT)' })
  async creditTenant(@Param('id') id: string, @Body() dto: CreditTenantDto, @Req() req: any) {
    return this.adminService.creditTenant(id, dto.amountKes, dto.reason, req.platformAdmin);
  }

  @Get('invoices')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'List subscription invoices (filter by status/tenantId, paginated)' })
  async listInvoices(@Query() query: ListInvoicesQueryDto) {
    return this.adminService.listInvoices(query);
  }

  @Post('invoices/:id/mark-paid')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Manual reconciliation: mark a PENDING invoice PAID (mpesaCode optional)' })
  async markInvoicePaid(
    @Param('id') id: string,
    @Body() dto: MarkInvoicePaidDto,
    @Req() req: any,
  ) {
    return this.adminService.markInvoicePaid(id, dto.mpesaCode, req.platformAdmin);
  }
}