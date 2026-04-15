import {
  IsArray,
  IsBoolean,
  IsNumber,
  IsOptional,
  IsString,
  Min,
  Max,
  IsObject,
  IsUUID,
  MaxLength,
  Matches,
  MinLength,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Type } from 'class-transformer';

// Category DTOs
export class CreateCategoryDto {
  @ApiProperty({ example: 'Beverages' })
  @IsString()
  @MinLength(2, { message: 'Category name must be at least 2 characters' })
  @MaxLength(100, { message: 'Category name must not exceed 100 characters' })
  @Matches(/^[a-zA-Z0-9\s&'-]+$/, { message: 'Category name contains invalid characters' })
  name: string;

  @ApiProperty({ example: 'beverages' })
  @IsString()
  @MinLength(2, { message: 'Slug must be at least 2 characters' })
  @MaxLength(100, { message: 'Slug must not exceed 100 characters' })
  @Matches(/^[a-z0-9]+(-[a-z0-9]+)*$/, { message: 'Slug must be lowercase alphanumeric with hyphens' })
  slug: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500, { message: 'Description must not exceed 500 characters' })
  description?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500, { message: 'Image URL must not exceed 500 characters' })
  @Matches(/^https?:\/\/.+/i, { message: 'Image must be a valid URL' })
  image?: string;

  @ApiPropertyOptional({ description: 'Parent category ID for subcategories' })
  @IsOptional()
  @IsUUID('4', { message: 'Parent category ID must be a valid UUID' })
  parentId?: string;

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @IsNumber({}, { message: 'Sort order must be a number' })
  @Min(0, { message: 'Sort order cannot be negative' })
  @Max(10000, { message: 'Sort order cannot exceed 10000' })
  @Type(() => Number)
  sortOrder?: number;
}

export class UpdateCategoryDto extends PartialType(CreateCategoryDto) {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

// Product DTOs
export class CreateProductDto {
  @ApiProperty({ example: 'SKU001' })
  @IsString()
  @MinLength(3, { message: 'SKU must be at least 3 characters' })
  @MaxLength(50, { message: 'SKU must not exceed 50 characters' })
  @Matches(/^[a-zA-Z0-9_-]+$/, { message: 'SKU can only contain letters, numbers, hyphens, and underscores' })
  sku: string;

  @ApiProperty({ example: 'Coca Cola 500ml' })
  @IsString()
  @MinLength(2, { message: 'Product name must be at least 2 characters' })
  @MaxLength(200, { message: 'Product name must not exceed 200 characters' })
  name: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'Description must not exceed 1000 characters' })
  description?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500, { message: 'Image URL must not exceed 500 characters' })
  @Matches(/^https?:\/\/.+/i, { message: 'Image must be a valid URL' })
  image?: string;

  @ApiProperty({ example: 150.0 })
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Price must have up to 2 decimal places' })
  @Min(0, { message: 'Price cannot be negative' })
  @Max(10000000, { message: 'Price cannot exceed 10,000,000' })
  @Type(() => Number)
  basePrice: number;

  @ApiPropertyOptional({ example: 120.0 })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Cost price must have up to 2 decimal places' })
  @Min(0, { message: 'Cost price cannot be negative' })
  @Max(10000000, { message: 'Cost price cannot exceed 10,000,000' })
  @Type(() => Number)
  costPrice?: number;

  @ApiPropertyOptional({ example: 16.0, description: 'Tax rate percentage' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Tax rate must have up to 2 decimal places' })
  @Min(0, { message: 'Tax rate cannot be negative' })
  @Max(100, { message: 'Tax rate cannot exceed 100%' })
  @Type(() => Number)
  taxRate?: number;

  @ApiPropertyOptional({ example: 'piece', default: 'piece' })
  @IsOptional()
  @IsString()
  @MaxLength(20, { message: 'Unit must not exceed 20 characters' })
  unit?: string;

  @ApiPropertyOptional({ example: 10, description: 'Minimum stock level for alerts' })
  @IsOptional()
  @IsNumber({}, { message: 'Min stock must be a number' })
  @Min(0, { message: 'Min stock cannot be negative' })
  @Max(1000000, { message: 'Min stock cannot exceed 1,000,000' })
  @Type(() => Number)
  minStock?: number;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  trackInventory?: boolean;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  allowFractions?: boolean;

  @ApiPropertyOptional({ description: 'Category IDs to assign' })
  @IsOptional()
  @IsArray()
  @IsUUID('4', { each: true, message: 'Each category ID must be a valid UUID' })
  categoryIds?: string[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  metadata?: Record<string, any>;
}

export class UpdateProductDto extends PartialType(CreateProductDto) {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isFavorite?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(10000)
  sortOrder?: number;
}

// Branch Price Override DTO
export class SetBranchPriceDto {
  @ApiProperty({ description: 'Product ID' })
  @IsUUID('4', { message: 'Product ID must be a valid UUID' })
  productId: string;

  @ApiProperty({ description: 'Branch ID' })
  @IsUUID('4', { message: 'Branch ID must be a valid UUID' })
  branchId: string;

  @ApiProperty({ example: 160.0 })
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Price must have up to 2 decimal places' })
  @Min(0, { message: 'Price cannot be negative' })
  @Max(10000000, { message: 'Price cannot exceed 10,000,000' })
  @Type(() => Number)
  price: number;

  @ApiPropertyOptional()
  @IsOptional()
  startDate?: Date;

  @ApiPropertyOptional()
  @IsOptional()
  endDate?: Date;
}

// Query DTOs
export class ProductQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200, { message: 'Search query must not exceed 200 characters' })
  search?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4', { message: 'Category ID must be a valid UUID' })
  categoryId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  @Type(() => Boolean)
  isActive?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  @Type(() => Boolean)
  isFavorite?: boolean;

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

// Response DTOs (no validation needed)
export class CategoryResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  name: string;

  @ApiProperty()
  slug: string;

  @ApiProperty()
  description?: string;

  @ApiProperty()
  image?: string;

  @ApiProperty()
  parentId?: string;

  @ApiProperty()
  sortOrder: number;

  @ApiProperty()
  isActive: boolean;

  @ApiProperty()
  productCount?: number;

  @ApiProperty()
  children?: CategoryResponseDto[];
}

export class ProductResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  sku: string;

  @ApiProperty()
  name: string;

  @ApiProperty()
  description?: string;

  @ApiProperty()
  image?: string;

  @ApiProperty()
  basePrice: number;

  @ApiProperty()
  costPrice?: number;

  @ApiProperty()
  taxRate: number;

  @ApiProperty()
  unit: string;

  @ApiProperty()
  minStock: number;

  @ApiProperty()
  trackInventory: boolean;

  @ApiProperty()
  allowFractions: boolean;

  @ApiProperty()
  isActive: boolean;

  @ApiProperty()
  isFavorite: boolean;

  @ApiProperty()
  categories?: { id: string; name: string }[];

  @ApiProperty({ description: 'Current price considering branch overrides' })
  currentPrice?: number;

  @ApiProperty({ description: 'Current stock at requested branch' })
  currentStock?: number;
}

export class PaginatedProductsDto {
  @ApiProperty({ type: [ProductResponseDto] })
  items: ProductResponseDto[];

  @ApiProperty()
  total: number;

  @ApiProperty()
  page: number;

  @ApiProperty()
  limit: number;

  @ApiProperty()
  totalPages: number;
}
