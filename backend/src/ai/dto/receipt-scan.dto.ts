import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsBase64, IsOptional, IsString, IsUrl, MaxLength, MinLength, ValidateIf } from 'class-validator';

export class ScanReceiptDto {
  @ApiPropertyOptional({ description: 'Publicly-fetchable URL of the already-uploaded receipt image' })
  @ValidateIf((o: ScanReceiptDto) => !o.imageBase64)
  @IsUrl()
  imageUrl?: string;

  @ApiPropertyOptional({ description: 'Base64-encoded receipt photo (no data: URI prefix). Preferred — needs no upload step.' })
  @ValidateIf((o: ScanReceiptDto) => !o.imageUrl)
  @IsString()
  @IsBase64()
  @MinLength(100)
  imageBase64?: string;

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

export type ReceiptDocumentType =
  | 'supplier_invoice'
  | 'till_receipt'
  | 'delivery_note'
  | 'mpesa_message'
  | 'other';

export interface ParsedReceiptResult {
  /** False when the image doesn't look like a receipt/invoice/delivery note at all. */
  isReceipt: boolean;
  /** Human-readable reason, only present when isReceipt is false. */
  rejectionReason?: string;
  supplierName?: string;
  invoiceNumber?: string;
  invoiceDate?: string;
  /** What kind of document the AI recognised. */
  documentType?: ReceiptDocumentType;
  /** One plain-language sentence on what the document is and what it contains. */
  summary?: string;
  /** Payment method printed on the document (cash, M-Pesa, card, credit), if any. */
  paymentMethod?: string;
  items: ParsedReceiptLineItem[];
  totalAmount?: number;
  /** Raw model output, kept for debugging/support — never shown to the end user. */
  rawModelText?: string;
  model: string;
}
