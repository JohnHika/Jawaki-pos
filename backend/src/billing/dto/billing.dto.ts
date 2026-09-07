import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  Min,
  MinLength,
  MaxLength,
} from 'class-validator';

export class UpdateBillingSettingsDto {
  @ApiPropertyOptional({ example: true })
  @IsOptional()
  @IsBoolean()
  autoRenewEnabled?: boolean;

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

export class SubmitPaymentDto {
  @ApiProperty({ example: 'QGH7XYZ92K' })
  @IsString()
  @MinLength(8)
  @MaxLength(15)
  mpesaCode!: string;

  @ApiPropertyOptional({ example: 3200 })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(9999999)
  amount?: number;
}

export class ConfirmPaymentClaimDto {
  @ApiProperty({ example: true })
  @IsBoolean()
  approve!: boolean;
}