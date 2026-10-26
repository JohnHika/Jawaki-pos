import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export class ParseMpesaDto {
  @ApiProperty({ description: 'Pasted M-Pesa messages, or the rows of an M-Pesa statement CSV' })
  @IsString()
  @MaxLength(200_000)
  text: string;
}

export class MpesaItemDto {
  @ApiProperty({ example: 'QJK7ABCD12' })
  @IsString()
  @Matches(/^[A-Za-z0-9]{8,12}$/, { message: 'That does not look like an M-Pesa code' })
  code: string;

  @ApiProperty()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(10_000_000)
  @Type(() => Number)
  amount: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  senderName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(30)
  senderPhone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  paidAt?: string;
}

export class ApplyMpesaItemDto extends MpesaItemDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4')
  debtorId?: string;
}

export class ApplyMpesaDto {
  @ApiProperty({ type: [ApplyMpesaItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => ApplyMpesaItemDto)
  items: ApplyMpesaItemDto[];
}

export class IgnoreMpesaDto {
  @ApiProperty({ type: [MpesaItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => MpesaItemDto)
  items: MpesaItemDto[];
}
