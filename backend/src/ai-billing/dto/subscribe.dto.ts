import { IsString, IsOptional } from 'class-validator';

/**
 * Admin-only DTO. The customer-facing subscription DTOs (SubscribeDto,
 * VerifySmsDto, InitializePaystackPaymentDto) were removed along with the
 * separate AI subscription endpoints — AI is now included in every plan.
 */
export class AdminActionDto {
  @IsString()
  paymentId: string;

  @IsString()
  action: 'approve' | 'reject';

  @IsOptional()
  @IsString()
  notes?: string;
}
