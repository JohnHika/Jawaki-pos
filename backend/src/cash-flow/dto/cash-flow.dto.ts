import { IsEnum, IsOptional, IsNumber, Min, IsString } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export enum CashFlowMode {
  CASH_ONLY = 'CASH_ONLY',
  ALL_REVENUE = 'ALL_REVENUE',
  RUNNING_BALANCE = 'RUNNING_BALANCE',
}

export enum CashEntryType {
  SALE_CASH_IN = 'SALE_CASH_IN',
  RESTOCK_OUT = 'RESTOCK_OUT',
  EXPENSE_OUT = 'EXPENSE_OUT',
  MANUAL_ADJUSTMENT = 'MANUAL_ADJUSTMENT',
  OPENING_BALANCE = 'OPENING_BALANCE',
}

export class UpdateCashSettingsDto {
  @ApiProperty({ enum: CashFlowMode })
  @IsEnum(CashFlowMode, { message: 'Invalid cash flow mode' })
  mode: CashFlowMode;
}

export class AdjustCashLedgerDto {
  @ApiProperty({ description: 'Positive to add cash, negative to remove', example: 1000 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Type(() => Number)
  amount: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  note?: string;
}

export class CashLedgerQueryDto {
  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsNumber({}, { message: 'Page must be a number' })
  @Min(1)
  @Type(() => Number)
  page?: number;

  @ApiPropertyOptional({ default: 50 })
  @IsOptional()
  @IsNumber({}, { message: 'Limit must be a number' })
  @Min(1)
  @Type(() => Number)
  limit?: number;
}

export class AvailableCashResponseDto {
  @ApiProperty({ enum: CashFlowMode })
  mode: CashFlowMode;

  @ApiProperty()
  availableCash: number;

  @ApiProperty()
  todaysCashIn: number;

  @ApiProperty()
  todaysCashOut: number;

  @ApiProperty()
  breakdown: {
    salesCashIn?: number;
    allRevenue?: number;
    restockOut: number;
    expenseOut: number;
    manualAdjustment: number;
    runningBalance?: number;
  };
}
