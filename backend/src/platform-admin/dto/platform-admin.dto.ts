import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class PlatformAdminLoginDto {
  @ApiProperty({ example: 'admin@jawaki.co.ke' })
  @IsString()
  @IsNotEmpty()
  email!: string;

  @ApiProperty({ example: 'change-me' })
  @IsString()
  @IsNotEmpty()
  password!: string;
}

export class ExtendTenantDto {
  @ApiProperty({ example: 7, minimum: 1, maximum: 365 })
  @IsInt()
  @Min(1)
  @Max(365)
  days!: number;
}

export class CreditTenantDto {
  @ApiProperty({ example: 1500, minimum: 1 })
  @IsNumber()
  @Min(1)
  amountKes!: number;

  @ApiProperty({ example: 'Goodwill credit for October downtime' })
  @IsString()
  @IsNotEmpty()
  reason!: string;
}

export class MarkInvoicePaidDto {
  @ApiPropertyOptional({ example: 'SBX12AB34CD' })
  @IsOptional()
  @IsString()
  mpesaCode?: string;
}

export class ListTenantsQueryDto {
  @ApiPropertyOptional({ enum: ['ACTIVE', 'TRIAL', 'PAST_DUE', 'SUSPENDED', 'CANCELLED'] })
  @IsOptional()
  @IsString()
  status?: string;

  @ApiPropertyOptional({ description: 'Matches tenant name (case-insensitive)' })
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize?: number = 20;
}

export class ListInvoicesQueryDto {
  @ApiPropertyOptional({ enum: ['PENDING', 'PAID'] })
  @IsOptional()
  @IsString()
  status?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  tenantId?: string;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize?: number = 20;
}