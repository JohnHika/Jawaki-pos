import {
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  Min,
  ValidateNested,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { StockMovementType } from '@prisma/client';

// ==================== BATCH MANAGEMENT DTOs ====================

export class BatchDto {
  @ApiProperty({ description: 'Unique batch number/code' })
  @IsString()
  batchNumber: string;

  @ApiProperty({ description: 'Quantity in this batch' })
  @IsNumber()
  @Min(0.001)
  @Type(() => Number)
  quantity: number;

  @ApiPropertyOptional({ description: 'Batch expiry date (ISO format)' })
  @IsOptional()
  @IsDateString()
  expiryDate?: string;

  @ApiPropertyOptional({ description: 'Manufacture date (ISO format)' })
  @IsOptional()
  @IsDateString()
  manufactureDate?: string;

  @ApiPropertyOptional({ description: 'Cost price for this batch' })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  costPrice?: number;

  @ApiPropertyOptional({ description: 'Supplier reference or invoice number' })
  @IsOptional()
  @IsString()
  supplierRef?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}

export class ReceiveBatchDto {
  @ApiProperty()
  @IsString()
  branchId: string;

  @ApiProperty()
  @IsString()
  productId: string;

  @ApiProperty({ type: [BatchDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => BatchDto)
  batches: BatchDto[];

  @ApiPropertyOptional({ description: 'Reference (e.g., PO number, invoice)' })
  @IsOptional()
  @IsString()
  reference?: string;
}

export class UpdateBatchDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  quantity?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  expiryDate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isBlocked?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}

export class ExpiryDashboardQueryDto {
  @ApiProperty()
  @IsString()
  branchId: string;

  @ApiPropertyOptional({ description: 'Filter by zone: expired, 30days, 60days, 90days' })
  @IsOptional()
  @IsString()
  zone?: 'expired' | '30days' | '60days' | '90days';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  page?: number;

  @ApiPropertyOptional({ default: 50 })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  limit?: number;
}

// Stock Adjustment DTOs
export class StockAdjustmentItemDto {
  @ApiProperty()
  @IsString()
  productId: string;

  @ApiProperty({ description: 'New stock quantity (absolute value)' })
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  quantity: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}

export class StockAdjustmentDto {
  @ApiProperty()
  @IsString()
  branchId: string;

  @ApiProperty({ enum: StockMovementType })
  @IsEnum(StockMovementType)
  type: StockMovementType;

  @ApiProperty({ type: [StockAdjustmentItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => StockAdjustmentItemDto)
  items: StockAdjustmentItemDto[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  reference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}

// Stock Transfer DTOs
export class TransferItemDto {
  @ApiProperty()
  @IsString()
  productId: string;

  @ApiProperty()
  @IsNumber()
  @Min(0.001)
  @Type(() => Number)
  quantity: number;
}

export class CreateTransferDto {
  @ApiProperty()
  @IsString()
  fromBranchId: string;

  @ApiProperty()
  @IsString()
  toBranchId: string;

  @ApiProperty({ type: [TransferItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => TransferItemDto)
  items: TransferItemDto[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}

export class ReceiveTransferDto {
  @ApiProperty({ description: 'Received quantities per item' })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => TransferItemDto)
  receivedItems: TransferItemDto[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}

// Query DTOs
export class StockQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  categoryId?: string;

  @ApiPropertyOptional({ description: 'Only show low stock items' })
  @IsOptional()
  lowStock?: boolean;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  page?: number;

  @ApiPropertyOptional({ default: 50 })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  limit?: number;
}

// Response DTOs
export class StockItemResponseDto {
  @ApiProperty()
  productId: string;

  @ApiProperty()
  sku: string;

  @ApiProperty()
  productName: string;

  @ApiProperty()
  quantity: number;

  @ApiProperty()
  reservedQty: number;

  @ApiProperty()
  availableQty: number;

  @ApiProperty()
  minStock: number;

  @ApiProperty()
  isLowStock: boolean;

  @ApiProperty()
  unit: string;

  @ApiProperty()
  costPrice?: number;

  @ApiProperty()
  stockValue?: number;
}

export class StockMovementResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  productId: string;

  @ApiProperty()
  productName: string;

  @ApiProperty()
  type: StockMovementType;

  @ApiProperty()
  quantity: number;

  @ApiProperty()
  previousQty: number;

  @ApiProperty()
  newQty: number;

  @ApiProperty()
  reference?: string;

  @ApiProperty()
  notes?: string;

  @ApiProperty()
  createdAt: Date;

  @ApiProperty()
  createdBy?: string;
}

export class TransferResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  fromBranchId: string;

  @ApiProperty()
  fromBranchName: string;

  @ApiProperty()
  toBranchId: string;

  @ApiProperty()
  toBranchName: string;

  @ApiProperty()
  status: string;

  @ApiProperty()
  notes?: string;

  @ApiProperty()
  items: Array<{
    productId: string;
    productName: string;
    requestedQty: number;
    sentQty?: number;
    receivedQty?: number;
  }>;

  @ApiProperty()
  createdAt: Date;

  @ApiProperty()
  createdBy: string;
}

// ==================== BATCH RESPONSE DTOs ====================

export class BatchResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  batchNumber: string;

  @ApiProperty()
  quantity: number;

  @ApiProperty()
  reservedQty: number;

  @ApiProperty()
  availableQty: number;

  @ApiProperty()
  expiryDate?: Date;

  @ApiProperty()
  manufactureDate?: Date;

  @ApiProperty()
  costPrice?: number;

  @ApiProperty()
  supplierRef?: string;

  @ApiProperty()
  notes?: string;

  @ApiProperty()
  isBlocked: boolean;

  @ApiProperty()
  isExpired: boolean;

  @ApiProperty()
  daysUntilExpiry?: number;

  @ApiProperty()
  expiryStatus: 'expired' | 'expiring_soon' | 'good';

  @ApiProperty()
  createdAt: Date;
}

export class StockWithBatchesResponseDto {
  @ApiProperty()
  productId: string;

  @ApiProperty()
  sku: string;

  @ApiProperty()
  productName: string;

  @ApiProperty()
  totalQuantity: number;

  @ApiProperty()
  totalReservedQty: number;

  @ApiProperty()
  totalAvailableQty: number;

  @ApiProperty({ type: [BatchResponseDto] })
  batches: BatchResponseDto[];

  @ApiProperty()
  hasExpiredBatches: boolean;

  @ApiProperty()
  hasExpiringSoonBatches: boolean;
}

export class ExpiryDashboardItemDto {
  @ApiProperty()
  productId: string;

  @ApiProperty()
  productName: string;

  @ApiProperty()
  sku: string;

  @ApiProperty()
  batchNumber: string;

  @ApiProperty()
  quantity: number;

  @ApiProperty()
  expiryDate?: Date;

  @ApiProperty()
  daysUntilExpiry?: number;

  @ApiProperty()
  expiryStatus: 'expired' | 'critical' | 'warning' | 'good';

  @ApiProperty()
  isBlocked: boolean;

  @ApiProperty()
  costValue?: number;
}

export class ExpiryDashboardResponseDto {
  @ApiProperty({ type: [ExpiryDashboardItemDto] })
  items: ExpiryDashboardItemDto[];

  @ApiProperty()
  total: number;

  @ApiProperty()
  page: number;

  @ApiProperty()
  limit: number;

  @ApiProperty()
  totalPages: number;

  @ApiProperty()
  summary: {
    expiredCount: number;
    expiredValue: number;
    expiring30Days: number;
    expiring30DaysValue: number;
    expiring60Days: number;
    expiring60DaysValue: number;
    expiring90Days: number;
    expiring90DaysValue: number;
  };
}
