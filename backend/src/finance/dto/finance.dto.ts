import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ReceivablePaymentMethod, ReceivableStatus, SupplierInvoiceStatus } from '@prisma/client';

export class FinanceBranchQueryDto {
  @ApiProperty()
  @IsUUID('4')
  branchId: string;
}

export class FinanceStatusQueryDto extends FinanceBranchQueryDto {
  @ApiPropertyOptional({ enum: ReceivableStatus })
  @IsOptional()
  @IsEnum(ReceivableStatus)
  status?: ReceivableStatus;
}

export class PayablesQueryDto extends FinanceBranchQueryDto {
  @ApiPropertyOptional({ enum: SupplierInvoiceStatus })
  @IsOptional()
  @IsEnum(SupplierInvoiceStatus)
  status?: SupplierInvoiceStatus;
}

export class RecordReceivablePaymentDto {
  @ApiProperty()
  @IsUUID('4')
  branchId: string;

  @ApiProperty({ example: 250 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(10000000)
  @Type(() => Number)
  amount: number;

  @ApiProperty({ enum: ReceivablePaymentMethod })
  @IsEnum(ReceivablePaymentMethod)
  method: ReceivablePaymentMethod;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  reference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;

  @ApiPropertyOptional({ description: 'Offline idempotency key from the device' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  offlineId?: string;
}

export class CreatePeerDebtorDto {
  @ApiProperty()
  @IsString()
  @MaxLength(160)
  name: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  contactName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(40)
  phone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(254)
  email?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  address?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;
}

export class CreatePeerReceivableDto {
  @ApiProperty()
  @IsUUID('4')
  branchId: string;

  @ApiProperty()
  @IsUUID('4')
  debtorId: string;

  @ApiProperty()
  @IsString()
  @MaxLength(500)
  description: string;

  @ApiProperty({ example: 1000 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(10000000)
  @Type(() => Number)
  amount: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  dueDate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  reference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  offlineId?: string;
}

export class ReceivableAllocationDto {
  @ApiProperty()
  @IsUUID('4')
  receivableId: string;

  @ApiProperty({ example: 250 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(10000000)
  @Type(() => Number)
  amount: number;
}

/** One collection from a customer, split across several open retail receivables. */
export class BulkRetailPaymentDto {
  @ApiProperty()
  @IsUUID('4')
  branchId: string;

  @ApiProperty({ enum: ReceivablePaymentMethod })
  @IsEnum(ReceivablePaymentMethod)
  method: ReceivablePaymentMethod;

  @ApiProperty({ type: [ReceivableAllocationDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => ReceivableAllocationDto)
  allocations: ReceivableAllocationDto[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  reference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;

  @ApiPropertyOptional({ description: 'Offline idempotency key for the whole batch' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  offlineId?: string;
}
