import { IsString, IsNumber, IsOptional, IsEnum, IsDateString } from 'class-validator';
import { ManualPaymentStatus } from '@prisma/client';

export class CreateManualPaymentRequestDto {
  @IsString()
  branchId: string;

  @IsString()
  @IsOptional()
  saleId?: string;

  @IsString()
  paymentMethod: string;

  @IsNumber()
  amount: number;

  @IsString()
  reason: string;

  @IsString()
  @IsOptional()
  notes?: string;

  @IsOptional()
  metadata?: Record<string, any>;
}

export class ApproveManualPaymentDto {
  @IsString()
  @IsOptional()
  notes?: string;
}

export class RejectManualPaymentDto {
  @IsString()
  rejectionReason: string;
}

export class CompleteManualPaymentDto {
  @IsString()
  @IsOptional()
  notes?: string;
}

export class ManualPaymentQueryDto {
  @IsString()
  @IsOptional()
  branchId?: string;

  @IsEnum(ManualPaymentStatus)
  @IsOptional()
  status?: ManualPaymentStatus;

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

export class ManualPaymentResponseDto {
  id: string;
  requestNumber: string;
  saleId?: string;
  branchId: string;
  branchName?: string;
  requestedById: string;
  requestedByName?: string;
  approvedById?: string;
  approvedByName?: string;
  paymentMethod: string;
  amount: number;
  reason: string;
  status: ManualPaymentStatus;
  notes?: string;
  rejectionReason?: string;
  approvedAt?: Date;
  completedAt?: Date;
  metadata: Record<string, any>;
  createdAt: Date;
  updatedAt: Date;
}

export class ManualPaymentListResponseDto {
  items: ManualPaymentResponseDto[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}
