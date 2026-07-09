import { Body, Controller, Delete, Post, Request, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { NotificationsService } from './notifications.service';
import { RegisterPushTokenDto, UnregisterPushTokenDto } from './dto/notifications.dto';

@ApiTags('notifications')
@Controller({ path: 'notifications', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Post('tokens')
  @ApiOperation({ summary: 'Register this device\'s push token for the current user' })
  async registerToken(@Request() req: any, @Body() dto: RegisterPushTokenDto) {
    await this.notificationsService.registerToken(
      req.user.sub,
      dto.token,
      dto.deviceUuid,
      dto.platform,
    );
    return { success: true };
  }

  @Delete('tokens')
  @ApiOperation({ summary: 'Unregister a push token (e.g. on logout)' })
  async unregisterToken(@Body() dto: UnregisterPushTokenDto) {
    await this.notificationsService.unregisterToken(dto.token);
    return { success: true };
  }
}
