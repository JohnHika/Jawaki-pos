import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, Length, Matches } from 'class-validator';

export class ScanApproveDto {
  @ApiProperty({ description: 'Full QR payload string as scanned' })
  @IsString()
  @Length(10, 4096)
  payload!: string;

  @ApiPropertyOptional({
    enum: ['approve', 'deny'],
    default: 'approve',
    description: 'Approve or deny the desktop sign-in request',
  })
  @IsOptional()
  @IsIn(['approve', 'deny'])
  decision?: 'approve' | 'deny';

  @ApiPropertyOptional({
    enum: ['approval', 'pin'],
    default: 'approval',
    description: 'pin requires the approver PIN to confirm',
  })
  @IsOptional()
  @IsIn(['approval', 'pin'])
  mode?: 'approval' | 'pin';

  @ApiPropertyOptional({ description: 'Approving device label' })
  @IsOptional()
  @IsString()
  @Length(0, 80)
  deviceName?: string;

  @ApiPropertyOptional({ description: 'Approver PIN, required in pin mode' })
  @IsOptional()
  @IsString()
  @Matches(/^\d{4,8}$/, { message: 'PIN must be 4 to 8 digits' })
  pin?: string;
}

export class CodeApproveDto {
  @ApiProperty({ description: '6-digit code shown under the desktop QR' })
  @Matches(/^\d{6}$/, { message: 'Code must be 6 digits' })
  code!: string;

  @ApiPropertyOptional({
    enum: ['approve', 'deny'],
    default: 'approve',
    description: 'Approve or deny the desktop sign-in request',
  })
  @IsOptional()
  @IsIn(['approve', 'deny'])
  decision?: 'approve' | 'deny';

  @ApiPropertyOptional({
    enum: ['approval', 'pin'],
    default: 'approval',
    description: 'pin requires the approver PIN to confirm',
  })
  @IsOptional()
  @IsIn(['approval', 'pin'])
  mode?: 'approval' | 'pin';

  @ApiPropertyOptional({ description: 'Approving device label' })
  @IsOptional()
  @IsString()
  @Length(0, 80)
  deviceName?: string;

  @ApiPropertyOptional({ description: 'Approver PIN, required in pin mode' })
  @IsOptional()
  @IsString()
  @Matches(/^\d{4,8}$/, { message: 'PIN must be 4 to 8 digits' })
  pin?: string;
}
