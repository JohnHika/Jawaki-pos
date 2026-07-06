import {
  Controller,
  Post,
  Get,
  Body,
  Param,
  Query,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { AiBillingService } from './ai-billing.service';
import { StartTrialDto, SubscribeDto, VerifySmsDto } from './dto/subscribe.dto';

@Controller('api/v1/ai-billing')
export class AiBillingController {
  constructor(private readonly billingService: AiBillingService) {}

  /** Start free trial */
  @Post('trial')
  async startTrial(@Body() dto: StartTrialDto) {
    return this.billingService.startTrial(dto.branchId);
  }

  /** Get subscription status */
  @Get('status/:branchId')
  async getStatus(@Param('branchId') branchId: string) {
    return this.billingService.getStatus(branchId);
  }

  /** Check if branch can use AI */
  @Get('can-use/:branchId')
  async canUseAi(@Param('branchId') branchId: string) {
    const canUse = await this.billingService.canUseAi(branchId);
    return { canUse };
  }

  /** Submit M-Pesa code (manual entry) */
  @Post('submit-payment')
  async submitPayment(@Body() dto: SubscribeDto) {
    return this.billingService.submitPayment(
      dto.branchId,
      dto.mpesaCode,
      dto.senderPhone,
      dto.smsRaw,
    );
  }

  /** Auto-verify from SMS content */
  @Post('verify-sms')
  async verifyFromSms(@Body() dto: VerifySmsDto) {
    return this.billingService.verifyFromSms(
      dto.branchId,
      dto.mpesaCode,
      dto.amount,
      dto.recipient,
    );
  }
}
