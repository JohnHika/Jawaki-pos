import { Type } from 'class-transformer';
import { IsEnum, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ManualPaymentStatus } from '@prisma/client';

export class CreateManualPaymentRequestDto {
  @ApiProperty()
  @IsUUID('4')
  branchId: string;

  @ApiPropertyOptional({ description: 'Existing sale this payment settles' })
  @IsOptional()
  @IsUUID('4')
  saleId?: string;

  @ApiProperty({ example: 'bank_transfer', description: 'How the customer paid outside the app' })
  @IsString()
  @MinLength(2)
  @MaxLength(40)
  paymentMethod: string;

  @ApiProperty({ example: 1200 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(10000000)
  @Type(() => Number)
  amount: number;

  @ApiProperty({ example: 'Customer paid by bank transfer, slip attached' })
  @IsString()
  @MinLength(3)
  @MaxLength(500)
  reason: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;
}

export class ManualPaymentListQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4')
  branchId?: string;

  @ApiPropertyOptional({ enum: ManualPaymentStatus })
  @IsOptional()
  @IsEnum(ManualPaymentStatus)
  status?: ManualPaymentStatus;
}

export class RejectManualPaymentDto {
  @ApiProperty()
  @IsString()
  @MinLength(3)
  @MaxLength(500)
  rejectionReason: string;
}
