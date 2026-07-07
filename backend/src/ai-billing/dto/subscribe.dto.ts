import { IsString, IsOptional, IsEmail, MinLength, MaxLength, Matches } from 'class-validator';

export class InitializePaystackPaymentDto {
  @IsString()
  branchId: string;

  @IsEmail()
  email: string;
}

export class SubscribeDto {
  @IsString()
  branchId: string;

  @IsString()
  @MinLength(5)
  @MaxLength(20)
  mpesaCode: string;

  @IsOptional()
  @IsString()
  @Matches(/^0[17]\d{8}$/, { message: 'Invalid Kenyan phone number' })
  senderPhone?: string;

  @IsOptional()
  @IsString()
  smsRaw?: string;
}

export class VerifySmsDto {
  @IsString()
  branchId: string;

  @IsString()
  mpesaCode: string;

  @IsString()
  amount: string;

  @IsString()
  recipient: string;

  @IsString()
  smsBody: string;
}

export class AdminActionDto {
  @IsString()
  paymentId: string;

  @IsString()
  action: 'approve' | 'reject';

  @IsOptional()
  @IsString()
  notes?: string;
}
