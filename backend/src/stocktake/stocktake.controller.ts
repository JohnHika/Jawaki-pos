import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { StocktakeService } from './stocktake.service';
import {
  ApproveStockCountDto,
  RecordCountsDto,
  StartStockCountDto,
  StockCountQueryDto,
} from './dto/stocktake.dto';

@ApiTags('stocktake')
@Controller({ path: 'stocktake', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
@ApiBearerAuth('JWT-auth')
export class StocktakeController {
  constructor(private readonly stocktake: StocktakeService) {}

  @Get()
  @RequirePermissions('inventory.stocktake.view')
  @ApiOperation({ summary: 'List stock counts' })
  list(@CurrentUser('tenantId') tenantId: string, @Query() query: StockCountQueryDto) {
    return this.stocktake.list(tenantId, query);
  }

  @Post()
  @RequirePermissions('inventory.stocktake.create')
  @ApiOperation({ summary: 'Start a count of the shelf (snapshots the system quantities)' })
  start(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: StartStockCountDto,
  ) {
    return this.stocktake.start(userId, tenantId, dto);
  }

  @Get(':id')
  @RequirePermissions('inventory.stocktake.view')
  @ApiOperation({ summary: 'A count with its lines (system quantities hidden while a blind count is open)' })
  get(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.stocktake.get(userId, tenantId, id);
  }

  @Get(':id/report')
  @RequirePermissions('inventory.stocktake.approve')
  @ApiOperation({ summary: 'Biggest losses and who counted what' })
  report(@CurrentUser('tenantId') tenantId: string, @Param('id', ParseUUIDPipe) id: string) {
    return this.stocktake.report(tenantId, id);
  }

  @Post(':id/counts')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('inventory.stocktake.count')
  @ApiOperation({ summary: 'Record what was found on the shelf' })
  record(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RecordCountsDto,
  ) {
    return this.stocktake.recordCounts(userId, tenantId, id, dto);
  }

  @Post(':id/submit')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('inventory.stocktake.count')
  @ApiOperation({ summary: 'Hand the count in for approval' })
  submit(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.stocktake.submit(userId, tenantId, id);
  }

  @Post(':id/approve')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('inventory.stocktake.approve')
  @ApiOperation({ summary: 'Approve a count and adjust stock to match' })
  approve(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ApproveStockCountDto,
  ) {
    return this.stocktake.approve(userId, tenantId, id, dto?.notes);
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('inventory.stocktake.create')
  @ApiOperation({ summary: 'Abandon a count without changing any stock' })
  cancel(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.stocktake.cancel(userId, tenantId, id);
  }
}
