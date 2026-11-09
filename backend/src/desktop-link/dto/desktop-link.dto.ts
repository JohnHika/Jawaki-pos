import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, Length, Matches } from 'class-validator';

export class StartDesktopLinkDto {
  @ApiPropertyOptional({ description: 'Computer name shown on the phone' })
  @IsOptional()
  @IsString()
  @Length(0, 80)
  desktopName?: string;

  @ApiPropertyOptional({ description: 'windows, macos or linux' })
  @IsOptional()
  @IsString()
  @Length(0, 20)
  platform?: string;

  @ApiProperty({
    description: 'SHA-256 (hex) of a random verifier the computer keeps',
  })
  @Matches(/^[a-fA-F0-9]{64}$/, { message: 'claimChallenge must be a SHA-256 hex digest' })
  claimChallenge!: string;
}

export class PreviewDesktopLinkDto {
  @ApiPropertyOptional({ description: 'QR text as scanned' })
  @IsOptional()
  @IsString()
  @Length(10, 1024)
  payload?: string;

  @ApiPropertyOptional({ description: '6-digit code shown on the computer' })
  @IsOptional()
  @Matches(/^\s*\d{3}\s?\d{3}\s*$/, { message: 'Enter the 6-digit code from the computer' })
  code?: string;
}

export class DecideDesktopLinkDto {
  @ApiProperty()
  @IsString()
  @Length(8, 64)
  linkId!: string;

  @ApiPropertyOptional({ enum: ['approve', 'deny'], default: 'approve' })
  @IsOptional()
  @IsIn(['approve', 'deny'])
  decision?: 'approve' | 'deny';

  @ApiPropertyOptional({
    description: 'Approver PIN, needed when the computer is on another connection',
  })
  @IsOptional()
  @Matches(/^\d{4,8}$/, { message: 'PIN must be 4 to 8 digits' })
  pin?: string;
}

export class ClaimDesktopLinkDto {
  @ApiProperty()
  @IsString()
  @Length(8, 64)
  linkId!: string;

  @ApiProperty({ description: 'The verifier whose SHA-256 was sent to start' })
  @IsString()
  @Length(32, 256)
  verifier!: string;

  @ApiPropertyOptional({ description: 'This computer’s Counterbase device id' })
  @IsOptional()
  @IsString()
  @Length(0, 120)
  deviceId?: string;
}
