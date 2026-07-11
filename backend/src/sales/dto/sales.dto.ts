import {
  IsArray,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  Min,
  Max,
  ValidateNested,
  IsDateString,
  IsUUID,
  MaxLength,
  MinLength,
  ArrayMinSize,
  ArrayMaxSize,
  IsBoolean,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { PaymentMethod, SaleStatus } from '@prisma/client';

// Sale Item DTO
export class CreateSaleItemDto {
  @ApiProperty()
  @IsUUID('4', { message: 'Product ID must be a valid UUID' })
  productId: string;

  @ApiProperty({ example: 2 })
  @IsNumber({ maxDecimalPlaces: 3 }, { message: 'Quantity must be a number with up to 3 decimal places' })
  @Min(0.001, { message: 'Quantity must be at least 0.001' })
  @Max(1000000, { message: 'Quantity cannot exceed 1,000,000' })
  @Type(() => Number)
  quantity: number;

  @ApiPropertyOptional({ description: 'Override unit price' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Price must have up to 2 decimal places' })
  @Min(0, { message: 'Price cannot be negative' })
  @Max(10000000, { message: 'Price cannot exceed 10,000,000' })
  @Type(() => Number)
  unitPrice?: number;

  @ApiPropertyOptional({ description: 'Line item discount' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Discount must have up to 2 decimal places' })
  @Min(0, { message: 'Discount cannot be negative' })
  @Max(1000000, { message: 'Discount cannot exceed 1,000,000' })
  @Type(() => Number)
  discount?: number;

  @ApiPropertyOptional({ description: 'Sold-unit label (piece/box/pack…) for detailed receipts' })
  @IsOptional()
  @IsString()
  @MaxLength(40)
  unit?: string;

  @ApiPropertyOptional({ description: 'Base units per sold unit (e.g. 12 for a box of 12)' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0)
  @Type(() => Number)
  quantityPerUnit?: number;
}

// One payment component of a SPLIT sale — e.g. { method: CASH, amount: 500 }
// plus { method: MPESA, amount: 300 } together covering one KES 800 total.
export class SaleTenderDto {
  @ApiProperty({ enum: PaymentMethod, description: 'Must not itself be SPLIT' })
  @IsEnum(PaymentMethod, { message: 'Invalid tender payment method' })
  method: PaymentMethod;

  @ApiProperty({ example: 500 })
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Tender amount must have up to 2 decimal places' })
  @Min(0.01, { message: 'Tender amount must be greater than 0' })
  @Max(10000000, { message: 'Tender amount cannot exceed 10,000,000' })
  @Type(() => Number)
  amount: number;

  @ApiPropertyOptional({ description: 'External reference, e.g. M-Pesa transaction code' })
  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Reference must not exceed 100 characters' })
  reference?: string;
}

// Create Sale DTO
export class CreateSaleDto {
  @ApiProperty({ description: 'Branch ID' })
  @IsUUID('4', { message: 'Branch ID must be a valid UUID' })
  branchId: string;

  @ApiPropertyOptional({ description: 'Device ID (for mobile POS)' })
  @IsOptional()
  @IsUUID('4', { message: 'Device ID must be a valid UUID' })
  deviceId?: string;

  @ApiPropertyOptional({ description: 'Customer ID' })
  @IsOptional()
  @IsUUID('4', { message: 'Customer ID must be a valid UUID' })
  customerId?: string;

  @ApiProperty({ type: [CreateSaleItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateSaleItemDto)
  @ArrayMinSize(1, { message: 'Sale must have at least one item' })
  @ArrayMaxSize(500, { message: 'Sale cannot exceed 500 items' })
  items: CreateSaleItemDto[];

  @ApiPropertyOptional({ description: 'Overall discount amount' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Discount must have up to 2 decimal places' })
  @Min(0, { message: 'Discount cannot be negative' })
  @Max(10000000, { message: 'Discount cannot exceed 10,000,000' })
  @Type(() => Number)
  discountAmount?: number;

  @ApiProperty({ enum: PaymentMethod })
  @IsEnum(PaymentMethod, { message: 'Invalid payment method' })
  paymentMethod: PaymentMethod;

  @ApiPropertyOptional({ description: 'Amount paid by customer (optional for CREDIT payment method)' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Amount must have up to 2 decimal places' })
  @Min(0, { message: 'Paid amount cannot be negative' })
  @Max(10000000, { message: 'Paid amount cannot exceed 10,000,000' })
  @Type(() => Number)
  paidAmount?: number;

  @ApiPropertyOptional({
    type: [SaleTenderDto],
    description: 'Required when paymentMethod is SPLIT — the individual payment components, which must sum to at least the total',
  })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SaleTenderDto)
  @ArrayMinSize(2, { message: 'A split payment needs at least 2 tenders' })
  @ArrayMaxSize(10, { message: 'A split payment cannot exceed 10 tenders' })
  tenders?: SaleTenderDto[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'Notes must not exceed 1000 characters' })
  notes?: string;

  @ApiPropertyOptional({ description: 'Offline ID from device (for sync)' })
  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Offline ID must not exceed 100 characters' })
  offlineId?: string;

  @ApiPropertyOptional({ description: 'Original timestamp from device' })
  @IsOptional()
  @IsDateString({}, { message: 'Device timestamp must be a valid ISO 8601 date' })
  deviceTimestamp?: string;
}

// Refund DTOs
export class RefundItemDto {
  @ApiProperty()
  @IsUUID('4', { message: 'Sale Item ID must be a valid UUID' })
  saleItemId: string;

  @ApiProperty()
  @IsNumber({ maxDecimalPlaces: 3 }, { message: 'Quantity must be a number with up to 3 decimal places' })
  @Min(0.001, { message: 'Quantity must be at least 0.001' })
  @Max(1000000, { message: 'Quantity cannot exceed 1,000,000' })
  @Type(() => Number)
  quantity: number;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  restockItem?: boolean;
}

export class CreateRefundDto {
  @ApiProperty()
  @IsUUID('4', { message: 'Sale ID must be a valid UUID' })
  saleId: string;

  @ApiProperty()
  @IsString()
  @MinLength(10, { message: 'Reason must be at least 10 characters' })
  @MaxLength(500, { message: 'Reason must not exceed 500 characters' })
  reason: string;

  @ApiProperty({ type: [RefundItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => RefundItemDto)
  @ArrayMinSize(1, { message: 'Refund must have at least one item' })
  items: RefundItemDto[];
}

// Query DTOs
export class SalesQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4', { message: 'Branch ID must be a valid UUID' })
  branchId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4', { message: 'User ID must be a valid UUID' })
  userId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(SaleStatus, { message: 'Invalid sale status' })
  status?: SaleStatus;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(PaymentMethod, { message: 'Invalid payment method' })
  paymentMethod?: PaymentMethod;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString({}, { message: 'Start date must be a valid ISO 8601 date' })
  startDate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString({}, { message: 'End date must be a valid ISO 8601 date' })
  endDate?: string;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsNumber({}, { message: 'Page must be a number' })
  @Min(1, { message: 'Page must be at least 1' })
  @Max(10000, { message: 'Page cannot exceed 10000' })
  @Type(() => Number)
  page?: number;

  @ApiPropertyOptional({ default: 50 })
  @IsOptional()
  @IsNumber({}, { message: 'Limit must be a number' })
  @Min(1, { message: 'Limit must be at least 1' })
  @Max(500, { message: 'Limit cannot exceed 500' })
  @Type(() => Number)
  limit?: number;
}

// Response DTOs (no validation needed for responses, keeping as-is)
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

  @ApiPropertyOptional()
  creditSales?: number;

  @ApiPropertyOptional()
  outstandingBalance?: number;

  @ApiProperty()
  voidedCount: number;

  @ApiProperty()
  refundedAmount: number;
}
