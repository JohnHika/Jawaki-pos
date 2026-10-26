import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsNumber,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

const KINDS = ['PERCENT', 'FIXED'];

export class CreateCouponDto {
  @ApiPropertyOptional({ description: 'Letters and digits. Leave out to generate one.' })
  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9_-]{3,20}$/, { message: 'Code must be 3-20 letters, digits, - or _' })
  code?: string;

  @ApiPropertyOptional({ description: 'Internal label, e.g. "Eid offer"' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  name?: string;

  @ApiProperty({ enum: KINDS })
  @IsIn(KINDS)
  kind: 'PERCENT' | 'FIXED';

  @ApiProperty({ description: 'Percent (0-100) or a flat KES amount' })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(10_000_000)
  @Type(() => Number)
  value: number;

  @ApiPropertyOptional({ nullable: true, description: 'Cap on the discount from a percent coupon' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(10_000_000)
  @Type(() => Number)
  maxDiscount?: number | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(100_000_000)
  @Type(() => Number)
  minSpend?: number | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsDateString()
  startsAt?: string | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsDateString()
  expiresAt?: string | null;

  @ApiPropertyOptional({ nullable: true, description: 'Total number of uses' })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(1_000_000)
  @Type(() => Number)
  usageLimit?: number | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(10_000)
  @Type(() => Number)
  perCustomerLimit?: number | null;

  @ApiPropertyOptional({ nullable: true, description: 'Restrict the code to one customer' })
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  customerId?: string | null;

  @ApiPropertyOptional({ type: [String], description: 'Only these products are discounted. Empty = whole sale.' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @IsUUID('4', { each: true })
  productIds?: string[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class UpdateCouponDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  name?: string;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(10_000_000)
  @Type(() => Number)
  maxDiscount?: number | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(100_000_000)
  @Type(() => Number)
  minSpend?: number | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsDateString()
  startsAt?: string | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsDateString()
  expiresAt?: string | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(1_000_000)
  @Type(() => Number)
  usageLimit?: number | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(10_000)
  @Type(() => Number)
  perCustomerLimit?: number | null;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class CheckCouponLineDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty()
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0.001)
  @Max(1_000_000)
  @Type(() => Number)
  quantity: number;

  @ApiProperty()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(10_000_000)
  @Type(() => Number)
  unitPrice: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  discount?: number;
}

export class CheckCouponDto {
  @ApiProperty()
  @IsString()
  @MaxLength(40)
  code: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  customerId?: string;

  @ApiProperty({ type: [CheckCouponLineDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => CheckCouponLineDto)
  lines: CheckCouponLineDto[];
}

export class CouponReportQueryDto {
  @ApiPropertyOptional({ default: 30 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(365)
  @Type(() => Number)
  days?: number;
}
