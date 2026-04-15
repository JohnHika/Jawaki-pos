import {
  IsBoolean,
  IsOptional,
  IsString,
  IsObject,
  IsEmail,
  IsUUID,
  MaxLength,
  MinLength,
  Matches,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';

// Tenant DTOs
export class CreateTenantDto {
  @ApiProperty({ example: 'Acme Stores' })
  @IsString()
  @MinLength(2, { message: 'Tenant name must be at least 2 characters' })
  @MaxLength(100, { message: 'Tenant name must not exceed 100 characters' })
  @Matches(/^[a-zA-Z0-9\s&'-]+$/, { message: 'Tenant name contains invalid characters' })
  name: string;

  @ApiProperty({ example: 'acme-stores' })
  @IsString()
  @MinLength(2, { message: 'Slug must be at least 2 characters' })
  @MaxLength(50, { message: 'Slug must not exceed 50 characters' })
  @Matches(/^[a-z0-9]+(-[a-z0-9]+)*$/, { message: 'Slug must be lowercase alphanumeric with hyphens' })
  slug: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500, { message: 'Logo URL must not exceed 500 characters' })
  @Matches(/^https?:\/\/.+/i, { message: 'Logo must be a valid URL' })
  logo?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  settings?: Record<string, any>;
}

export class UpdateTenantDto extends PartialType(CreateTenantDto) {}

// Branch DTOs
export class CreateBranchDto {
  @ApiProperty({ example: 'Main Street Store' })
  @IsString()
  @MinLength(2, { message: 'Branch name must be at least 2 characters' })
  @MaxLength(100, { message: 'Branch name must not exceed 100 characters' })
  @Matches(/^[a-zA-Z0-9\s&'-]+$/, { message: 'Branch name contains invalid characters' })
  name: string;

  @ApiProperty({ example: 'MSS001' })
  @IsString()
  @MinLength(2, { message: 'Branch code must be at least 2 characters' })
  @MaxLength(20, { message: 'Branch code must not exceed 20 characters' })
  @Matches(/^[a-zA-Z0-9_-]+$/, { message: 'Branch code can only contain letters, numbers, hyphens, and underscores' })
  code: string;

  @ApiPropertyOptional({ example: '123 Main Street, Nairobi' })
  @IsOptional()
  @IsString()
  @MaxLength(200, { message: 'Address must not exceed 200 characters' })
  address?: string;

  @ApiPropertyOptional({ example: '+254712345678' })
  @IsOptional()
  @IsString()
  @MaxLength(20, { message: 'Phone number must not exceed 20 characters' })
  @Matches(/^\+?[\d\s-()]+$/, { message: 'Invalid phone number format' })
  phone?: string;

  @ApiPropertyOptional({ example: 'main@store.com' })
  @IsOptional()
  @IsEmail({}, { message: 'Invalid email format' })
  @MaxLength(255, { message: 'Email must not exceed 255 characters' })
  email?: string;

  @ApiPropertyOptional({ example: 'Africa/Nairobi' })
  @IsOptional()
  @IsString()
  @MaxLength(50, { message: 'Timezone must not exceed 50 characters' })
  @Matches(/^[a-zA-Z0-9/_+-]+$/, { message: 'Invalid timezone format' })
  timezone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  settings?: Record<string, any>;
}

export class UpdateBranchDto extends PartialType(CreateBranchDto) {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

// Device DTOs
export class RegisterDeviceDto {
  @ApiProperty({ description: 'Unique device UUID from the mobile app' })
  @IsUUID('4', { message: 'Device UUID must be a valid UUID' })
  deviceUuid: string;

  @ApiProperty({ example: 'POS Terminal 1' })
  @IsString()
  @MinLength(2, { message: 'Device name must be at least 2 characters' })
  @MaxLength(100, { message: 'Device name must not exceed 100 characters' })
  name: string;

  @ApiPropertyOptional({ example: 'Samsung Galaxy Tab A8' })
  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Model must not exceed 100 characters' })
  model?: string;

  @ApiPropertyOptional({ example: 'Android 13' })
  @IsOptional()
  @IsString()
  @MaxLength(50, { message: 'OS version must not exceed 50 characters' })
  osVersion?: string;

  @ApiPropertyOptional({ example: '1.2.0' })
  @IsOptional()
  @IsString()
  @MaxLength(20, { message: 'App version must not exceed 20 characters' })
  @Matches(/^\d+\.\d+\.\d+.*$/, { message: 'App version must be in semantic versioning format' })
  appVersion?: string;

  @ApiProperty({ description: 'Branch ID to assign device to' })
  @IsUUID('4', { message: 'Branch ID must be a valid UUID' })
  branchId: string;
}

export class UpdateDeviceDto {
  @ApiPropertyOptional({ example: 'POS Terminal 1' })
  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Device name must not exceed 100 characters' })
  name?: string;

  @ApiPropertyOptional({ example: '1.3.0' })
  @IsOptional()
  @IsString()
  @MaxLength(20, { message: 'App version must not exceed 20 characters' })
  @Matches(/^\d+\.\d+\.\d+.*$/, { message: 'App version must be in semantic versioning format' })
  appVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

// Response DTOs (no validation needed)
export class BranchResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  name: string;

  @ApiProperty()
  code: string;

  @ApiProperty()
  address?: string;

  @ApiProperty()
  phone?: string;

  @ApiProperty()
  email?: string;

  @ApiProperty()
  timezone: string;

  @ApiProperty()
  isActive: boolean;

  @ApiProperty()
  settings: Record<string, any>;

  @ApiProperty()
  deviceCount?: number;

  @ApiProperty()
  userCount?: number;
}

export class DeviceResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  deviceUuid: string;

  @ApiProperty()
  name: string;

  @ApiProperty()
  model?: string;

  @ApiProperty()
  osVersion?: string;

  @ApiProperty()
  appVersion?: string;

  @ApiProperty()
  lastSyncAt?: Date;

  @ApiProperty()
  isActive: boolean;

  @ApiProperty()
  branchId: string;

  @ApiProperty()
  branchName?: string;
}
