import { IsBoolean, IsOptional, IsString, IsObject } from 'class-validator';
import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';

// Tenant DTOs
export class CreateTenantDto {
  @ApiProperty({ example: 'Acme Stores' })
  @IsString()
  name: string;

  @ApiProperty({ example: 'acme-stores' })
  @IsString()
  slug: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
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
  name: string;

  @ApiProperty({ example: 'MSS001' })
  @IsString()
  code: string;

  @ApiPropertyOptional({ example: '123 Main Street, Nairobi' })
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional({ example: '+254712345678' })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional({ example: 'main@store.com' })
  @IsOptional()
  @IsString()
  email?: string;

  @ApiPropertyOptional({ example: 'Africa/Nairobi' })
  @IsOptional()
  @IsString()
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
  @IsString()
  deviceUuid: string;

  @ApiProperty({ example: 'POS Terminal 1' })
  @IsString()
  name: string;

  @ApiPropertyOptional({ example: 'Samsung Galaxy Tab A8' })
  @IsOptional()
  @IsString()
  model?: string;

  @ApiPropertyOptional({ example: 'Android 13' })
  @IsOptional()
  @IsString()
  osVersion?: string;

  @ApiPropertyOptional({ example: '1.2.0' })
  @IsOptional()
  @IsString()
  appVersion?: string;

  @ApiProperty({ description: 'Branch ID to assign device to' })
  @IsString()
  branchId: string;
}

export class UpdateDeviceDto {
  @ApiPropertyOptional({ example: 'POS Terminal 1' })
  @IsOptional()
  @IsString()
  name?: string;

  @ApiPropertyOptional({ example: '1.3.0' })
  @IsOptional()
  @IsString()
  appVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

// Response DTOs
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
