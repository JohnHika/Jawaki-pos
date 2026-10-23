import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsDateString,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

export const ALLOCATION_BASES = ['VALUE', 'QUANTITY', 'CBM', 'WEIGHT'] as const;
export const SHIPMENT_STATUSES = ['PLANNED', 'IN_TRANSIT', 'ARRIVED', 'CANCELLED'] as const;
export const COST_TYPES = [
  'FREIGHT',
  'DUTY',
  'VAT',
  'IDF',
  'RDL',
  'CLEARING',
  'PORT_HANDLING',
  'TRANSPORT',
  'INSURANCE',
  'AGENT_FEE',
  'OTHER',
] as const;

const CURRENCY = /^[A-Za-z]{3}$/;

export class CreateShipmentDto {
  @ApiProperty()
  @IsUUID('4')
  branchId: string;

  @ApiProperty({ example: 'Container 40ft - kitchenware' })
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  title: string;

  @ApiPropertyOptional({ description: 'Container / bill of lading number' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  reference?: string;

  @ApiPropertyOptional({ example: 'Guangzhou, China' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  origin?: string;

  @ApiPropertyOptional({ example: 'USD', description: 'Currency the supplier priced the goods in' })
  @IsOptional()
  @Matches(CURRENCY, { message: 'Currency must be a 3-letter code such as USD or CNY' })
  currency?: string;

  @ApiPropertyOptional({ description: 'KES per 1 unit of the currency. Filled from live rates when omitted.' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 4 })
  @Min(0.0001)
  @Max(1_000_000)
  @Type(() => Number)
  fxRate?: number;

  @ApiPropertyOptional({ enum: ALLOCATION_BASES })
  @IsOptional()
  @IsIn(ALLOCATION_BASES as unknown as string[])
  allocationBasis?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  expectedArrival?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}

export class UpdateShipmentDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  title?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  reference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  origin?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Matches(CURRENCY, { message: 'Currency must be a 3-letter code such as USD or CNY' })
  currency?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 4 })
  @Min(0.0001)
  @Max(1_000_000)
  @Type(() => Number)
  fxRate?: number;

  @ApiPropertyOptional({ enum: ALLOCATION_BASES })
  @IsOptional()
  @IsIn(ALLOCATION_BASES as unknown as string[])
  allocationBasis?: string;

  @ApiPropertyOptional({ enum: SHIPMENT_STATUSES })
  @IsOptional()
  @IsIn(SHIPMENT_STATUSES as unknown as string[])
  status?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  expectedArrival?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}

export class AddParticipantDto {
  @ApiProperty({ example: 'Mama Wanjiru' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(30)
  phone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  notes?: string;
}

export class ShipmentItemDto {
  @ApiPropertyOptional({ description: 'Whose goods these are; defaults to your own' })
  @IsOptional()
  @IsUUID('4')
  participantId?: string;

  @ApiPropertyOptional({ description: 'Link to a product so it can be received into stock' })
  @IsOptional()
  @IsUUID('4')
  productId?: string;

  @ApiProperty({ example: 'Steel sufuria set (3pc)' })
  @IsString()
  @MinLength(1)
  @MaxLength(160)
  description: string;

  @ApiProperty()
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0.001)
  @Max(100_000_000)
  @Type(() => Number)
  quantity: number;

  @ApiPropertyOptional({ example: 'carton' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  unit?: string;

  @ApiProperty({ description: 'Supplier price per unit, in the shipment currency' })
  @IsNumber({ maxDecimalPlaces: 4 })
  @Min(0)
  @Max(100_000_000)
  @Type(() => Number)
  unitCost: number;

  @ApiPropertyOptional({ description: 'Total volume of this line in cubic metres' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 4 })
  @Min(0)
  @Max(100_000)
  @Type(() => Number)
  cbm?: number;

  @ApiPropertyOptional({ description: 'Total weight of this line in kg' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0)
  @Max(100_000_000)
  @Type(() => Number)
  weightKg?: number;
}

export class AddCostDto {
  @ApiProperty({ enum: COST_TYPES })
  @IsIn(COST_TYPES as unknown as string[])
  type: string;

  @ApiPropertyOptional({ example: 'KenTrade IDF' })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  label?: string;

  @ApiProperty()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(1_000_000_000)
  @Type(() => Number)
  amount: number;

  @ApiPropertyOptional({ example: 'KES', description: 'Defaults to KES' })
  @IsOptional()
  @Matches(CURRENCY, { message: 'Currency must be a 3-letter code such as KES or USD' })
  currency?: string;

  @ApiPropertyOptional({ description: 'KES per 1 unit when the cost is not in KES' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 4 })
  @Min(0.0001)
  @Max(1_000_000)
  @Type(() => Number)
  fxRate?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  paidAt?: string;

  @ApiPropertyOptional({ description: 'Receipt / M-Pesa / invoice number' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  reference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  receiptUrl?: string;
}

export class RecordImportPaymentDto {
  @ApiProperty()
  @IsUUID('4')
  participantId: string;

  @ApiProperty({ description: 'Amount handed over, in KES' })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(1_000_000_000)
  @Type(() => Number)
  amountKes: number;

  @ApiPropertyOptional({ example: 'MPESA' })
  @IsOptional()
  @IsString()
  @MaxLength(30)
  method?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  reference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  notes?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  paidAt?: string;
}

export class ReceivedLineDto {
  @ApiProperty()
  @IsUUID('4')
  itemId: string;

  @ApiProperty({ description: 'How many actually arrived (may be fewer than ordered)' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0)
  @Max(100_000_000)
  @Type(() => Number)
  receivedQty: number;
}

export class ReceiveShipmentDto {
  @ApiPropertyOptional({ type: [ReceivedLineDto], description: 'Omit to receive everything as ordered' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => ReceivedLineDto)
  items?: ReceivedLineDto[];
}

export class ShipmentQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4')
  branchId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  status?: string;
}
