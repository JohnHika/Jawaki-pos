import {
  Controller,
  Post,
  Get,
  Body,
  Param,
  Req,
  Headers,
  HttpCode,
  HttpStatus,
  UnauthorizedException,
} from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'crypto';
import { ConfigService } from '@nestjs/config';
import { Request } from 'express';
import { AiBillingService } from './ai-billing.service';
import {
  SubscribeDto,
  VerifySmsDto,
  InitializePaystackPaymentDto,
} from './dto/subscribe.dto';

@Controller('api/v1/ai-billing')
export class AiBillingController {
  constructor(
    private readonly billingService: AiBillingService,
    private readonly configService: ConfigService,
  ) {}

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

  /** Start a Paystack card checkout for a subscription */
  @Post('paystack/initialize')
  async initializePaystackPayment(@Body() dto: InitializePaystackPaymentDto) {
    return this.billingService.initializePaystackPayment(dto.branchId, dto.email);
  }

  /**
   * Paystack webhook — activates (or renews) a subscription once a card
   * charge succeeds. Verifies the `x-paystack-signature` header against
   * the raw request body before trusting the payload, since this endpoint
   * has no other auth and anyone who knew the URL could otherwise forge a
   * "payment succeeded" event.
   */
  @Post('paystack/webhook')
  @HttpCode(HttpStatus.OK)
  async paystackWebhook(
    @Req() req: Request & { rawBody?: Buffer },
    @Headers('x-paystack-signature') signature: string,
  ) {
    this.verifyPaystackSignature(req.rawBody, signature);

    const { event, data } = req.body as { event: string; data: any };
    return this.billingService.handlePaystackWebhook(event, data);
  }

  private verifyPaystackSignature(rawBody: Buffer | undefined, signature: string | undefined) {
    const secretKey = this.configService.get<string>('PAYSTACK_SECRET_KEY');

    if (!secretKey || !rawBody || !signature) {
      throw new UnauthorizedException('Invalid Paystack webhook request');
    }

    const expected = createHmac('sha512', secretKey).update(rawBody).digest('hex');
    const expectedBuffer = Buffer.from(expected, 'utf8');
    const signatureBuffer = Buffer.from(signature, 'utf8');

    if (
      expectedBuffer.length !== signatureBuffer.length ||
      !timingSafeEqual(expectedBuffer, signatureBuffer)
    ) {
      throw new UnauthorizedException('Invalid Paystack webhook signature');
    }
  }
}
