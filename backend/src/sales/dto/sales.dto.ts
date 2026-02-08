import {
  IsArray,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  Min,
  ValidateNested,
  IsDateString,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { PaymentMethod, SaleStatus } from '@prisma/client';

// Sale Item DTO
export class CreateSaleItemDto {
  @ApiProperty()
  @IsString()
  productId: string;

  @ApiProperty({ example: 2 })
  @IsNumber()
  @Min(0.001)
  @Type(() => Number)
  quantity: number;

  @ApiPropertyOptional({ description: 'Override unit price' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  unitPrice?: number;

  @ApiPropertyOptional({ description: 'Line item discount' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  discount?: number;
}

// Create Sale DTO
export class CreateSaleDto {
  @ApiProperty({ description: 'Branch ID' })
  @IsString()
  branchId: string;

  @ApiPropertyOptional({ description: 'Device ID (for mobile POS)' })
  @IsOptional()
  @IsString()
  deviceId?: string;

  @ApiPropertyOptional({ description: 'Customer ID' })
  @IsOptional()
  @IsString()
  customerId?: string;

  @ApiProperty({ type: [CreateSaleItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateSaleItemDto)
  items: CreateSaleItemDto[];

  @ApiPropertyOptional({ description: 'Overall discount amount' })
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  discountAmount?: number;

  @ApiProperty({ enum: PaymentMethod })
  @IsEnum(PaymentMethod)
  paymentMethod: PaymentMethod;

  @ApiProperty({ description: 'Amount paid by customer' })
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  paidAmount: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiPropertyOptional({ description: 'Offline ID from device (for sync)' })
  @IsOptional()
  @IsString()
  offlineId?: string;

  @ApiPropertyOptional({ description: 'Original timestamp from device' })
  @IsOptional()
  @IsDateString()
  deviceTimestamp?: string;
}

// Refund DTOs
export class RefundItemDto {
  @ApiProperty()
  @IsString()
  saleItemId: string;

  @ApiProperty()
  @IsNumber()
  @Min(0.001)
  @Type(() => Number)
  quantity: number;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  restockItem?: boolean;
}

export class CreateRefundDto {
  @ApiProperty()
  @IsString()
  saleId: string;

  @ApiProperty()
  @IsString()
  reason: string;

  @ApiProperty({ type: [RefundItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => RefundItemDto)
  items: RefundItemDto[];
}

// Query DTOs
export class SalesQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  branchId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  userId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(SaleStatus)
  status?: SaleStatus;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(PaymentMethod)
  paymentMethod?: PaymentMethod;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  startDate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  endDate?: string;

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
export class SaleItemResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  productId: string;

  @ApiProperty()
  productName: string;

  @ApiProperty()
  quantity: number;

  @ApiProperty()
  unitPrice: number;

  @ApiProperty()
  discount: number;

  @ApiProperty()
  taxRate: number;

  @ApiProperty()
  taxAmount: number;

  @ApiProperty()
  totalAmount: number;
}

export class SaleResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  receiptNumber: string;

  @ApiProperty()
  branchId: string;

  @ApiProperty()
  branchName?: string;

  @ApiProperty()
  userId: string;

  @ApiProperty()
  userName?: string;

  @ApiProperty()
  customerId?: string;

  @ApiProperty()
  customerName?: string;

  @ApiProperty()
  status: SaleStatus;

  @ApiProperty()
  subtotal: number;

  @ApiProperty()
  taxAmount: number;

  @ApiProperty()
  discountAmount: number;

  @ApiProperty()
  totalAmount: number;

  @ApiProperty()
  paidAmount: number;

  @ApiProperty()
  changeAmount: number;

  @ApiProperty()
  paymentMethod: PaymentMethod;

  @ApiProperty()
  notes?: string;

  @ApiProperty({ type: [SaleItemResponseDto] })
  items?: SaleItemResponseDto[];

  @ApiProperty()
  createdAt: Date;
}

export class PaginatedSalesDto {
  @ApiProperty({ type: [SaleResponseDto] })
  items: SaleResponseDto[];

  @ApiProperty()
  total: number;

  @ApiProperty()
  page: number;

  @ApiProperty()
  limit: number;

  @ApiProperty()
  totalPages: number;
}

export class DailySummaryDto {
  @ApiProperty()
  date: string;

  @ApiProperty()
  totalSales: number;

  @ApiProperty()
  totalTransactions: number;

  @ApiProperty()
  totalTax: number;

  @ApiProperty()
  totalDiscount: number;

  @ApiProperty()
  cashSales: number;

  @ApiProperty()
  mpesaSales: number;

  @ApiProperty()
  cardSales: number;

  @ApiProperty()
  voidedCount: number;

  @ApiProperty()
  refundedAmount: number;
}
