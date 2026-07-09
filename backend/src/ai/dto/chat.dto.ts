import { IsString, IsArray, IsOptional, MaxLength, IsBoolean, IsObject, ValidateNested, IsEnum, IsNumber } from 'class-validator';
import { Type } from 'class-transformer';

enum AiTask {
  AnalyzeAndRecommend = 'analyze_and_recommend',
  BusinessAnalysis = 'business_analysis',
  QuickQuestion = 'quick_question',
}

enum AiResponseStyle {
  ActionablePartner = 'actionable_partner',
  Concise = 'concise',
  DetailedReport = 'detailed_report',
}

class ProductSummaryDto {
  @IsString()
  name: string;

  @IsOptional()
  @IsString()
  sku?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsNumber()
  quantity_sold?: number;

  @IsOptional()
  @IsNumber()
  revenue?: number;

  @IsOptional()
  @IsNumber()
  price?: number;

  @IsOptional()
  @IsNumber()
  remaining_stock?: number;

  @IsOptional()
  @IsNumber()
  days_without_sale?: number;
}

class SalesSummaryDto {
  @IsOptional()
  @IsNumber()
  total_sales?: number;

  @IsOptional()
  @IsNumber()
  transactions?: number;

  @IsOptional()
  @IsNumber()
  average_ticket?: number;

  @IsOptional()
  @IsNumber()
  items_sold?: number;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ProductSummaryDto)
  top_products?: ProductSummaryDto[];

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ProductSummaryDto)
  low_stock_items?: ProductSummaryDto[];

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ProductSummaryDto)
  slow_moving_items?: ProductSummaryDto[];
}

class BusinessContextDto {
  @IsString()
  @IsOptional()
  business_type?: string;

  @IsString()
  @IsOptional()
  company?: string;

  @IsString()
  @IsOptional()
  tenant_slug?: string;

  @IsString()
  @IsOptional()
  branch?: string;

  @IsString()
  @IsOptional()
  role?: string;

  @IsString()
  @IsOptional()
  time_range?: string;

  @IsString()
  @IsOptional()
  @MaxLength(100)
  user_first_name?: string;
}

export class ChatMessageDto {
  @IsString()
  @MaxLength(4000)
  role: 'user' | 'assistant' | 'system';

  @IsString()
  @MaxLength(4000)
  content: string;
}

export class ChatRequestDto {
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  user_question?: string;

  @IsOptional()
  @IsObject()
  @ValidateNested()
  @Type(() => BusinessContextDto)
  business_context?: BusinessContextDto;

  @IsOptional()
  @IsObject()
  @ValidateNested()
  @Type(() => SalesSummaryDto)
  data_context?: any;

  @IsOptional()
  @IsString()
  @IsEnum(AiTask)
  ai_task?: string;

  @IsOptional()
  @IsString()
  @IsEnum(AiResponseStyle)
  response_style?: string;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ChatMessageDto)
  messages?: ChatMessageDto[];

  @IsOptional()
  @IsString()
  @MaxLength(200)
  storeId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  branchId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  context?: 'sales' | 'inventory' | 'customers' | 'general';

  @IsOptional()
  @IsBoolean()
  includeData?: boolean;
}
