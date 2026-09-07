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
  NotFoundException,
  UseGuards,
} from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'crypto';
import { ConfigService } from '@nestjs/config';
import { Request } from 'express';
import { AiBillingService } from './ai-billing.service';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  SubscribeDto,
  VerifySmsDto,
  InitializePaystackPaymentDto,
} from './dto/subscribe.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@Controller('api/v1/ai-billing')
export class AiBillingController {
  constructor(
    private readonly billingService: AiBillingService,
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  /**
   * Asserts the caller's tenant actually owns the branch before any
   * subscription read/write. Without this, any JWT holder from tenant A
   * could read payment history (M-Pesa codes included) or activate
   * subscriptions for tenant B by supplying an arbitrary branchId.
   */
  private async assertBranchInTenant(tenantId: string, branchId: string) {
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
      select: { id: true },
    });
    if (!branch) throw new NotFoundException('Branch not found');
  }

  /** Get subscription status */
  @Get('status/:branchId')
  @UseGuards(JwtAuthGuard)
  async getStatus(
    @Param('branchId') branchId: string,
    @CurrentUser('tenantId') tenantId: string,
  ) {
    await this.assertBranchInTenant(tenantId, branchId);
    return this.billingService.getStatus(branchId);
  }

  /** Check if branch can use AI */
  @Get('can-use/:branchId')
  @UseGuards(JwtAuthGuard)
  async canUseAi(
    @Param('branchId') branchId: string,
    @CurrentUser('tenantId') tenantId: string,
  ) {
    await this.assertBranchInTenant(tenantId, branchId);
    const canUse = await this.billingService.canUseAi(branchId);
    return { canUse };
  }

  /** Submit M-Pesa code (manual entry) */
  @Post('submit-payment')
  @UseGuards(JwtAuthGuard)
  async submitPayment(
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: SubscribeDto,
  ) {
    await this.assertBranchInTenant(tenantId, dto.branchId);
    return this.billingService.submitPayment(
      dto.branchId,
      dto.mpesaCode,
      dto.senderPhone,
      dto.smsRaw,
    );
  }

  /** Auto-verify from SMS content */
  @Post('verify-sms')
  @UseGuards(JwtAuthGuard)
  async verifyFromSms(
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: VerifySmsDto,
  ) {
    await this.assertBranchInTenant(tenantId, dto.branchId);
    return this.billingService.verifyFromSms(
      dto.branchId,
      dto.mpesaCode,
      dto.amount,
      dto.recipient,
    );
  }

  /** Start a Paystack card checkout for a subscription */
  @Post('paystack/initialize')
  @UseGuards(JwtAuthGuard)
  async initializePaystackPayment(
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: InitializePaystackPaymentDto,
  ) {
    await this.assertBranchInTenant(tenantId, dto.branchId);
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