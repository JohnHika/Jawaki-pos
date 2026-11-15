import { IsArray, IsBoolean, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

const PROFILE_ID = /^[a-z][a-z0-9_]{1,48}$/;

export class CreateLayoutRequestDto {
  @ApiProperty({ example: 'bakery_food_counter' })
  @IsString()
  @Matches(PROFILE_ID, { message: 'Choose a valid business type' })
  toProfileId!: string;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @Matches(PROFILE_ID, { each: true, message: 'Choose valid business types' })
  additionalProfileIds?: string[];

  @ApiProperty({ example: 'We are opening a food counter next to the bookshop.' })
  @IsString()
  @MinLength(10, { message: 'Please tell us why in at least 10 characters' })
  @MaxLength(500)
  reason!: string;
}

export class LayoutRequestDecisionDto {
  @ApiProperty()
  @IsBoolean()
  approve!: boolean;

  @ApiPropertyOptional({ description: 'Shown to the owner with the decision' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}
