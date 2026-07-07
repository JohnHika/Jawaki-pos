import { IsString, IsUUID, IsEnum, IsObject, IsArray, ValidateNested, IsDateString, IsOptional, IsNumber } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export enum SyncEventType {
  SALE_CREATED = 'SALE_CREATED',
  SALE_VOIDED = 'SALE_VOIDED',
  REFUND_CREATED = 'REFUND_CREATED',
  STOCK_ADJUSTED = 'STOCK_ADJUSTED',
  STOCK_TRANSFER_CREATED = 'STOCK_TRANSFER_CREATED',
  PRODUCT_UPDATED = 'PRODUCT_UPDATED',
  CATEGORY_UPDATED = 'CATEGORY_UPDATED',
  PRICE_OVERRIDE_UPDATED = 'PRICE_OVERRIDE_UPDATED',
  USER_UPDATED = 'USER_UPDATED',
  SUPPLIER_INVOICE_CREATED = 'SUPPLIER_INVOICE_CREATED',
  SUPPLIER_PAYMENT_RECORDED = 'SUPPLIER_PAYMENT_RECORDED',
}

export class SyncEventDto {
  @ApiProperty({ description: 'Unique event ID generated offline' })
  @IsUUID()
  eventId: string;

  @ApiProperty({ enum: SyncEventType })
  @IsEnum(SyncEventType)
  eventType: SyncEventType;

  @ApiProperty({ description: 'Event payload data' })
  @IsObject()
  payload: Record<string, any>;

  @ApiProperty({ description: 'Device ID that generated the event' })
  @IsUUID()
  deviceId: string;

  @ApiProperty({ description: 'Timestamp when event was created offline' })
  @IsDateString()
  createdAt: string;

  @ApiPropertyOptional({ description: 'Sequence number for ordering' })
  @IsOptional()
  @IsNumber()
  sequenceNumber?: number;
}

export class PushSyncEventsDto {
  @ApiProperty({ type: [SyncEventDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SyncEventDto)
  events: SyncEventDto[];

  @ApiProperty({ description: 'Last known server timestamp' })
  @IsOptional()
  @IsDateString()
  lastSyncTimestamp?: string;
}

export class PullSyncRequestDto {
  @ApiProperty({ description: 'Last sync timestamp' })
  @IsOptional()
  @IsDateString()
  since?: string;

  @ApiPropertyOptional({ description: 'Event types to pull' })
  @IsOptional()
  @IsArray()
  @IsEnum(SyncEventType, { each: true })
  eventTypes?: SyncEventType[];

  @ApiPropertyOptional({ description: 'Maximum number of events to return' })
  @IsOptional()
  @IsNumber()
  limit?: number;
}

export class SyncResultDto {
  @ApiProperty()
  eventId: string;

  @ApiProperty()
  success: boolean;

  @ApiPropertyOptional()
  error?: string;

  @ApiPropertyOptional()
  serverId?: string;

  @ApiPropertyOptional()
  serverTimestamp?: Date;
}

export class PushSyncResponseDto {
  @ApiProperty({ type: [SyncResultDto] })
  results: SyncResultDto[];

  @ApiProperty({ description: 'Number of successfully processed events' })
  successCount: number;

  @ApiProperty({ description: 'Number of failed events' })
  failureCount: number;

  @ApiProperty({ description: 'Server timestamp for next sync' })
  serverTimestamp: Date;
}

export class PullSyncResponseDto {
  @ApiProperty({ type: [Object] })
  events: any[];

  @ApiProperty({ description: 'Whether more events are available' })
  hasMore: boolean;

  @ApiProperty({ description: 'Server timestamp for next sync' })
  serverTimestamp: Date;

  @ApiPropertyOptional({ description: 'Cursor for pagination' })
  nextCursor?: string;
}

export class SyncStatusDto {
  @ApiProperty()
  deviceId: string;

  @ApiProperty()
  lastPushAt: Date;

  @ApiProperty()
  lastPullAt: Date;

  @ApiProperty()
  pendingEvents: number;

  @ApiProperty()
  isOnline: boolean;
}

export class ConflictResolutionDto {
  @ApiProperty()
  eventId: string;

  @ApiProperty({ enum: ['SERVER_WINS', 'CLIENT_WINS', 'MERGE'] })
  resolution: 'SERVER_WINS' | 'CLIENT_WINS' | 'MERGE';

  @ApiPropertyOptional({ description: 'Merged data if resolution is MERGE' })
  mergedPayload?: Record<string, any>;
}
