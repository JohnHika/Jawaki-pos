import { Body, Controller, Delete, Get, Param, Post, Query, Request, UseGuards } from '@nestjs/common';
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

  @Get()
  @ApiOperation({ summary: 'List the current user notification inbox (newest first)' })
  async list(
    @Request() req: any,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    const data = await this.notificationsService.list(
      req.user.sub,
      limit ? Number(limit) : 50,
      before,
    );
    return { success: true, data };
  }

  // Declared before ':id/read' so the literal route is never shadowed.
  @Post('read-all')
  @ApiOperation({ summary: 'Mark all of the current user notifications as read' })
  async readAll(@Request() req: any) {
    await this.notificationsService.markAllRead(req.user.sub);
    return { success: true };
  }

  @Post(':id/read')
  @ApiOperation({ summary: 'Mark one notification as read' })
  async markRead(@Request() req: any, @Param('id') id: string) {
    await this.notificationsService.markRead(req.user.sub, id);
    return { success: true };
  }
}
