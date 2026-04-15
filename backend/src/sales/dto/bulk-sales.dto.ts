import {
  IsArray,
  IsString,
  ValidateNested,
  ArrayMinSize,
} from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { CreateSaleDto } from './sales.dto';

export class BulkCreateSalesDto {
  @ApiProperty({ type: [CreateSaleDto], description: 'Array of sales to create' })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => CreateSaleDto)
  sales: CreateSaleDto[];
}

export class BulkVoidSalesDto {
  @ApiProperty({ description: 'Array of sale IDs to void' })
  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  ids: string[];

  @ApiProperty({ description: 'Reason for voiding' })
  @IsString()
  reason: string;
}
