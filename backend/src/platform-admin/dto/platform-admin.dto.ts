import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Max,
  MaxLength,
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

export class UpdateTenantLicenseDto {
  @ApiPropertyOptional({
    enum: ['off', 'warn', 'enforce'],
    description:
      'off = report only (default), warn = log would-be blocks, enforce = refuse unlicensed modules/limits',
  })
  @IsOptional()
  @IsIn(['off', 'warn', 'enforce'])
  enforcement?: 'off' | 'warn' | 'enforce';

  @ApiPropertyOptional({
    example: { aiAssistant: true, analytics: false },
    description: 'Per-module grant (true) or revoke (false); null clears the override',
  })
  @IsOptional()
  @IsObject()
  overrides?: Record<string, boolean | null>;

  @ApiPropertyOptional({ example: '2027-01-01T00:00:00Z', nullable: true })
  @IsOptional()
  @IsString()
  validUntil?: string | null;

  @ApiPropertyOptional({ example: 3, nullable: true })
  @IsOptional()
  @IsInt()
  @Min(1)
  maxBranches?: number | null;

  @ApiPropertyOptional({ example: 10, nullable: true })
  @IsOptional()
  @IsInt()
  @Min(1)
  maxUsers?: number | null;

  @ApiPropertyOptional({ example: 'Setup fee outstanding since 12 Oct' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string | null;

  @ApiPropertyOptional({ description: 'Issue a fresh licence key' })
  @IsOptional()
  @IsBoolean()
  reissueKey?: boolean;
}
