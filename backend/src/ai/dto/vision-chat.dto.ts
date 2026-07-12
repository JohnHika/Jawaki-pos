import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsBase64, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class VisionChatRequestDto {
  @ApiProperty({ description: 'Base64-encoded image (no data: URI prefix)' })
  @IsString()
  @IsBase64()
  @MinLength(100)
  imageBase64: string;

  @ApiProperty({ description: "What the user asked about the photo, e.g. \"what's wrong with this product?\"" })
  @IsString()
  @MinLength(1)
  @MaxLength(1000)
  prompt: string;

  @ApiPropertyOptional({ description: 'Branch ID, for future per-branch AI access gating' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  branchId?: string;
}

export interface VisionChatResult {
  reply: string;
  model: string;
}
