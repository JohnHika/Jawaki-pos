import { IsEmail, IsNotEmpty, IsObject, IsOptional, IsString, IsUUID, Matches, MaxLength, MinLength, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class WorkspaceBranchDto {
  @IsString() @MinLength(2) @MaxLength(100)
  name: string;
  @IsOptional() @IsString() @MinLength(2) @MaxLength(20)
  code?: string;
  @IsOptional() @IsString() @MaxLength(200)
  address?: string;
  @IsOptional() @IsString() @MaxLength(20)
  phone?: string;
  @IsOptional() @IsEmail()
  email?: string;
}

export class CreateWorkspaceBaseDto {
  @IsString() @MinLength(2) @MaxLength(100)
  companyName: string;
  @IsOptional() @IsString() @Matches(/^[a-z0-9]+(-[a-z0-9]+)*$/)
  companySlug?: string;
  @IsString() @MinLength(1) @MaxLength(100)
  firstName: string;
  @IsString() @MinLength(1) @MaxLength(100)
  lastName: string;
  @IsOptional() @IsString() @MaxLength(500)
  logo?: string;
  @IsOptional() @IsString() @MaxLength(255)
  logoPublicId?: string;
  @IsOptional() @IsObject()
  settings?: Record<string, unknown>;
  @IsOptional() @IsUUID('4')
  deviceId?: string;
  @ValidateNested() @Type(() => WorkspaceBranchDto)
  branch: WorkspaceBranchDto;
}

export class CreateGoogleWorkspaceDto extends CreateWorkspaceBaseDto {
  @IsString() @IsNotEmpty()
  idToken: string;
}

export class RequestWorkspaceOtpDto {
  @IsEmail()
  email: string;
}

export class CreateEmailWorkspaceDto extends CreateWorkspaceBaseDto {
  @IsEmail()
  email: string;
  @IsUUID('4')
  challengeId: string;
  @IsString() @Matches(/^\d{6,8}$/)
  code: string;
}
