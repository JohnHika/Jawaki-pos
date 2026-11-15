import { Body, Controller, Get, HttpCode, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { ThrottlerGuard } from '@nestjs/throttler';
import { LayoutRequestDecisionDto } from '../branches/dto/layout-request.dto';
import { LayoutRequestsService } from '../branches/layout-requests.service';
import { contextFromRequest, PlatformAuditService } from './audit/platform-audit.service';
import { RequirePlatformPermission } from './decorators/platform-permission.decorator';
import { PlatformAdminGuard } from './guards/platform-admin.guard';

@ApiTags('platform-admin')
@UseGuards(ThrottlerGuard, PlatformAdminGuard)
@Controller({ path: 'platform-admin/layout-requests', version: '1' })
export class PlatformLayoutRequestsController {
  constructor(
    private readonly requests: LayoutRequestsService,
    private readonly audit: PlatformAuditService,
  ) {}

  @Get()
  @RequirePlatformPermission('tenants.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Business type change requests from shops (filter by status)' })
  async list(@Query('status') status?: string) {
    return { items: await this.requests.listForPlatform(status) };
  }

  @Post(':id/decision')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.manage')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Approve or decline a business type change request' })
  async decide(@Param('id') id: string, @Body() dto: LayoutRequestDecisionDto, @Req() req: any) {
    const actor = req.platformAdmin;
    const decided = await this.requests.decide(actor, id, dto.approve, dto.note);
    await this.audit.log({
      action: dto.approve ? 'LAYOUT_CHANGE_APPROVED' : 'LAYOUT_CHANGE_DECLINED',
      category: 'TENANT',
      actor,
      targetType: 'LayoutChangeRequest',
      targetId: decided.id,
      tenantId: decided.tenantId,
      summary: `${dto.approve ? 'Approved' : 'Declined'} business type change to ${decided.toProfileId}`,
      metadata: { fromProfileId: decided.fromProfileId, toProfileId: decided.toProfileId },
      ctx: contextFromRequest(req),
    });
    return decided;
  }
}
