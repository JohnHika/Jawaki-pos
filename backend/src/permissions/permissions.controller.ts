import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { PermissionsService } from './permissions.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@ApiTags('permissions')
@Controller({ path: 'permissions', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class PermissionsController {
  constructor(private readonly permissionsService: PermissionsService) {}

  @Get()
  @UseGuards(PermissionsGuard)
  @RequirePermissions('permissions.view_catalog')
  @ApiOperation({ summary: 'Full permission catalog, grouped by feature' })
  async getCatalog() {
    return this.permissionsService.getCatalog();
  }

  @Get('me')
  @ApiOperation({ summary: "Current user's effective permissions (for mid-session refresh)" })
  async getMyPermissions(@CurrentUser() user: { sub: string }) {
    const permissions = await this.permissionsService.getEffectivePermissions(user.sub);
    return { permissions };
  }
}
