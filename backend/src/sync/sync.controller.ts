import {
  Controller,
  Post,
  Get,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiResponse } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { SyncService } from './sync.service';
import {
  PushSyncEventsDto,
  PushSyncResponseDto,
  PullSyncRequestDto,
  PullSyncResponseDto,
  SyncStatusDto,
  ConflictResolutionDto,
  SyncResultDto,
} from './dto/sync.dto';

@ApiTags('Sync')
@ApiBearerAuth()
@Controller('sync')
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class SyncController {
  constructor(private syncService: SyncService) {}

  @Post('push')
  @RequirePermissions('sync.push')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Push offline events to server' })
  @ApiResponse({ status: 200, type: PushSyncResponseDto })
  async pushEvents(
    @CurrentUser() user: any,
    @Body() dto: PushSyncEventsDto,
  ): Promise<PushSyncResponseDto> {
    return this.syncService.pushEvents(user.deviceId, user.branchId, dto);
  }

  @Post('pull')
  @RequirePermissions('sync.pull')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Pull server changes for offline sync' })
  @ApiResponse({ status: 200, type: PullSyncResponseDto })
  async pullEvents(
    @CurrentUser() user: any,
    @Body() dto: PullSyncRequestDto,
  ): Promise<PullSyncResponseDto> {
    return this.syncService.pullEvents(user.deviceId, user.branchId, dto);
  }

  @Get('status')
  @RequirePermissions('sync.status')
  @ApiOperation({ summary: 'Get sync status for current device' })
  @ApiResponse({ status: 200, type: SyncStatusDto })
  async getSyncStatus(@CurrentUser() user: any): Promise<SyncStatusDto> {
    return this.syncService.getSyncStatus(user.deviceId);
  }

  @Post('heartbeat')
  @RequirePermissions('sync.status')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Register device heartbeat' })
  async heartbeat(@CurrentUser() user: any): Promise<void> {
    await this.syncService.registerHeartbeat(user.deviceId);
  }

  @Post('conflicts/resolve')
  @RequirePermissions('sync.resolve_conflicts')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Resolve sync conflicts' })
  @ApiResponse({ status: 200, type: [SyncResultDto] })
  async resolveConflicts(
    @CurrentUser() user: any,
    @Body() conflicts: ConflictResolutionDto[],
  ): Promise<SyncResultDto[]> {
    return this.syncService.resolveConflict(user.deviceId, conflicts);
  }

  @Get('failed')
  @RequirePermissions('sync.push')
  @ApiOperation({ summary: 'Get failed sync events for retry' })
  async getFailedEvents(@CurrentUser() user: any): Promise<any[]> {
    return this.syncService.getFailedEvents(user.deviceId);
  }

  @Post('retry')
  @RequirePermissions('sync.push')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Retry failed sync events' })
  @ApiResponse({ status: 200, type: PushSyncResponseDto })
  async retryFailedEvents(@CurrentUser() user: any): Promise<PushSyncResponseDto> {
    return this.syncService.retryFailedEvents(user.deviceId, user.branchId);
  }
}
