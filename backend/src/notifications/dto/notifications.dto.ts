import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class RegisterPushTokenDto {
  @ApiProperty({ description: 'FCM registration token from the device' })
  @IsString()
  @MinLength(1, { message: 'Token is required' })
  @MaxLength(4096, { message: 'Token is too long' })
  token: string;

  @ApiPropertyOptional({ description: 'Device UUID, if known' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  deviceUuid?: string;

  @ApiPropertyOptional({ enum: ['android', 'ios'], default: 'android' })
  @IsOptional()
  @IsIn(['android', 'ios'])
  platform?: string;
}

export class UnregisterPushTokenDto {
  @ApiProperty({ description: 'FCM registration token to remove' })
  @IsString()
  @MinLength(1, { message: 'Token is required' })
  @MaxLength(4096)
  token: string;
}
