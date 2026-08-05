import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { TenantOnboardingService } from './tenant-onboarding.service';
import { AcceptStaffInvitationDto, CreateStaffInvitationDto, UpdateOnboardingStepDto } from './dto/tenant-onboarding.dto';

@ApiTags('tenant-onboarding')
@Controller({ path: 'tenant-onboarding', version: '1' })
export class TenantOnboardingController {
  constructor(private readonly service: TenantOnboardingService) {}

  @Get()
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  get(@CurrentUser() user: any) { return this.service.get(user); }

  @Patch('steps/:key')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  updateStep(@CurrentUser() user: any, @Param('key') key: string, @Body() dto: UpdateOnboardingStepDto) {
    return this.service.updateStep(user, key, dto.status);
  }

  @Get('staff-invitations')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  listInvitations(@CurrentUser() user: any) { return this.service.listInvitations(user); }

  @Post('staff-invitations')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  createInvitation(@CurrentUser() user: any, @Body() dto: CreateStaffInvitationDto) {
    return this.service.createInvitation(user, dto);
  }

  @Post('staff-invitations/:invitationId/accept')
  acceptInvitation(@Param('invitationId') invitationId: string, @Body() dto: AcceptStaffInvitationDto) {
    return this.service.acceptInvitation(invitationId, dto);
  }
}
