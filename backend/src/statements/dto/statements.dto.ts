import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsIn,
  IsInt,
  IsNumber,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class StatementTargetDto {
  @ApiPropertyOptional({
    description: 'A customer who owes on credit sales; legacy offline IDs are supported',
  })
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  customerId?: string;

  @ApiPropertyOptional({ description: 'A peer shop that owes on a B2B debt' })
  @IsOptional()
  @IsUUID('4')
  debtorId?: string;
}

export class CreateStatementLinkDto extends StatementTargetDto {
  @ApiPropertyOptional({ description: 'A personal note shown at the top of the page' })
  @IsOptional()
  @IsString()
  @MaxLength(280)
  message?: string;

  @ApiPropertyOptional({ default: 14, description: 'How many days the link works for' })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(60)
  @Type(() => Number)
  days?: number;
}

export class UpdateStatementSettingsDto {
  @ApiPropertyOptional({ description: 'How customers pay: paybill / till number, account, bank' })
  @IsOptional()
  @IsString()
  @MaxLength(400)
  payInstructions?: string;

  @ApiPropertyOptional({ description: 'Phone shown on statements' })
  @IsOptional()
  @IsString()
  @MaxLength(30)
  phone?: string;
}

export class ClaimsQueryDto {
  @ApiPropertyOptional({ enum: ['PENDING', 'CONFIRMED', 'REJECTED'] })
  @IsOptional()
  @IsIn(['PENDING', 'CONFIRMED', 'REJECTED'])
  status?: string;
}

export class LinksQueryDto extends StatementTargetDto {}

export class DecideClaimDto {
  @ApiProperty({ enum: ['CONFIRM', 'REJECT'] })
  @IsIn(['CONFIRM', 'REJECT'])
  action: 'CONFIRM' | 'REJECT';

  @ApiPropertyOptional({ description: 'Amount actually received, if different from what was claimed' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(10_000_000)
  @Type(() => Number)
  amount?: number;
}

/** What the person opening the link sends back. */
export class PublicClaimDto {
  @ApiProperty({ enum: ['PAID', 'PROMISE'] })
  @IsIn(['PAID', 'PROMISE'])
  kind: 'PAID' | 'PROMISE';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9]{8,12}$/, { message: 'That does not look like an M-Pesa code' })
  mpesaCode?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(10_000_000)
  @Type(() => Number)
  amount?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  promisedFor?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  payerName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;
}
