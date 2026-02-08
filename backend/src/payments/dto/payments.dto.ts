import { IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

// M-Pesa DTOs
export class MpesaStkPushDto {
  @ApiProperty({ example: '254712345678' })
  @IsString()
  phoneNumber: string;

  @ApiProperty({ example: 1500 })
  @IsNumber()
  @Min(1)
  @Type(() => Number)
  amount: number;

  @ApiProperty({ description: 'Sale ID or reference' })
  @IsString()
  accountReference: string;

  @ApiPropertyOptional({ example: 'Payment for order' })
  @IsOptional()
  @IsString()
  transactionDesc?: string;
}

export class MpesaCallbackDto {
  Body: {
    stkCallback: {
      MerchantRequestID: string;
      CheckoutRequestID: string;
      ResultCode: number;
      ResultDesc: string;
      CallbackMetadata?: {
        Item: Array<{
          Name: string;
          Value: string | number;
        }>;
      };
    };
  };
}

export class MpesaC2BConfirmationDto {
  TransactionType: string;
  TransID: string;
  TransTime: string;
  TransAmount: string;
  BusinessShortCode: string;
  BillRefNumber: string;
  InvoiceNumber: string;
  OrgAccountBalance: string;
  ThirdPartyTransID: string;
  MSISDN: string;
  FirstName: string;
  MiddleName: string;
  LastName: string;
}

// PesaPal DTOs
export class PesapalPaymentDto {
  @ApiProperty({ example: 1500 })
  @IsNumber()
  @Min(1)
  @Type(() => Number)
  amount: number;

  @ApiProperty({ description: 'Unique merchant reference' })
  @IsString()
  merchantReference: string;

  @ApiProperty()
  @IsString()
  description: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  currency?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  callbackUrl?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  cancellationUrl?: string;

  // Customer info
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  email?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  phoneNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  firstName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  lastName?: string;
}

export class PesapalIpnDto {
  OrderTrackingId: string;
  OrderMerchantReference: string;
  OrderNotificationType: string;
}

// TouristTap DTOs
export class TouristTapPaymentDto {
  @ApiProperty({ example: 1500 })
  @IsNumber()
  @Min(1)
  @Type(() => Number)
  amount: number;

  @ApiProperty({ description: 'Unique transaction reference' })
  @IsString()
  transactionRef: string;

  @ApiPropertyOptional({ default: 'KES' })
  @IsOptional()
  @IsString()
  currency?: string;

  @ApiPropertyOptional({ description: 'Customer NFC token or reference' })
  @IsOptional()
  @IsString()
  customerRef?: string;
}

export class TouristTapCallbackDto {
  transactionRef: string;
  status: string;
  amount: number;
  currency: string;
  timestamp: string;
  signature: string;
}

// Response DTOs
export class PaymentInitResponseDto {
  @ApiProperty()
  success: boolean;

  @ApiProperty()
  transactionId: string;

  @ApiPropertyOptional()
  checkoutUrl?: string;

  @ApiPropertyOptional()
  message?: string;
}

export class PaymentStatusResponseDto {
  @ApiProperty()
  transactionId: string;

  @ApiProperty()
  status: string;

  @ApiProperty()
  amount: number;

  @ApiPropertyOptional()
  paidAt?: Date;

  @ApiPropertyOptional()
  receiptNumber?: string;

  @ApiPropertyOptional()
  payerInfo?: {
    phone?: string;
    name?: string;
  };
}
