import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';

const MODES = ['OFF', 'FLAG', 'BLOCK'];

export class PriceGuardSettingsDto {
  @ApiPropertyOptional({ enum: MODES })
  @IsOptional()
  @IsIn(MODES)
  mode?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(500)
  minMarginPercent?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  maxCashierDiscountPercent?: number;
}

export class CreditSettingsDto {
  @ApiPropertyOptional({ enum: MODES })
  @IsOptional()
  @IsIn(MODES)
  mode?: string;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100_000_000)
  defaultLimit?: number | null;

  @ApiPropertyOptional({ nullable: true })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(3650)
  blockWhenOverdueDays?: number | null;
}

export class AlertThresholdsDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  pushHigh?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  voidAlertAmount?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  refundAlertAmount?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  stockWriteOffValue?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  cashShortAmount?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(1000)
  priceChangePercent?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  stocktakeVarianceValue?: number;
}

export class DailySummarySettingsDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @ApiPropertyOptional({ description: 'Local hour 0-23 the summary is sent' })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(23)
  hourLocal?: number;
}

export class StocktakeSettingsDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  separateApprover?: boolean;
}

export class UpdateAccountabilitySettingsDto {
  @ApiPropertyOptional({ type: PriceGuardSettingsDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => PriceGuardSettingsDto)
  priceGuard?: PriceGuardSettingsDto;

  @ApiPropertyOptional({ type: CreditSettingsDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => CreditSettingsDto)
  credit?: CreditSettingsDto;

  @ApiPropertyOptional({ type: AlertThresholdsDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => AlertThresholdsDto)
  alerts?: AlertThresholdsDto;

  @ApiPropertyOptional({ type: DailySummarySettingsDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => DailySummarySettingsDto)
  dailySummary?: DailySummarySettingsDto;

  @ApiPropertyOptional({ type: StocktakeSettingsDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => StocktakeSettingsDto)
  stocktake?: StocktakeSettingsDto;
}

export class AlertsQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4')
  branchId?: string;

  @ApiPropertyOptional({ enum: ['LOW', 'MEDIUM', 'HIGH'] })
  @IsOptional()
  @IsIn(['LOW', 'MEDIUM', 'HIGH'])
  severity?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  type?: string;

  @ApiPropertyOptional({ description: 'Only alerts not yet acknowledged' })
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true' || value === '1')
  @IsBoolean()
  open?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}

export class AcknowledgeAlertsDto {
  @ApiPropertyOptional({ description: 'Alert ids; omit with all=true to clear everything' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @IsUUID('4', { each: true })
  ids?: string[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  all?: boolean;
}
