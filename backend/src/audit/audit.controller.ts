import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { AuditService } from './audit.service';
import { AuditLogQueryDto, PaginatedAuditLogDto } from './dto/audit.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@ApiTags('audit')
@Controller({ path: 'audit-log', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class AuditController {
  constructor(private readonly auditService: AuditService) {}

  @Get()
  @UseGuards(PermissionsGuard)
  @RequirePermissions('audit.read')
  @ApiOperation({ summary: 'List audit log entries for the current tenant' })
  @ApiResponse({ status: 200, description: 'Paginated audit log entries', type: PaginatedAuditLogDto })
  async findAll(
    @CurrentUser('tenantId') tenantId: string,
    @Query() query: AuditLogQueryDto,
  ) {
    return this.auditService.findAll(tenantId, query);
  }
}
