import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { ReportPeriod } from './reporting.dto';

export enum ChartDataType {
  SALES_TREND = 'SALES_TREND',
  TOP_PRODUCTS = 'TOP_PRODUCTS',
  SALES_HEATMAP = 'SALES_HEATMAP',
  PAYMENT_BREAKDOWN = 'PAYMENT_BREAKDOWN',
}

export class GenerateChartDto {
  @ApiProperty({ enum: ChartDataType })
  @IsEnum(ChartDataType)
  chartType: ChartDataType;

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

/** One (x, y) point for a bar/line chart — `label` is the x-axis tick
 * (a date, a product name, a payment method...), `value` the y-axis number. */
export interface ChartPoint {
  label: string;
  value: number;
}

/** One cell of a day×hour heatmap grid. dayOfWeek: 0=Sun..6=Sat, hour: 0-23. */
export interface HeatmapCell {
  dayOfWeek: number;
  hour: number;
  value: number;
}

/** What the mobile client needs to render an actual chart widget (fl_chart)
 * instead of a text description — kept generic across bar/line/heatmap so
 * one shape covers every report the AI can visualize. */
export interface GeneratedChart {
  kind: 'bar' | 'line' | 'heatmap';
  title: string;
  subtitle: string;
  /** Populated for kind: 'bar' | 'line'. */
  points?: ChartPoint[];
  /** Populated for kind: 'heatmap'. */
  cells?: HeatmapCell[];
  /** Unit label for the y-axis / cell values, e.g. "KES" or "sales". */
  valueLabel: string;
}
