import { IsNumber, IsOptional, IsString, MaxLength, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export class CloseDayDto {
  @ApiProperty({
    description: 'Physically counted cash in the till at close, in KES',
    example: 15000,
  })
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Counted cash must have up to 2 decimal places' })
  @Min(0, { message: 'Counted cash cannot be negative' })
  @Type(() => Number)
  countedCash: number;

  @ApiPropertyOptional({
    description: 'The business day to close (ISO date). Defaults to today.',
    example: '2026-07-11',
  })
  @IsOptional()
  @IsString()
  date?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'Notes must not exceed 1000 characters' })
  notes?: string;
}
