import { IsOptional, IsString, IsNumber, Min, Max, MaxLength } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiPropertyOptional } from '@nestjs/swagger';

export class AuditLogQueryDto {
  @ApiPropertyOptional({ description: 'Filter by entity type, e.g. "branch", "user", "pin"' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  entityType?: string;

  @ApiPropertyOptional({ description: 'Filter by action, e.g. "CREATE", "UPDATE", "DELETE"' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  action?: string;

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
  @Max(200, { message: 'Limit cannot exceed 200' })
  @Type(() => Number)
  limit?: number;
}

export class AuditLogEntryDto {
  id: string;
  action: string;
  entityType: string;
  entityId: string | null;
  userName: string | null;
  createdAt: Date;
}

export class PaginatedAuditLogDto {
  items: AuditLogEntryDto[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}
