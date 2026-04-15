import {
  IsEmail,
  IsEnum,
  IsNotEmpty,
  IsOptional,
  IsString,
  MinLength,
  MaxLength,
  Matches,
  IsUUID,
  IsArray,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { UserRole } from '@prisma/client';

export class LoginDto {
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

  @ApiPropertyOptional({ description: 'Device UUID for mobile login' })
  @IsOptional()
  @IsUUID('4', { message: 'Device ID must be a valid UUID' })
  deviceId?: string;

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
  @IsUUID('4', { message: 'Device ID must be a valid UUID' })
  deviceId: string;

  @ApiProperty({ description: 'Branch ID' })
  @IsUUID('4', { message: 'Branch ID must be a valid UUID' })
  branchId: string;
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

  @ApiPropertyOptional({ enum: UserRole, default: UserRole.CASHIER })
  @IsOptional()
  @IsEnum(UserRole, { message: 'Invalid role' })
  role?: UserRole;

  @ApiProperty({ description: 'Tenant ID' })
  @IsUUID('4', { message: 'Tenant ID must be a valid UUID' })
  tenantId: string;

  @ApiPropertyOptional({ description: 'Branch IDs to assign' })
  @IsOptional()
  @IsArray()
  @IsUUID('4', { each: true, message: 'Each branch ID must be a valid UUID' })
  branchIds?: string[];
}

export class RefreshTokenDto {
  @ApiProperty()
  @IsString()
  @MinLength(50, { message: 'Invalid refresh token format' })
  @MaxLength(256, { message: 'Refresh token is too long' })
  refreshToken: string;
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
    role: UserRole;
    tenantId: string;
    branches: Array<{ id: string; name: string; isPrimary: boolean }>;
  };
}
