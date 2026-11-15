import { Body, Controller, Get, HttpCode, Param, Post, Request, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CreateLayoutRequestDto } from './dto/layout-request.dto';
import { LayoutRequestsService } from './layout-requests.service';

// Registered before BranchesController so "layout-requests" is never read as a branch id.
@ApiTags('branches')
@Controller({ path: 'branches/layout-requests', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
@RequirePermissions('branches.tenant.update')
@ApiBearerAuth('JWT-auth')
export class LayoutRequestsController {
  constructor(private readonly requests: LayoutRequestsService) {}

  @Post()
  @ApiOperation({ summary: 'Ask to change the shop’s business type, with a reason' })
  create(@Request() req: any, @Body() dto: CreateLayoutRequestDto) {
    return this.requests.create(req.user.tenantId, req.user.sub, dto);
  }

  @Get()
  @ApiOperation({ summary: 'This shop’s business type change requests, newest first' })
  list(@Request() req: any) {
    return this.requests.listForTenant(req.user.tenantId);
  }

  @Post(':id/cancel')
  @HttpCode(200)
  @ApiOperation({ summary: 'Withdraw a request that is still waiting' })
  cancel(@Request() req: any, @Param('id') id: string) {
    return this.requests.cancel(req.user.tenantId, id);
  }
}
