import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsNotEmpty, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;

export class CreatePartnerRequestDto {
  @ApiProperty({ description: 'Company code (the other business slug)' })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim().toLowerCase() : value))
  @IsString()
  @IsNotEmpty({ message: 'Company code is required' })
  @MaxLength(100)
  companyCode: string;

  @ApiPropertyOptional({ description: 'Short intro note', maxLength: 300 })
  @IsOptional()
  @Transform(trim)
  @IsString()
  @MaxLength(300, { message: 'Message must be at most 300 characters' })
  message?: string;
}

export class SendPartnerMessageDto {
  @ApiProperty({ minLength: 1, maxLength: 2000 })
  @Transform(trim)
  @IsString()
  @MinLength(1, { message: 'Message cannot be empty' })
  @MaxLength(2000, { message: 'Message must be at most 2000 characters' })
  body: string;
}
