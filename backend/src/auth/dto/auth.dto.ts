import {
  IsEmail,
  IsBoolean,
  IsEnum,
  IsNotEmpty,
  IsOptional,
  IsString,
  MinLength,
  MaxLength,
  Matches,
  IsUUID,
  IsArray,
  IsObject,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { LegacyUserRole } from '@prisma/client';

export class LoginDto {
  @ApiProperty({ example: 'admin@store.com' })
  @IsEmail({}, { message: 'Invalid email format' })
  @MaxLength(255, { message: 'Email must not exceed 255 characters' })
  email: string;

  @ApiProperty({ example: 'password123' })
  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters' })
  @MaxLength(128, { message: 'Password must not exceed 128 characters' })
  password: string;

  @ApiPropertyOptional({ description: 'Device UUID for mobile login' })
  @IsOptional()
  @IsUUID('4', { message: 'Device ID must be a valid UUID' })
  deviceId?: string;

  @ApiPropertyOptional({ description: 'Company/Tenant ID. Use when one email exists in multiple companies.' })
  @IsOptional()
  @IsUUID('4', { message: 'Tenant ID must be a valid UUID' })
  tenantId?: string;

  @ApiPropertyOptional({ example: 'acme-stores', description: 'Company/Tenant slug for multi-company login' })
  @IsOptional()
  @IsString()
  @MinLength(2, { message: 'Tenant slug must be at least 2 characters' })
  @MaxLength(50, { message: 'Tenant slug must not exceed 50 characters' })
  @Matches(/^[a-z0-9]+(-[a-z0-9]+)*$/, {
    message: 'Tenant slug must be lowercase alphanumeric with hyphens',
  })
  tenantSlug?: string;

  @ApiPropertyOptional({ description: 'Branch ID for context' })
  @IsOptional()
  @IsUUID('4', { message: 'Branch ID must be a valid UUID' })
  branchId?: string;
}

export class PinLoginDto {
  @ApiProperty({ example: '1234' })
  @IsString()
  @MinLength(4, { message: 'PIN must be at least 4 digits' })
  @MaxLength(6, { message: 'PIN must not exceed 6 digits' })
  @Matches(/^\d{4,6}$/, { message: 'PIN must contain only 4-6 digits' })
  pin: string;

  @ApiProperty({ description: 'Device UUID' })
  @IsUUID('4', { message: 'Device ID must be a valid UUID v4' })
  deviceId: string;

  @ApiPropertyOptional({ description: 'Branch ID. Optional when device is already registered to a branch.' })
  @IsUUID('4', { message: 'Branch ID must be a valid UUID v4' })
  @IsOptional()
  branchId?: string;
}

export class RegisterDto {
  @ApiProperty({ example: 'admin@store.com' })
  @IsEmail({}, { message: 'Invalid email format' })
  @MaxLength(255, { message: 'Email must not exceed 255 characters' })
  email: string;

  @ApiProperty({ example: 'password123' })
  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters' })
  @MaxLength(128, { message: 'Password must not exceed 128 characters' })
  @Matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/, {
    message: 'Password must contain at least one uppercase letter, one lowercase letter, and one number',
  })
  password: string;

  @ApiProperty({ example: 'John' })
  @IsString()
  @IsNotEmpty({ message: 'First name is required' })
  @MaxLength(100, { message: 'First name must not exceed 100 characters' })
  @Matches(/^[a-zA-Z\s'-]+$/, { message: 'First name can only contain letters, spaces, hyphens, and apostrophes' })
  firstName: string;

  @ApiProperty({ example: 'Doe' })
  @IsString()
  @IsNotEmpty({ message: 'Last name is required' })
  @MaxLength(100, { message: 'Last name must not exceed 100 characters' })
  @Matches(/^[a-zA-Z\s'-]+$/, { message: 'Last name can only contain letters, spaces, hyphens, and apostrophes' })
  lastName: string;

  @ApiPropertyOptional({ example: '+254712345678' })
  @IsOptional()
  @IsString()
  @MaxLength(20, { message: 'Phone number must not exceed 20 characters' })
  @Matches(/^\+?[\d\s-()]+$/, { message: 'Invalid phone number format' })
  phone?: string;

  @ApiPropertyOptional({ enum: LegacyUserRole, default: LegacyUserRole.CASHIER })
  @IsOptional()
  @IsEnum(LegacyUserRole, { message: 'Invalid role' })
  role?: LegacyUserRole;

  @ApiProperty({ description: 'Tenant ID' })
  @IsUUID('4', { message: 'Tenant ID must be a valid UUID' })
  tenantId: string;

  @ApiPropertyOptional({ description: 'Branch IDs to assign' })
  @IsOptional()
  @IsArray()
  @IsUUID('4', { each: true, message: 'Each branch ID must be a valid UUID' })
  branchIds?: string[];
}

export class RegisterCompanyBranchDto {
  @ApiProperty({ example: 'Main Shop' })
  @IsString()
  @MinLength(2, { message: 'Branch name must be at least 2 characters' })
  @MaxLength(100, { message: 'Branch name must not exceed 100 characters' })
  @Matches(/^[a-zA-Z0-9\s&'-]+$/, { message: 'Branch name contains invalid characters' })
  name: string;

  @ApiPropertyOptional({ example: 'MAIN' })
  @IsOptional()
  @IsString()
  @MinLength(2, { message: 'Branch code must be at least 2 characters' })
  @MaxLength(20, { message: 'Branch code must not exceed 20 characters' })
  @Matches(/^[a-zA-Z0-9_-]+$/, {
    message: 'Branch code can only contain letters, numbers, hyphens, and underscores',
  })
  code?: string;

  @ApiPropertyOptional({ example: 'Nairobi, Kenya' })
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

  @ApiPropertyOptional({ example: 'shop@acme.co.ke' })
  @IsOptional()
  @IsEmail({}, { message: 'Invalid email format' })
  @MaxLength(255, { message: 'Email must not exceed 255 characters' })
  email?: string;
}

export class RegisterCompanyAdminDto {
  @ApiProperty({ example: 'owner@acme.co.ke' })
  @IsEmail({}, { message: 'Invalid email format' })
  @MaxLength(255, { message: 'Email must not exceed 255 characters' })
  email: string;

  @ApiProperty({ example: 'SecurePass1' })
  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters' })
  @MaxLength(128, { message: 'Password must not exceed 128 characters' })
  @Matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/, {
    message: 'Password must contain at least one uppercase letter, one lowercase letter, and one number',
  })
  password: string;

  @ApiProperty({ example: 'John' })
  @IsString()
  @IsNotEmpty({ message: 'First name is required' })
  @MaxLength(100, { message: 'First name must not exceed 100 characters' })
  @Matches(/^[a-zA-Z\s'-]+$/, { message: 'First name can only contain letters, spaces, hyphens, and apostrophes' })
  firstName: string;

  @ApiProperty({ example: 'Doe' })
  @IsString()
  @IsNotEmpty({ message: 'Last name is required' })
  @MaxLength(100, { message: 'Last name must not exceed 100 characters' })
  @Matches(/^[a-zA-Z\s'-]+$/, { message: 'Last name can only contain letters, spaces, hyphens, and apostrophes' })
  lastName: string;

  @ApiPropertyOptional({ example: '+254712345678' })
  @IsOptional()
  @IsString()
  @MaxLength(20, { message: 'Phone number must not exceed 20 characters' })
  @Matches(/^\+?[\d\s-()]+$/, { message: 'Invalid phone number format' })
  phone?: string;
}

export class RegisterCompanyDto {
  @ApiProperty({ example: 'Acme Stores' })
  @IsString()
  @MinLength(2, { message: 'Company name must be at least 2 characters' })
  @MaxLength(100, { message: 'Company name must not exceed 100 characters' })
  @Matches(/^[a-zA-Z0-9\s&'-]+$/, { message: 'Company name contains invalid characters' })
  companyName: string;

  @ApiPropertyOptional({ example: 'acme-stores' })
  @IsOptional()
  @IsString()
  @MinLength(2, { message: 'Company slug must be at least 2 characters' })
  @MaxLength(50, { message: 'Company slug must not exceed 50 characters' })
  @Matches(/^[a-z0-9]+(-[a-z0-9]+)*$/, {
    message: 'Company slug must be lowercase alphanumeric with hyphens',
  })
  companySlug?: string;

  @ApiPropertyOptional({ description: 'Company logo URL, usually returned by Cloudinary after upload' })
  @IsOptional()
  @IsString()
  @MaxLength(500, { message: 'Logo URL must not exceed 500 characters' })
  @Matches(/^https?:\/\/.+/i, { message: 'Logo must be a valid URL' })
  logo?: string;

  @ApiPropertyOptional({ description: 'Cloudinary public ID for the company logo' })
  @IsOptional()
  @IsString()
  @MaxLength(255, { message: 'Logo public ID must not exceed 255 characters' })
  logoPublicId?: string;

  @ApiPropertyOptional({ description: 'Initial company settings' })
  @IsOptional()
  @IsObject()
  settings?: Record<string, any>;

  @ApiPropertyOptional({ description: 'Device UUID for immediately binding the first session' })
  @IsOptional()
  @IsUUID('4', { message: 'Device ID must be a valid UUID' })
  deviceId?: string;

  @ApiProperty({ type: RegisterCompanyBranchDto })
  @ValidateNested()
  @Type(() => RegisterCompanyBranchDto)
  branch: RegisterCompanyBranchDto;

  @ApiProperty({ type: RegisterCompanyAdminDto })
  @ValidateNested()
  @Type(() => RegisterCompanyAdminDto)
  admin: RegisterCompanyAdminDto;
}

export class RefreshTokenDto {
  // Refresh tokens are generated as plain UUIDv4 (36 chars) — see
  // AuthService.generateTokens. MinLength must stay <= 36 or every refresh
  // ever issued fails validation here before the service even runs.
  @ApiProperty()
  @IsString()
  @MinLength(36, { message: 'Invalid refresh token format' })
  @MaxLength(256, { message: 'Refresh token is too long' })
  refreshToken: string;
}

export class LogoutDto {
  // Same UUIDv4 format as RefreshTokenDto — see comment there.
  @ApiPropertyOptional({ description: 'Current device refresh token for session-scoped logout' })
  @IsOptional()
  @IsString()
  @MinLength(36, { message: 'Invalid refresh token format' })
  @MaxLength(256, { message: 'Refresh token is too long' })
  refreshToken?: string;

  @ApiPropertyOptional({
    description: 'When true, revoke all active sessions for the user',
    default: false,
  })
  @IsOptional()
  @IsBoolean()
  allDevices?: boolean;
}

export class ChangePasswordDto {
  @ApiProperty()
  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters' })
  @MaxLength(128, { message: 'Password must not exceed 128 characters' })
  currentPassword: string;

  @ApiProperty()
  @IsString()
  @MinLength(8, { message: 'New password must be at least 8 characters' })
  @MaxLength(128, { message: 'Password must not exceed 128 characters' })
  @Matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/, {
    message: 'Password must contain at least one uppercase letter, one lowercase letter, and one number',
  })
  newPassword: string;
}

export class SetPinDto {
  @ApiProperty({ example: '1234' })
  @IsString()
  @MinLength(4, { message: 'PIN must be at least 4 digits' })
  @MaxLength(6, { message: 'PIN must not exceed 6 digits' })
  @Matches(/^\d{4,6}$/, { message: 'PIN must contain only 4-6 digits' })
  pin: string;
}

// Authorizes logging into a phone-acting-as-local-server (offline mode)
// as this user — separate from SetPinDto's online quick-login PIN.
export class SetOfflineAccessPinDto {
  @ApiProperty({ example: '1234' })
  @IsString()
  @MinLength(4, { message: 'PIN must be at least 4 digits' })
  @MaxLength(6, { message: 'PIN must not exceed 6 digits' })
  @Matches(/^\d{4,6}$/, { message: 'PIN must contain only 4-6 digits' })
  pin: string;
}

export class AuthResponseDto {
  @ApiProperty()
  accessToken: string;

  @ApiProperty()
  refreshToken: string;

  @ApiProperty()
  expiresIn: number;

  @ApiProperty()
  user: {
    id: string;
    email: string;
    firstName: string;
    lastName: string;
    role: LegacyUserRole;
    tenantId: string;
    tenantSlug?: string;
    branchId?: string;
    branchName?: string;
    hasPinSet: boolean;
    permissions: string[];
    tenant?: {
      id: string;
      name: string;
      slug: string;
      logo?: string;
      logoPublicId?: string;
      settings?: Record<string, any>;
      isActive: boolean;
    };
    branches: Array<{ id: string; name: string; isPrimary: boolean }>;
  };
}

export class CompanyInfoResponseDto {
  @ApiProperty({ example: 'Acme Stores' })
  name: string;

  @ApiPropertyOptional({ description: 'Company logo URL' })
  logoUrl?: string;

  @ApiPropertyOptional({ description: 'Company logo Cloudinary public ID' })
  logoPublicId?: string;

  @ApiProperty({ example: true })
  isActive: boolean;
}
