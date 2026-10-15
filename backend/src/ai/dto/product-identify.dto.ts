import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsBase64, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class IdentifyProductDto {
  @ApiProperty({ description: 'Base64-encoded product photo (no data: URI prefix)' })
  @IsString()
  @IsBase64()
  @MinLength(100)
  imageBase64: string;

  @ApiPropertyOptional({ description: 'Branch ID, for future per-branch AI access gating' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  branchId?: string;
}

export interface IdentifiedProduct {
  /** False when the photo isn't a recognisable retail product. */
  identified: boolean;
  /** Only present when identified is false and the AI explained why. */
  reason?: string;
  name?: string;
  brand?: string;
  category?: string;
  size?: string;
  description?: string;
  barcode?: string;
  model: string;
}
