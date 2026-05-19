import {
  IsString,
  IsNumber,
  IsEnum,
  IsOptional,
  IsDateString,
  IsUUID,
  Min,
  MaxLength,
  IsArray,
  ValidateNested,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export enum ExpenseCategory {
  UTILITIES = 'UTILITIES',
  RENT = 'RENT',
  SALARIES = 'SALARIES',
  INVENTORY = 'INVENTORY',
  MARKETING = 'MARKETING',
  MAINTENANCE = 'MAINTENANCE',
  TRANSPORT = 'TRANSPORT',
  SUPPLIES = 'SUPPLIES',
  INSURANCE = 'INSURANCE',
  TAXES = 'TAXES',
  OTHER = 'OTHER',
}

export enum ExpenseStatus {
  PENDING = 'PENDING',
  APPROVED = 'APPROVED',
  REJECTED = 'REJECTED',
  PAID = 'PAID',
}

export class CreateExpenseDto {
  @ApiProperty({ enum: ExpenseCategory })
  @IsEnum(ExpenseCategory, { message: 'Invalid expense category' })
  category: ExpenseCategory;

  @ApiProperty({ example: 5000 })
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Amount must have up to 2 decimal places' })
  @Min(0.01, { message: 'Amount must be greater than 0' })
  @Type(() => Number)
  amount: number;

  @ApiProperty({ description: 'Branch ID' })
  @IsUUID('4', { message: 'Branch ID must be a valid UUID' })
  branchId: string;

  @ApiProperty({ description: 'Supplier/Vendor name' })
  @IsString()
  @MaxLength(200, { message: 'Supplier name must not exceed 200 characters' })
  supplier: string;

  @ApiPropertyOptional({ description: 'Invoice or receipt number' })
  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Reference must not exceed 100 characters' })
  reference?: string;

  @ApiProperty({ description: 'Expense description' })
  @IsString()
  @MaxLength(500, { message: 'Description must not exceed 500 characters' })
  description: string;

  @ApiProperty({ description: 'Expense date' })
  @IsDateString({}, { message: 'Date must be a valid ISO 8601 date' })
  date: string;

  @ApiPropertyOptional({ description: 'Payment method' })
  @IsOptional()
  @IsString()
  paymentMethod?: string;

  @ApiPropertyOptional({ description: 'Notes' })
  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'Notes must not exceed 1000 characters' })
  notes?: string;

  @ApiPropertyOptional({ description: 'Receipt image URLs' })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  receiptImages?: string[];

  @ApiPropertyOptional({ description: 'Offline ID from device (for sync)' })
  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Offline ID must not exceed 100 characters' })
  offlineId?: string;
}

export class UpdateExpenseDto {
  @ApiPropertyOptional({ enum: ExpenseCategory })
  @IsOptional()
  @IsEnum(ExpenseCategory, { message: 'Invalid expense category' })
  category?: ExpenseCategory;

  @ApiPropertyOptional({ example: 5000 })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 }, { message: 'Amount must have up to 2 decimal places' })
  @Min(0.01, { message: 'Amount must be greater than 0' })
  @Type(() => Number)
  amount?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  supplier?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  reference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  date?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  paymentMethod?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;

  @ApiPropertyOptional({ enum: ExpenseStatus })
  @IsOptional()
  @IsEnum(ExpenseStatus, { message: 'Invalid expense status' })
  status?: ExpenseStatus;

  @ApiPropertyOptional({ description: 'Receipt image URLs' })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  receiptImages?: string[];
}

export class ExpenseQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4', { message: 'Branch ID must be a valid UUID' })
  branchId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(ExpenseCategory, { message: 'Invalid expense category' })
  category?: ExpenseCategory;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(ExpenseStatus, { message: 'Invalid expense status' })
  status?: ExpenseStatus;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString({}, { message: 'Start date must be a valid ISO 8601 date' })
  startDate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString({}, { message: 'End date must be a valid ISO 8601 date' })
  endDate?: string;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsNumber({}, { message: 'Page must be a number' })
  @Min(1, { message: 'Page must be at least 1' })
  @Type(() => Number)
  page?: number;

  @ApiPropertyOptional({ default: 50 })
  @IsOptional()
  @IsNumber({}, { message: 'Limit must be a number' })
  @Min(1, { message: 'Limit must be at least 1' })
  @Type(() => Number)
  limit?: number;
}

export class ExpenseItemDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  expenseId: string;

  @ApiProperty()
  description: string;

  @ApiProperty()
  quantity: number;

  @ApiProperty()
  unitPrice: number;

  @ApiProperty()
  total: number;
}

export class CreateExpenseItemDto {
  @ApiProperty()
  @IsString()
  @MaxLength(200)
  description: string;

  @ApiProperty({ example: 1 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Type(() => Number)
  quantity: number;

  @ApiProperty({ example: 100 })
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Type(() => Number)
  unitPrice: number;
}

export class CreateExpenseWithItemsDto {
  @ApiProperty({ enum: ExpenseCategory })
  @IsEnum(ExpenseCategory)
  category: ExpenseCategory;

  @ApiProperty()
  @IsUUID('4')
  branchId: string;

  @ApiProperty()
  @IsString()
  @MaxLength(200)
  supplier: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  reference?: string;

  @ApiProperty()
  @IsDateString()
  date: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  paymentMethod?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;

  @ApiProperty({ type: [CreateExpenseItemDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateExpenseItemDto)
  items: CreateExpenseItemDto[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  offlineId?: string;
}

export class ExpenseResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  expenseNumber: string;

  @ApiProperty({ enum: ExpenseCategory })
  category: ExpenseCategory;

  @ApiProperty()
  branchId: string;

  @ApiProperty()
  branchName?: string;

  @ApiProperty()
  supplier: string;

  @ApiProperty()
  reference?: string;

  @ApiProperty()
  description: string;

  @ApiProperty()
  amount: number;

  @ApiProperty({ enum: ExpenseStatus })
  status: ExpenseStatus;

  @ApiProperty()
  date: string;

  @ApiProperty()
  paymentMethod?: string;

  @ApiProperty()
  notes?: string;

  @ApiProperty()
  receiptImages?: string[];

  @ApiProperty()
  createdById: string;

  @ApiProperty()
  createdBy?: string;

  @ApiProperty()
  approvedById?: string;

  @ApiProperty()
  approvedBy?: string;

  @ApiProperty()
  approvedAt?: string;

  @ApiProperty()
  createdAt: Date;

  @ApiProperty()
  updatedAt: Date;

  @ApiPropertyOptional({ type: [ExpenseItemDto] })
  items?: ExpenseItemDto[];
}

export class ExpenseSummaryDto {
  @ApiProperty()
  totalExpenses: number;

  @ApiProperty()
  pendingCount: number;

  @ApiProperty()
  pendingAmount: number;

  @ApiProperty()
  approvedCount: number;

  @ApiProperty()
  approvedAmount: number;

  @ApiProperty()
  paidCount: number;

  @ApiProperty()
  paidAmount: number;

  @ApiProperty()
  rejectedCount: number;

  @ApiProperty()
  rejectedAmount: number;

  @ApiProperty()
  byCategory: Array<{
    category: ExpenseCategory;
    count: number;
    amount: number;
    percentage: number;
  }>;

  @ApiProperty()
  byBranch: Array<{
    branchId: string;
    branchName: string;
    amount: number;
    percentage: number;
  }>;
}

export class ExpenseTrendDto {
  @ApiProperty()
  period: string;

  @ApiProperty()
  amount: number;

  @ApiProperty()
  count: number;
}
