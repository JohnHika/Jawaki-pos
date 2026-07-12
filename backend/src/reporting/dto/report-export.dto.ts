import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { ReportPeriod } from './reporting.dto';

export enum ReportExportType {
  SALES_SUMMARY = 'SALES_SUMMARY',
  TOP_PRODUCTS = 'TOP_PRODUCTS',
  PROFIT_LOSS = 'PROFIT_LOSS',
  INVENTORY = 'INVENTORY',
  PAYMENT_BREAKDOWN = 'PAYMENT_BREAKDOWN',
}

export enum ReportExportFormat {
  PDF = 'PDF',
  DOCX = 'DOCX',
  CSV = 'CSV',
}

export class GenerateReportDto {
  @ApiProperty({ enum: ReportExportType })
  @IsEnum(ReportExportType)
  reportType: ReportExportType;

  @ApiProperty({ enum: ReportExportFormat })
  @IsEnum(ReportExportFormat)
  format: ReportExportFormat;

  @ApiPropertyOptional({ enum: ReportPeriod })
  @IsOptional()
  @IsEnum(ReportPeriod)
  period?: ReportPeriod;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  branchId?: string;
}

/** One table's worth of report data — generic enough that any report type
 * (sales, profit, inventory, ...) renders through the same PDF/DOCX builder,
 * mirroring the mobile app's own PdfReportSection shape so both sides of the
 * app describe a report the same way. */
export interface ReportSection {
  heading: string;
  headers: string[];
  rows: string[][];
}

export interface GeneratedReport {
  title: string;
  subtitle: string;
  sections: ReportSection[];
}
