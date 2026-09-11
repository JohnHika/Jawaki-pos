import {
  Controller,
  Post,
  Get,
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

  /**
   * Paystack webhook — dormant. The separate AI subscription that this
   * webhook activated no longer exists (AI is included in every plan), but
   * the endpoint is kept so any stray webhook deliveries are acknowledged
   * instead of erroring. Verifies the `x-paystack-signature` header against
   * the raw request body before trusting the payload.
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