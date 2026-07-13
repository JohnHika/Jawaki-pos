import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsNotEmpty, IsObject, IsOptional, IsString, MaxLength } from 'class-validator';

export class EnqueuePrintJobDto {
  @ApiProperty({ description: "This device's UUID (the one requesting the print)" })
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  deviceId: string;

  @ApiProperty({
    description:
      'Receipt data, same shape ReceiptPrinterService.printReceipt() already builds from',
  })
  @IsObject()
  payload: Record<string, unknown>;
}

export class ClaimPrintJobsDto {
  @ApiProperty({ description: "This device's UUID (the one holding the Bluetooth printer)" })
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  deviceId: string;
}

export class CompletePrintJobDto {
  @ApiProperty({ description: "This device's UUID (must match the device that claimed it)" })
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  deviceId: string;

  @ApiProperty({ enum: ['printed', 'failed'] })
  @IsIn(['printed', 'failed'])
  status: 'printed' | 'failed';

  @ApiPropertyOptional({ description: 'Error detail when status is failed' })
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  errorMessage?: string;
}

export class SetPrinterDeviceDto {
  @ApiPropertyOptional({
    description:
      'Device UUID of the device that owns the Bluetooth printer connection for this branch. Null clears it (no device is drained, jobs queue until one is set).',
  })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  deviceId?: string | null;
}
