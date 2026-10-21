import { Body, Controller, Delete, Get, HttpCode, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { ThrottlerGuard } from '@nestjs/throttler';
import { RequirePlatformPermission } from './decorators/platform-permission.decorator';
import { AddTenantNoteDto, ReasonDto } from './dto/platform-staff.dto';
import { PlatformAdminGuard } from './guards/platform-admin.guard';
import { contextFromRequest } from './audit/platform-audit.service';
import { PlatformTenantSupportService } from './platform-tenant-support.service';

@ApiTags('platform-admin')
@UseGuards(ThrottlerGuard, PlatformAdminGuard)
@Controller({ path: 'platform-admin/tenants/:tenantId', version: '1' })
export class PlatformTenantSupportController {
  constructor(private readonly support: PlatformTenantSupportService) {}

  @Get('users')
  @RequirePlatformPermission('tenants.users')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'A company’s staff accounts with status and active sessions' })
  users(@Param('tenantId') tenantId: string) {
    return this.support.listUsers(tenantId);
  }

  @Post('users/:userId/deactivate')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.security')
  @ApiBearerAuth('JWT-auth')
  deactivate(@Param('tenantId') tenantId: string, @Param('userId') userId: string, @Req() req: any) {
    return this.support.setUserActive(req.platformAdmin, tenantId, userId, false, contextFromRequest(req));
  }

  @Post('users/:userId/activate')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.security')
  @ApiBearerAuth('JWT-auth')
  activate(@Param('tenantId') tenantId: string, @Param('userId') userId: string, @Req() req: any) {
    return this.support.setUserActive(req.platformAdmin, tenantId, userId, true, contextFromRequest(req));
  }

  @Post('users/:userId/revoke-sessions')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.security')
  @ApiBearerAuth('JWT-auth')
  revokeUser(@Param('tenantId') tenantId: string, @Param('userId') userId: string, @Req() req: any) {
    return this.support.revokeUserSessions(req.platformAdmin, tenantId, userId, contextFromRequest(req));
  }

  @Post('force-logout')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.security')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Sign every user of this company out on all devices' })
  forceLogout(@Param('tenantId') tenantId: string, @Req() req: any) {
    return this.support.forceLogout(req.platformAdmin, tenantId, contextFromRequest(req));
  }

  @Post('lockout')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.security')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Emergency kill switch: block all sign-ins for this company' })
  lock(@Param('tenantId') tenantId: string, @Body() dto: ReasonDto, @Req() req: any) {
    return this.support.setLockout(req.platformAdmin, tenantId, true, dto.reason, contextFromRequest(req));
  }

  @Post('lockout/lift')
  @HttpCode(200)
  @RequirePlatformPermission('tenants.security')
  @ApiBearerAuth('JWT-auth')
  unlock(@Param('tenantId') tenantId: string, @Body() dto: ReasonDto, @Req() req: any) {
    return this.support.setLockout(req.platformAdmin, tenantId, false, dto.reason, contextFromRequest(req));
  }

  @Get('devices')
  @RequirePlatformPermission('tenants.users')
  @ApiBearerAuth('JWT-auth')
  devices(@Param('tenantId') tenantId: string) {
    return this.support.listDevices(tenantId);
  }

  @Get('notes')
  @RequirePlatformPermission('tenants.view')
  @ApiBearerAuth('JWT-auth')
  notes(@Param('tenantId') tenantId: string) {
    return this.support.listNotes(tenantId);
  }

  @Post('notes')
  @HttpCode(201)
  @RequirePlatformPermission('tenants.manage')
  @ApiBearerAuth('JWT-auth')
  addNote(@Param('tenantId') tenantId: string, @Body() dto: AddTenantNoteDto, @Req() req: any) {
    return this.support.addNote(req.platformAdmin, tenantId, dto.body, !!dto.pinned, contextFromRequest(req));
  }

  @Delete('notes/:noteId')
  @RequirePlatformPermission('tenants.manage')
  @ApiBearerAuth('JWT-auth')
  deleteNote(@Param('tenantId') tenantId: string, @Param('noteId') noteId: string, @Req() req: any) {
    return this.support.deleteNote(req.platformAdmin, tenantId, noteId, contextFromRequest(req));
  }
}
