import {
  IsArray,
  IsString,
  ValidateNested,
  ArrayMinSize,
} from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { CreateProductDto, UpdateProductDto } from './catalog.dto';

export class BulkCreateProductItem extends CreateProductDto {}

export class BulkUpdateProductItem extends UpdateProductDto {
  @ApiProperty({ description: 'Product ID to update' })
  @IsString()
  id: string;
}

export class BulkCreateProductsDto {
  @ApiProperty({ type: [BulkCreateProductItem], description: 'Array of products to create' })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => BulkCreateProductItem)
  products: BulkCreateProductItem[];
}

export class BulkUpdateProductsDto {
  @ApiProperty({ type: [BulkUpdateProductItem], description: 'Array of products to update' })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => BulkUpdateProductItem)
  products: BulkUpdateProductItem[];
}

export class BulkDeleteProductsDto {
  @ApiProperty({ description: 'Array of product IDs to delete' })
  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  ids: string[];
}