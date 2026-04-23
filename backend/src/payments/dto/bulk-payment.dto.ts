import { IsString, IsNumber, IsArray, IsOptional, IsDateString, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class BulkPaymentItemDto {
  @IsString()
  saleId: string;

  @IsNumber()
  amount: number;

  @IsString()
  @IsOptional()
  notes?: string;
}

export class BulkPaymentCustomerDto {
  @IsString()
  @IsOptional()
  customerId?: string;

  @IsString()
  @IsOptional()
  customerName?: string;

  @IsString()
  @IsOptional()
  customerPhone?: string;
}

export class ProcessBulkPaymentDto {
  @IsString()
  branchId: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => BulkPaymentItemDto)
  payments: BulkPaymentItemDto[];

  @IsString()
  paymentMethod: string;

  @IsString()
  @IsOptional()
  reference?: string;

  @IsString()
  @IsOptional()
  notes?: string;

  @IsOptional()
  metadata?: Record<string, any>;
}

export class ProcessBulkCreditPaymentDto {
  @IsString()
  branchId: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => BulkPaymentItemDto)
  payments: BulkPaymentItemDto[];

  @IsString()
  @IsOptional()
  customerName?: string;

  @IsString()
  @IsOptional()
  customerPhone?: string;

  @IsString()
  @IsOptional()
  notes?: string;

  @IsDateString()
  @IsOptional()
  dueDate?: string;

  @IsOptional()
  metadata?: Record<string, any>;
}

export class BulkPaymentResultDto {
  success: boolean;
  batchId: string;
  processedCount: number;
  failedCount: number;
  totalAmount: number;
  results: BulkPaymentResultItemDto[];
  errors: BulkPaymentErrorDto[];
}

export class BulkPaymentResultItemDto {
  saleId: string;
  receiptNumber?: string;
  amount: number;
  status: 'success' | 'failed';
  message?: string;
}

export class BulkPaymentErrorDto {
  saleId: string;
  error: string;
}

export class BulkPaymentStatusDto {
  batchId: string;
  status: 'processing' | 'completed' | 'partial' | 'failed';
  createdAt: Date;
  completedAt?: Date;
  totalPayments: number;
  processedPayments: number;
  successfulPayments: number;
  failedPayments: number;
  totalAmount: number;
  results: BulkPaymentResultItemDto[];
}

export class BulkPaymentQueryDto {
  @IsString()
  @IsOptional()
  branchId?: string;

  @IsString()
  @IsOptional()
  status?: 'processing' | 'completed' | 'partial' | 'failed';

  @IsDateString()
  @IsOptional()
  startDate?: string;

  @IsDateString()
  @IsOptional()
  endDate?: string;

  @IsNumber()
  @IsOptional()
  page?: number = 1;

  @IsNumber()
  @IsOptional()
  limit?: number = 20;
}
