import { IsDateString, IsOptional, IsUUID, IsEnum, IsNumber, IsArray, IsString } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';

export enum ReportPeriod {
  TODAY = 'TODAY',
  YESTERDAY = 'YESTERDAY',
  THIS_WEEK = 'THIS_WEEK',
  LAST_WEEK = 'LAST_WEEK',
  THIS_MONTH = 'THIS_MONTH',
  LAST_MONTH = 'LAST_MONTH',
  THIS_QUARTER = 'THIS_QUARTER',
  THIS_YEAR = 'THIS_YEAR',
  CUSTOM = 'CUSTOM',
}

export enum ReportGroupBy {
  HOUR = 'HOUR',
  DAY = 'DAY',
  WEEK = 'WEEK',
  MONTH = 'MONTH',
  CATEGORY = 'CATEGORY',
  PRODUCT = 'PRODUCT',
  CASHIER = 'CASHIER',
  BRANCH = 'BRANCH',
  PAYMENT_METHOD = 'PAYMENT_METHOD',
}

export class DateRangeDto {
  @ApiProperty()
  @IsDateString()
  startDate: string;

  @ApiProperty()
  @IsDateString()
  endDate: string;
}

export class ReportFilterDto {
  @ApiPropertyOptional({ enum: ReportPeriod })
  @IsOptional()
  @IsEnum(ReportPeriod)
  period?: ReportPeriod;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  startDate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  endDate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  branchId?: string;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @IsUUID('4', { each: true })
  branchIds?: string[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  categoryId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  productId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  cashierId?: string;

  @ApiPropertyOptional({ enum: ReportGroupBy })
  @IsOptional()
  @IsEnum(ReportGroupBy)
  groupBy?: ReportGroupBy;
}

export class SalesSummaryDto {
  @ApiProperty()
  totalSales: number;

  @ApiProperty()
  totalRevenue: number;

  @ApiProperty()
  totalDiscount: number;

  @ApiProperty()
  netRevenue: number;

  @ApiProperty()
  averageTicket: number;

  @ApiProperty()
  itemsSold: number;

  @ApiProperty()
  uniqueCustomers: number;

  @ApiProperty()
  refundsCount: number;

  @ApiProperty()
  refundsAmount: number;

  @ApiProperty()
  voidedSalesCount: number;

  @ApiProperty()
  voidedSalesAmount: number;
}

export class SalesTrendDto {
  @ApiProperty()
  period: string;

  @ApiProperty()
  salesCount: number;

  @ApiProperty()
  revenue: number;

  @ApiProperty()
  itemsSold: number;
}

export class TopProductDto {
  @ApiProperty()
  productId: string;

  @ApiProperty()
  productName: string;

  @ApiProperty()
  sku: string;

  @ApiProperty()
  categoryName: string;

  @ApiProperty()
  quantitySold: number;

  @ApiProperty()
  revenue: number;

  @ApiProperty()
  profit: number;
}

export class CategorySalesDto {
  @ApiProperty()
  categoryId: string;

  @ApiProperty()
  categoryName: string;

  @ApiProperty()
  salesCount: number;

  @ApiProperty()
  itemsSold: number;

  @ApiProperty()
  revenue: number;

  @ApiProperty()
  percentage: number;
}

export class CashierPerformanceDto {
  @ApiProperty()
  userId: string;

  @ApiProperty()
  name: string;

  @ApiProperty()
  salesCount: number;

  @ApiProperty()
  revenue: number;

  @ApiProperty()
  itemsSold: number;

  @ApiProperty()
  averageTicket: number;

  @ApiProperty()
  refundsCount: number;
}

export class PaymentMethodBreakdownDto {
  @ApiProperty()
  method: string;

  @ApiProperty()
  transactionsCount: number;

  @ApiProperty()
  amount: number;

  @ApiProperty()
  percentage: number;
}

export class BranchComparisonDto {
  @ApiProperty()
  branchId: string;

  @ApiProperty()
  branchName: string;

  @ApiProperty()
  salesCount: number;

  @ApiProperty()
  revenue: number;

  @ApiProperty()
  averageTicket: number;

  @ApiProperty()
  topProduct: string;
}

export class InventoryReportDto {
  @ApiProperty()
  totalProducts: number;

  @ApiProperty()
  totalStockValue: number;

  @ApiProperty()
  lowStockItems: number;

  @ApiProperty()
  outOfStockItems: number;

  @ApiProperty()
  overStockItems: number;
}

export class StockMovementSummaryDto {
  @ApiProperty()
  adjustmentsIn: number;

  @ApiProperty()
  adjustmentsOut: number;

  @ApiProperty()
  transfersIn: number;

  @ApiProperty()
  transfersOut: number;

  @ApiProperty()
  salesReductions: number;

  @ApiProperty()
  refundRestores: number;
}

export class DashboardSummaryDto {
  @ApiProperty({ type: SalesSummaryDto })
  sales: SalesSummaryDto;

  @ApiProperty({ type: [SalesTrendDto] })
  trend: SalesTrendDto[];

  @ApiProperty({ type: [TopProductDto] })
  topProducts: TopProductDto[];

  @ApiProperty({ type: [PaymentMethodBreakdownDto] })
  paymentMethods: PaymentMethodBreakdownDto[];

  @ApiProperty({ type: InventoryReportDto })
  inventory: InventoryReportDto;
}

export class DailyProfitAndLossDto {
  @ApiProperty()
  date: string;

  @ApiProperty()
  branchId: string;

  @ApiProperty()
  branchName: string;

  // Revenue
  @ApiProperty()
  grossSales: number;

  @ApiProperty()
  totalDiscounts: number;

  @ApiProperty()
  totalTax: number;

  @ApiProperty()
  netSales: number;

  @ApiProperty()
  refundedAmount: number;

  @ApiProperty()
  netRevenue: number;

  // Cost of Goods Sold
  @ApiProperty()
  costOfGoodsSold: number;

  @ApiProperty()
  grossProfit: number;

  @ApiProperty({ description: 'Gross profit margin percentage' })
  grossProfitMargin: number;

  // Expenses
  @ApiProperty()
  totalExpenses: number;

  @ApiProperty()
  expensesByCategory: Record<string, number>;

  // Net Profit
  @ApiProperty()
  netProfit: number;

  @ApiProperty({ description: 'Net profit margin percentage' })
  netProfitMargin: number;

  // Summary
  @ApiProperty()
  transactionCount: number;

  @ApiProperty()
  averageTransactionValue: number;
}
