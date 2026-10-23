import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { ImportsService } from './imports.service';
import {
  AddCostDto,
  AddParticipantDto,
  CreateShipmentDto,
  ReceiveShipmentDto,
  RecordImportPaymentDto,
  ShipmentItemDto,
  ShipmentQueryDto,
  UpdateShipmentDto,
} from './dto/imports.dto';

@ApiTags('imports')
@Controller({ path: 'imports', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
@ApiBearerAuth('JWT-auth')
export class ImportsController {
  constructor(private readonly imports: ImportsService) {}

  @Get()
  @RequirePermissions('imports.view')
  @ApiOperation({ summary: 'Containers and consignments, with what is still owed' })
  list(@CurrentUser('tenantId') tenantId: string, @Query() query: ShipmentQueryDto) {
    return this.imports.list(tenantId, query);
  }

  @Post()
  @RequirePermissions('imports.manage')
  @ApiOperation({ summary: 'Start a new container / consignment' })
  create(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: CreateShipmentDto,
  ) {
    return this.imports.create(userId, tenantId, dto);
  }

  @Get(':id')
  @RequirePermissions('imports.view')
  @ApiOperation({ summary: 'A shipment with landed cost per line and each trader\'s balance' })
  get(@CurrentUser('tenantId') tenantId: string, @Param('id', ParseUUIDPipe) id: string) {
    return this.imports.get(tenantId, id);
  }

  @Patch(':id')
  @RequirePermissions('imports.manage')
  @ApiOperation({ summary: 'Edit details, exchange rate, cost-spreading basis or status' })
  update(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateShipmentDto,
  ) {
    return this.imports.update(userId, tenantId, id, dto);
  }

  @Post(':id/participants')
  @RequirePermissions('imports.manage')
  @ApiOperation({ summary: 'Add another trader sharing this container' })
  addParticipant(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AddParticipantDto,
  ) {
    return this.imports.addParticipant(userId, tenantId, id, dto);
  }

  @Delete(':id/participants/:participantId')
  @RequirePermissions('imports.manage')
  removeParticipant(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('participantId', ParseUUIDPipe) participantId: string,
  ) {
    return this.imports.removeParticipant(userId, tenantId, id, participantId);
  }

  @Post(':id/items')
  @RequirePermissions('imports.manage')
  @ApiOperation({ summary: 'Add goods to the container' })
  addItem(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ShipmentItemDto,
  ) {
    return this.imports.addItem(userId, tenantId, id, dto);
  }

  @Patch(':id/items/:itemId')
  @RequirePermissions('imports.manage')
  updateItem(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('itemId', ParseUUIDPipe) itemId: string,
    @Body() dto: Partial<ShipmentItemDto>,
  ) {
    return this.imports.updateItem(userId, tenantId, id, itemId, dto);
  }

  @Delete(':id/items/:itemId')
  @RequirePermissions('imports.manage')
  removeItem(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('itemId', ParseUUIDPipe) itemId: string,
  ) {
    return this.imports.removeItem(userId, tenantId, id, itemId);
  }

  @Post(':id/costs')
  @RequirePermissions('imports.manage')
  @ApiOperation({ summary: 'Add freight, duty, clearing or any other cost' })
  addCost(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AddCostDto,
  ) {
    return this.imports.addCost(userId, tenantId, id, dto);
  }

  @Delete(':id/costs/:costId')
  @RequirePermissions('imports.manage')
  removeCost(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('costId', ParseUUIDPipe) costId: string,
  ) {
    return this.imports.removeCost(userId, tenantId, id, costId);
  }

  @Post(':id/payments')
  @RequirePermissions('imports.payments')
  @ApiOperation({ summary: 'Record money a trader handed over towards their share' })
  recordPayment(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RecordImportPaymentDto,
  ) {
    return this.imports.recordPayment(userId, tenantId, id, dto);
  }

  @Delete(':id/payments/:paymentId')
  @RequirePermissions('imports.payments')
  removePayment(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('paymentId', ParseUUIDPipe) paymentId: string,
  ) {
    return this.imports.removePayment(userId, tenantId, id, paymentId);
  }

  @Post(':id/receive')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions('imports.receive')
  @ApiOperation({ summary: 'Book the arrived goods into stock at landed cost' })
  receive(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReceiveShipmentDto,
  ) {
    return this.imports.receive(userId, tenantId, id, dto);
  }
}
