import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AccountabilityService } from './accountability.service';
import { AccountabilitySummaryService } from './accountability-summary.service';
import {
  AcknowledgeAlertsDto,
  AlertsQueryDto,
  UpdateAccountabilitySettingsDto,
} from './dto/accountability.dto';

@ApiTags('accountability')
@Controller({ path: 'accountability', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class AccountabilityController {
  constructor(
    private readonly accountability: AccountabilityService,
    private readonly summaries: AccountabilitySummaryService,
  ) {}

  @Get('till-rules')
  @ApiOperation({
    summary: 'Rules, this user\'s overrides and per-product price floors, for the till to apply offline',
  })
  tillRules(@CurrentUser('tenantId') tenantId: string, @CurrentUser('id') userId: string) {
    return this.accountability.tillRules(tenantId, userId);
  }

  @Get('settings')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('accountability.view')
  @ApiOperation({ summary: 'Price, discount, credit and alert rules for this company' })
  getSettings(@CurrentUser('tenantId') tenantId: string) {
    return this.accountability.getSettings(tenantId);
  }

  @Put('settings')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('accountability.manage')
  @ApiOperation({ summary: 'Change the accountability rules (owner only)' })
  updateSettings(
    @CurrentUser('tenantId') tenantId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: UpdateAccountabilitySettingsDto,
  ) {
    return this.accountability.updateSettings(tenantId, userId, dto as Record<string, any>);
  }

  @Get('alerts')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('accountability.view')
  @ApiOperation({ summary: 'Feed of things that need the owner\'s attention' })
  listAlerts(@CurrentUser('tenantId') tenantId: string, @Query() query: AlertsQueryDto) {
    return this.accountability.list(tenantId, query);
  }

  @Post('alerts/acknowledge')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('accountability.view')
  @ApiOperation({ summary: 'Mark alerts as seen' })
  acknowledge(
    @CurrentUser('tenantId') tenantId: string,
    @CurrentUser('id') userId: string,
    @Body() dto: AcknowledgeAlertsDto,
  ) {
    if (!dto.all && (!dto.ids || dto.ids.length === 0)) {
      throw new BadRequestException('Send ids, or all=true');
    }
    return this.accountability.acknowledge(tenantId, userId, dto.all ? 'all' : dto.ids!);
  }

  @Get('summary')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('accountability.view')
  @ApiOperation({ summary: 'Today (or a given day) at a branch, as the owner would read it' })
  async summary(
    @CurrentUser('tenantId') tenantId: string,
    @Query('branchId') branchId: string,
    @Query('date') date?: string,
  ) {
    if (!branchId) throw new BadRequestException('branchId is required');
    if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      throw new BadRequestException('date must be YYYY-MM-DD');
    }
    const summary = await this.summaries.buildBranchSummary(tenantId, branchId, date);
    return { ...summary, text: this.summaries.formatSummary(summary) };
  }
}
