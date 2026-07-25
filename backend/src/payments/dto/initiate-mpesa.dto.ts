import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import {
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  Min,
  MaxLength,
} from "class-validator";

export class InitiateMpesaDto {
  @ApiProperty({ example: "254712345678" })
  @IsString()
  @Matches(/^(?:\+?254|0)?(?:7|1)\d{8}$/, {
    message: "phoneNumber must be a valid Kenyan mobile number",
  })
  phoneNumber!: string;

  @ApiProperty({ example: 1500 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  @Max(9999999)
  amount!: number;

  @ApiProperty({ example: "POS-ORDER-123" })
  @IsString()
  @MaxLength(100)
  reference!: string;

  @ApiPropertyOptional({ example: "POS sale" })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  description?: string;
}
