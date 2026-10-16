import { Controller, Get, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { LicenseService } from './license.service';

@ApiTags('license')
@ApiBearerAuth('JWT-auth')
@UseGuards(JwtAuthGuard)
@Controller({ path: 'license', version: '1' })
export class LicenseController {
  constructor(private readonly license: LicenseService) {}

  @Get()
  @ApiOperation({
    summary:
      'This company’s licence: plan, which modules are unlocked, limits and expiry',
  })
  describe(@Req() req: any) {
    return this.license.describeForClient(req.user.tenantId);
  }
}
