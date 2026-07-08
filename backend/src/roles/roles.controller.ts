import { Controller, Get, Post, Patch, Delete, Body, Param, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { RolesService } from './roles.service';
import { CreateRoleDto, UpdateRoleDto } from './dto/role.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

interface RequestUser {
  sub: string;
  tenantId: string;
}

@ApiTags('roles')
@Controller({ path: 'roles', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
@ApiBearerAuth('JWT-auth')
export class RolesController {
  constructor(private readonly rolesService: RolesService) {}

  @Get()
  @RequirePermissions('roles.view')
  @ApiOperation({ summary: 'List roles for the current tenant' })
  async findAll(@CurrentUser() user: RequestUser) {
    return this.rolesService.findAll(user.tenantId);
  }

  @Get(':id')
  @RequirePermissions('roles.view')
  @ApiOperation({ summary: 'Get a role by ID, including its permission set' })
  async findOne(@CurrentUser() user: RequestUser, @Param('id') id: string) {
    return this.rolesService.findOne(user.tenantId, id);
  }

  @Post()
  @RequirePermissions('roles.create')
  @ApiOperation({ summary: 'Create a new role' })
  async create(@CurrentUser() user: RequestUser, @Body() dto: CreateRoleDto) {
    return this.rolesService.create(user.tenantId, dto, user.sub);
  }

  @Patch(':id')
  @RequirePermissions('roles.update')
  @ApiOperation({ summary: "Update a role's name/description/permission set" })
  async update(
    @CurrentUser() user: RequestUser,
    @Param('id') id: string,
    @Body() dto: UpdateRoleDto,
  ) {
    return this.rolesService.update(user.tenantId, id, dto, user.sub);
  }

  @Delete(':id')
  @RequirePermissions('roles.delete')
  @ApiOperation({ summary: 'Delete a role (must have zero assigned users)' })
  async remove(@CurrentUser() user: RequestUser, @Param('id') id: string) {
    return this.rolesService.remove(user.tenantId, id, user.sub);
  }
}
