import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  UseGuards,
  Request,
  ParseUUIDPipe,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { DailyCloseService } from './daily-close.service';
import { CloseDayDto } from './dto/daily-close.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';

@ApiTags('daily-close')
@Controller({ path: 'sales/daily-close', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class DailyCloseController {
  constructor(private readonly dailyCloseService: DailyCloseService) {}

  @Post(':branchId')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('sales.close_end_of_day')
  @ApiOperation({ summary: 'Close the end of day for a branch (Z-report + cash count)' })
  @ApiResponse({ status: 201, description: 'Day closed' })
  async closeDay(
    @Param('branchId', ParseUUIDPipe) branchId: string,
    @Request() req: any,
    @Body() dto: CloseDayDto,
  ) {
    return this.dailyCloseService.closeDay(req.user.sub, req.user.tenantId, branchId, dto);
  }

  @Get(':branchId')
  @ApiOperation({ summary: "Get a branch's close for a day (or today); null if not yet closed" })
  @ApiResponse({ status: 200, description: 'Daily close or null' })
  async getClose(
    @Param('branchId', ParseUUIDPipe) branchId: string,
    @Request() req: any,
    @Query('date') date?: string,
  ) {
    return this.dailyCloseService.getClose(req.user.tenantId, branchId, date);
  }

  @Get(':branchId/history')
  @ApiOperation({ summary: 'Recent daily closes for a branch' })
  @ApiResponse({ status: 200, description: 'Daily close history' })
  async getHistory(
    @Param('branchId', ParseUUIDPipe) branchId: string,
    @Request() req: any,
    @Query('limit') limit?: string,
  ) {
    return this.dailyCloseService.getHistory(
      req.user.tenantId,
      branchId,
      limit ? parseInt(limit, 10) : 30,
    );
  }
}
