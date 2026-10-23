import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsOptional,
  IsString,
  Matches,
} from 'class-validator';

export class UpdateBillingSettingsDto {
  @ApiPropertyOptional({ example: true })
  @IsOptional()
  @IsBoolean()
  autoRenewEnabled?: boolean;

  @ApiPropertyOptional({ example: '2026-10-23-v1' })
  @IsOptional()
  @IsString()
  autoRenewAuthorizationVersion?: string;

  @ApiPropertyOptional({
    example: '254712345678',
    description: 'Kenyan mobile number that receives the renewal STK push. Pass null to clear.',
    nullable: true,
  })
  @IsOptional()
  @IsString()
  @Matches(/^(?:\+?254|0)?(?:7|1)\d{8}$/, {
    message: 'billingPhone must be a valid Kenyan mobile number',
  })
  billingPhone?: string | null;
}
