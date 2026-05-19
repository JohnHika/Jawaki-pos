import { IsString, IsArray, IsOptional, MaxLength, IsBoolean } from 'class-validator';

export class ChatMessageDto {
  @IsString()
  @MaxLength(4000)
  role: 'user' | 'assistant' | 'system';

  @IsString()
  @MaxLength(4000)
  content: string;
}

export class ChatRequestDto {
  @IsArray()
  messages: ChatMessageDto[];

  @IsOptional()
  @IsString()
  @MaxLength(200)
  storeId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  context?: 'sales' | 'inventory' | 'customers' | 'general';

  @IsOptional()
  @IsBoolean()
  includeData?: boolean;
}
