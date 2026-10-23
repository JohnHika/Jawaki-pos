import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { LegacyUserRole } from '@prisma/client';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { AcceptPolicyDto } from './dto/accept-policy.dto';
import { LegalPolicyService } from './legal-policy.service';

@ApiTags('legal')
@ApiBearerAuth('JWT-auth')
@Controller({ path: 'legal', version: '1' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(LegacyUserRole.ADMIN)
export class LegalPolicyController {
  constructor(private readonly policies: LegalPolicyService) {}

  @Get('acceptances')
  @ApiOperation({ summary: 'List policy versions accepted by this workspace owner' })
  list(@Req() req: any) {
    return this.policies.listForOwner(req.user.tenantId, req.user.sub);
  }

  @Post('acceptances')
  @ApiOperation({ summary: 'Record an owner acceptance of the current policy version' })
  accept(@Req() req: any, @Body() dto: AcceptPolicyDto) {
    return this.policies.accept(
      req.user.tenantId,
      req.user.sub,
      dto.policyType,
      dto.policyVersion,
    );
  }
}
