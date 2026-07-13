import { Body, Controller, Get, Param, Post, Put, Query, Request, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PrintingService } from './printing.service';
import {
  ClaimPrintJobsDto,
  CompletePrintJobDto,
  EnqueuePrintJobDto,
  SetPrinterDeviceDto,
} from './dto/printing.dto';

// Multiple devices can share one Bluetooth thermal printer (Bluetooth
// Classic only allows one active connection), so a print job raised by any
// device is queued here for the single device designated as that printer's
// holder to claim and drain — see PrintingService for the full contract.
@ApiTags('printing')
@Controller({ path: 'printing', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class PrintingController {
  constructor(private readonly printingService: PrintingService) {}

  @Post('jobs')
  @ApiOperation({ summary: 'Enqueue a receipt print job for this branch' })
  async enqueue(@Request() req: any, @Body() dto: EnqueuePrintJobDto) {
    const job = await this.printingService.enqueue(
      req.user.branchId,
      req.user.sub,
      dto.deviceId,
      dto.payload,
    );
    return { success: true, data: job };
  }

  @Post('jobs/claim')
  @ApiOperation({ summary: 'Claim pending print jobs for this branch (printer-holder device only)' })
  async claim(@Request() req: any, @Body() dto: ClaimPrintJobsDto) {
    const jobs = await this.printingService.claimPending(req.user.branchId, dto.deviceId);
    return { success: true, data: jobs };
  }

  @Put('jobs/:id/complete')
  @ApiOperation({ summary: 'Report a claimed print job as printed or failed' })
  async complete(
    @Request() req: any,
    @Param('id') id: string,
    @Body() dto: CompletePrintJobDto,
  ) {
    const job = await this.printingService.complete(
      id,
      req.user.branchId,
      dto.deviceId,
      dto.status,
      dto.errorMessage,
    );
    return { success: true, data: job };
  }

  @Get('jobs/mine')
  @ApiOperation({ summary: "List this device's own recently requested print jobs and their status" })
  async listMine(@Request() req: any, @Query('deviceId') deviceId: string) {
    const jobs = await this.printingService.listMine(req.user.branchId, deviceId);
    return { success: true, data: jobs };
  }

  @Get('printer-device')
  @ApiOperation({ summary: 'Get the device UUID currently designated to hold this branch\'s printer' })
  async getPrinterDevice(@Request() req: any) {
    const deviceId = await this.printingService.getPrinterDevice(req.user.branchId);
    return { success: true, data: { printerDeviceId: deviceId } };
  }

  @Put('printer-device')
  @ApiOperation({ summary: 'Designate (or clear) which device holds this branch\'s Bluetooth printer' })
  async setPrinterDevice(@Request() req: any, @Body() dto: SetPrinterDeviceDto) {
    const result = await this.printingService.setPrinterDevice(req.user.branchId, dto.deviceId ?? null);
    return { success: true, data: result };
  }
}
