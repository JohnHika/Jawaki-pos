import { Controller, Get, Post, Delete, Body, Param, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { UsersManagementService } from './users-management.service';
import { AssignRoleDto, CreatePermissionOverrideDto } from './dto/user-management.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

interface RequestUser {
  sub: string;
  tenantId: string;
}

@ApiTags('users')
@Controller({ path: 'users', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
@ApiBearerAuth('JWT-auth')
export class UsersManagementController {
  constructor(private readonly usersManagementService: UsersManagementService) {}

  @Get()
  @RequirePermissions('users.view')
  @ApiOperation({ summary: 'List tenant users with their assigned roles' })
  async findAll(@CurrentUser() user: RequestUser) {
    return this.usersManagementService.findAll(user.tenantId);
  }

  @Get(':id/permissions')
  @RequirePermissions('users.view')
  @ApiOperation({ summary: "Breakdown of a user's permissions: from roles, granted, revoked, effective" })
  async getPermissions(@CurrentUser() user: RequestUser, @Param('id') id: string) {
    return this.usersManagementService.getPermissionBreakdown(user.tenantId, id);
  }

  @Get('offline-directory')
  @RequirePermissions('users.view')
  @ApiOperation({
    summary: 'Directory of users with an offline-access PIN set, for phone-server-mode sync',
    description:
      'Pulled once while online by a device about to act as a local server. Includes each user\'s effective permissions and offline-access PIN hash (never the online login PIN/password) so other devices can authenticate against it fully offline.',
  })
  async getOfflineDirectory(@CurrentUser() user: RequestUser) {
    return this.usersManagementService.getOfflineDirectory(user.tenantId);
  }

  @Post(':id/roles')
  @RequirePermissions('permissions.assign_role')
  @ApiOperation({ summary: 'Assign a role to a user (a user may hold multiple roles)' })
  async assignRole(
    @CurrentUser() user: RequestUser,
    @Param('id') id: string,
    @Body() dto: AssignRoleDto,
  ) {
    return this.usersManagementService.assignRole(user.tenantId, id, dto, user.sub);
  }

  @Delete(':id/roles/:roleId')
  @RequirePermissions('permissions.assign_role')
  @ApiOperation({ summary: 'Remove a role from a user' })
  async removeRole(
    @CurrentUser() user: RequestUser,
    @Param('id') id: string,
    @Param('roleId') roleId: string,
  ) {
    return this.usersManagementService.removeRole(user.tenantId, id, roleId, user.sub);
  }

  @Post(':id/permission-overrides')
  @RequirePermissions('permissions.override_user')
  @ApiOperation({ summary: 'Grant or revoke an individual permission for a user, overriding their roles' })
  async setOverride(
    @CurrentUser() user: RequestUser,
    @Param('id') id: string,
    @Body() dto: CreatePermissionOverrideDto,
  ) {
    return this.usersManagementService.setPermissionOverride(user.tenantId, id, dto, user.sub);
  }

  @Delete(':id/permission-overrides/:permissionKey')
  @RequirePermissions('permissions.override_user')
  @ApiOperation({ summary: 'Clear a permission override, reverting the user to their role-derived access' })
  async clearOverride(
    @CurrentUser() user: RequestUser,
    @Param('id') id: string,
    @Param('permissionKey') permissionKey: string,
  ) {
    return this.usersManagementService.clearPermissionOverride(user.tenantId, id, permissionKey, user.sub);
  }
}
