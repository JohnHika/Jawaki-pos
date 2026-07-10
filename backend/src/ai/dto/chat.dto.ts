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
  // Grounding signals so the AI treats this data as the authoritative,
  // current state of the business (a zero means "hasn't happened yet",
  // not "offline/missing"). See buildSystemPrompt's data-source rules.
  @IsOptional()
  @IsString()
  data_source?: string;

  @IsOptional()
  @IsBoolean()
  data_is_authoritative?: boolean;

  @IsOptional()
  @IsBoolean()
  is_offline?: boolean;

  @IsOptional()
  @IsString()
  data_freshness?: string;

  @IsOptional()
  @IsBoolean()
  has_sales_today?: boolean;

  @IsOptional()
  @IsBoolean()
  data_read_failed?: boolean;

  // Durable shop memories the backend injects (owner prefs, policies,
  // customer notes) — loosely typed since it's server-populated context.
  @IsOptional()
  @IsArray()
  shop_memories?: any[];

  // Web-search grounding results the backend may inject.
  @IsOptional()
  @IsArray()
  web_insights?: any[];

  @IsOptional()
  @IsArray()
  web_sources?: any[];

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

// Echoes a paused gateway tool_use block (AskUserQuestion, or the mutating
// create_stock_reorder awaiting confirmation) back to the client. The
// client round-trips it verbatim in `pending_tool_call` on the follow-up
// request so the server can resume the same agent turn without needing to
// persist tool_use/tool_result blocks server-side.
export class PendingToolCallDto {
  @IsString()
  @MaxLength(200)
  id: string;

  @IsString()
  @MaxLength(100)
  name: string;

  @IsObject()
  input: Record<string, any>;
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

  // Toggles from the mobile "Add to chat" sheet. Accepted now so the
  // payload validates; wired to real web-search / tool-calling behaviour
  // in later phases.
  @IsOptional()
  @IsBoolean()
  web_search?: boolean;

  @IsOptional()
  @IsBoolean()
  tool_access?: boolean;

  // Set when resuming a paused agent turn (AskUserQuestion answered, or a
  // mutating tool call approved/declined). Must be the exact tool_use block
  // the server returned as `pending_tool_call` on the previous response.
  @IsOptional()
  @IsObject()
  @ValidateNested()
  @Type(() => PendingToolCallDto)
  pending_tool_call?: PendingToolCallDto;

  // The user's answers to an AskUserQuestion tool call — question text ->
  // chosen answer string (comma-joined for multiSelect), matching the
  // gateway's expected tool_result text format.
  @IsOptional()
  @IsObject()
  question_answers?: Record<string, string>;

  // Set when resuming a paused mutating tool call (create_stock_reorder).
  @IsOptional()
  @IsBoolean()
  tool_confirmed?: boolean;
}
