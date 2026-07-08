import { IsNumber, IsOptional, IsString, MaxLength, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class CreateReconciliationDto {
  @ApiProperty({
    description: 'Physically counted cash in the till, in KES',
    example: 15000,
  })
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Counted cash must have up to 2 decimal places' })
  @Min(0, { message: 'Counted cash cannot be negative' })
  @Type(() => Number)
  countedCash: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'Notes must not exceed 1000 characters' })
  notes?: string;
}

export class ReconciliationQueryDto {
  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsNumber({}, { message: 'Page must be a number' })
  @Min(1)
  @Type(() => Number)
  page?: number;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional()
  @IsNumber({}, { message: 'Limit must be a number' })
  @Min(1)
  @Type(() => Number)
  limit?: number;
}
