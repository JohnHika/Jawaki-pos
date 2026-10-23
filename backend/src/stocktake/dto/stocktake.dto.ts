import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export class StartStockCountDto {
  @ApiProperty()
  @IsUUID('4')
  branchId: string;

  @ApiPropertyOptional({ example: 'Weekly shelf count' })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  title?: string;

  @ApiPropertyOptional({
    description: 'Hide system quantities from the counter (default true)',
  })
  @IsOptional()
  @IsBoolean()
  blind?: boolean;

  @ApiPropertyOptional({ description: 'Count only these products' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(2000)
  @IsUUID('4', { each: true })
  productIds?: string[];

  @ApiPropertyOptional({ description: 'Count only products in this category' })
  @IsOptional()
  @IsUUID('4')
  categoryId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}

export class CountEntryDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ description: 'What is physically on the shelf' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0)
  @Max(10_000_000)
  @Type(() => Number)
  countedQty: number;

  @ApiPropertyOptional({ description: 'Why it differs (damaged, expired, sold unrecorded...)' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  reason?: string;
}

export class RecordCountsDto {
  @ApiProperty({ type: [CountEntryDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => CountEntryDto)
  entries: CountEntryDto[];
}

export class StockCountQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4')
  branchId?: string;

  @ApiPropertyOptional({ enum: ['IN_PROGRESS', 'SUBMITTED', 'APPROVED', 'CANCELLED'] })
  @IsOptional()
  @IsIn(['IN_PROGRESS', 'SUBMITTED', 'APPROVED', 'CANCELLED'])
  status?: string;
}

export class ApproveStockCountDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}
