import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUrl, MaxLength } from 'class-validator';

export class ScanReceiptDto {
  @ApiProperty({ description: 'Publicly-fetchable URL of the already-uploaded receipt image' })
  @IsUrl()
  imageUrl: string;

  @ApiPropertyOptional({ description: 'Branch ID, for future per-branch AI access gating' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  branchId?: string;
}

export interface ParsedReceiptLineItem {
  name: string;
  quantity: number;
  unit: string;
  unitCost: number;
  lineTotal: number;
}

export interface ParsedReceiptResult {
  /** False when the image doesn't look like a receipt/invoice/delivery note at all. */
  isReceipt: boolean;
  /** Human-readable reason, only present when isReceipt is false. */
  rejectionReason?: string;
  supplierName?: string;
  invoiceNumber?: string;
  invoiceDate?: string;
  items: ParsedReceiptLineItem[];
  totalAmount?: number;
  /** Raw model output, kept for debugging/support — never shown to the end user. */
  rawModelText?: string;
  model: string;
}
