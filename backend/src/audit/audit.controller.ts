import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { AuditService } from './audit.service';
import { AuditLogQueryDto, PaginatedAuditLogDto } from './dto/audit.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { UserRole } from '@prisma/client';

@ApiTags('audit')
@Controller({ path: 'audit-log', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class AuditController {
  constructor(private readonly auditService: AuditService) {}

  @Get()
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'List audit log entries for the current tenant' })
  @ApiResponse({ status: 200, description: 'Paginated audit log entries', type: PaginatedAuditLogDto })
  async findAll(
    @CurrentUser('tenantId') tenantId: string,
    @Query() query: AuditLogQueryDto,
  ) {
    return this.auditService.findAll(tenantId, query);
  }
}
