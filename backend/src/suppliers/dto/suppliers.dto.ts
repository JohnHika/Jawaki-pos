import {
  IsString,
  IsNumber,
  IsEnum,
  IsOptional,
  IsUUID,
  IsDateString,
  IsArray,
  ValidateNested,
  Min,
  MaxLength,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export enum SupplierInvoiceStatus {
  OPEN = 'OPEN',
  PARTIAL = 'PARTIAL',
  PAID = 'PAID',
}

export enum CashFundingSource {
  CASH_TILL = 'CASH_TILL',
  CREDIT_SUPPLIER = 'CREDIT_SUPPLIER',
}

export class CreateSupplierDto {
  @ApiProperty()
  @IsString()
  @MaxLength(200)
  name: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  contactName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(30)
  phone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  email?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(300)
  address?: string;
}

export class SupplierInvoiceItemDto {
  @ApiPropertyOptional({ description: 'Catalog product ID, if this line matches an existing product' })
  @IsOptional()
  @IsUUID('4')
  productId?: string;

  @ApiProperty()
  @IsString()
  @MaxLength(200)
  productName: string;

  @ApiProperty({ example: 10 })
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0.001)
  @Type(() => Number)
  quantity: number;

  @ApiPropertyOptional({ default: 'piece' })
  @IsOptional()
  @IsString()
  unit?: string;

  @ApiProperty({ example: 50 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  unitCost: number;
}

export class CreateSupplierInvoiceDto {
  @ApiProperty({ description: 'Branch ID' })
  @IsUUID('4')
  branchId: string;

  @ApiProperty({ description: 'Supplier name — matched or created' })
  @IsString()
  @MaxLength(200)
  supplierName: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(30)
  supplierPhone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  invoiceNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  receiptImageUrl?: string;

  @ApiProperty({ type: [SupplierInvoiceItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SupplierInvoiceItemDto)
  items: SupplierInvoiceItemDto[];

  @ApiPropertyOptional({ default: 0, description: 'Amount paid immediately, in cash or otherwise' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  paidAmount?: number;

  @ApiPropertyOptional({ enum: CashFundingSource, default: CashFundingSource.CASH_TILL })
  @IsOptional()
  @IsEnum(CashFundingSource)
  fundingSource?: CashFundingSource;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  dueDate?: string;

  @ApiPropertyOptional({ description: 'Offline ID from device (for sync dedup)' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  offlineId?: string;
}

export class RecordSupplierPaymentDto {
  @ApiProperty({ example: 1000 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Type(() => Number)
  amount: number;

  @ApiPropertyOptional({ enum: CashFundingSource, default: CashFundingSource.CASH_TILL })
  @IsOptional()
  @IsEnum(CashFundingSource)
  fundingSource?: CashFundingSource;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}
