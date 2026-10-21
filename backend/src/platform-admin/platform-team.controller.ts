import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { ThrottlerGuard } from '@nestjs/throttler';
import { RequirePlatformPermission } from './decorators/platform-permission.decorator';
import { AuditQueryDto, CreateStaffDto, UpdateStaffDto } from './dto/platform-staff.dto';
import { PlatformAdminGuard } from './guards/platform-admin.guard';
import { PlatformAuditService, contextFromRequest } from './audit/platform-audit.service';
import { PlatformSecurityService } from './platform-security.service';
import { PlatformTeamService } from './platform-team.service';

@ApiTags('platform-admin')
@UseGuards(ThrottlerGuard, PlatformAdminGuard)
@Controller({ path: 'platform-admin/team', version: '1' })
export class PlatformTeamController {
  constructor(private readonly team: PlatformTeamService) {}

  @Get('roles')
  @RequirePlatformPermission('team.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Role catalog with permissions, and which roles you can assign' })
  roles(@Req() req: any) {
    return this.team.roleCatalog(req.platformAdmin.role);
  }

  @Get()
  @RequirePlatformPermission('team.view')
  @ApiBearerAuth('JWT-auth')
  list() {
    return this.team.list();
  }

  @Post()
  @HttpCode(201)
  @RequirePlatformPermission('team.manage')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Add a staff member; returns a one-time temporary password' })
  create(@Body() dto: CreateStaffDto, @Req() req: any) {
    return this.team.create(req.platformAdmin, dto, contextFromRequest(req));
  }

  @Get(':id')
  @RequirePlatformPermission('team.view')
  @ApiBearerAuth('JWT-auth')
  get(@Param('id') id: string) {
    return this.team.get(id);
  }

  @Patch(':id')
  @RequirePlatformPermission('team.manage')
  @ApiBearerAuth('JWT-auth')
  update(@Param('id') id: string, @Body() dto: UpdateStaffDto, @Req() req: any) {
    return this.team.update(req.platformAdmin, id, dto, contextFromRequest(req));
  }

  @Post(':id/reset-password')
  @HttpCode(200)
  @RequirePlatformPermission('team.manage')
  @ApiBearerAuth('JWT-auth')
  resetPassword(@Param('id') id: string, @Req() req: any) {
    return this.team.resetPassword(req.platformAdmin, id, contextFromRequest(req));
  }

  @Post(':id/unlock')
  @HttpCode(200)
  @RequirePlatformPermission('security.manage')
  @ApiBearerAuth('JWT-auth')
  unlock(@Param('id') id: string, @Req() req: any) {
    return this.team.unlock(req.platformAdmin, id, contextFromRequest(req));
  }

  @Get(':id/sessions')
  @RequirePlatformPermission('security.view')
  @ApiBearerAuth('JWT-auth')
  sessions(@Param('id') id: string) {
    return this.team.sessions(id);
  }

  @Post(':id/revoke-sessions')
  @HttpCode(200)
  @RequirePlatformPermission('security.manage')
  @ApiBearerAuth('JWT-auth')
  revokeSessions(@Param('id') id: string, @Req() req: any) {
    return this.team.revokeSessions(req.platformAdmin, id, contextFromRequest(req));
  }
}

@ApiTags('platform-admin')
@UseGuards(ThrottlerGuard, PlatformAdminGuard)
@Controller({ path: 'platform-admin', version: '1' })
export class PlatformSecurityController {
  constructor(
    private readonly security: PlatformSecurityService,
    private readonly audit: PlatformAuditService,
  ) {}

  @Get('security/overview')
  @RequirePlatformPermission('security.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Security centre: failed sign-ins, locked accounts, 2FA coverage, alerts' })
  overview() {
    return this.security.overview();
  }

  @Get('audit')
  @RequirePlatformPermission('audit.view')
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Attributed trail of everything staff did and every sign-in' })
  list(@Query() query: AuditQueryDto) {
    return this.audit.list(query);
  }
}
