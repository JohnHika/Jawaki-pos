import {
  Controller,
  Get,
  Header,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Request } from 'express';
import { createHmac, timingSafeEqual } from 'crypto';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { TenantActivationService } from '../tenant-activation/tenant-activation.service';
import { PaystackBillingService } from './paystack-billing.service';

@ApiTags('billing')
@Controller({ path: 'billing/paystack', version: '1' })
export class PaystackWebhookController {
  constructor(
    private readonly config: ConfigService,
    private readonly activation: TenantActivationService,
    private readonly billing: PaystackBillingService,
  ) {}

  /** One Paystack dashboard endpoint handles activation and monthly invoices. */
  @Post('webhook')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Paystack webhook for activation and subscription invoices' })
  async webhook(
    @Req() req: Request & { rawBody?: Buffer },
    @Headers('x-paystack-signature') signature: string,
  ) {
    this.verifySignature(req.rawBody, signature);
    const { event, data } = req.body as { event: string; data: any };
    const product = this.productFromMetadata(data?.metadata);
    if (product === 'axon_startup_activation') {
      return this.activation.handleWebhook(event, data);
    }
    if (product === 'axon_subscription_invoice') {
      return this.billing.handleWebhook(event, data);
    }
    return { received: true, handled: false };
  }

  /** Return the mobile app to Billing; the app verifies the reference itself. */
  @Get('callback')
  @Header('Content-Type', 'text/html; charset=utf-8')
  @ApiOperation({ summary: 'Return a Paystack subscription checkout to Counterbase' })
  callback(@Query('reference') reference?: string) {
    const appUrl = `axonpos://payment/billing?reference=${encodeURIComponent(reference?.trim() ?? '')}`;
    return `<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Return to Counterbase</title></head>
<body style="font-family:system-ui,sans-serif;padding:32px;text-align:center">
<h1>Payment received</h1><p>Returning you to Counterbase to verify your subscription payment.</p>
<p><a href="${appUrl}">Return to Counterbase</a></p>
<script>window.location.replace(${JSON.stringify(appUrl)});</script>
</body></html>`;
  }

  private verifySignature(rawBody: Buffer | undefined, signature: string | undefined) {
    const secretKey = this.config.get<string>('PAYSTACK_SECRET_KEY');
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

  private productFromMetadata(value: unknown): string | undefined {
    let metadata: any = value;
    if (typeof value === 'string') {
      try {
        metadata = JSON.parse(value);
      } catch {
        return undefined;
      }
    }
    return metadata && typeof metadata === 'object'
      ? metadata.product?.toString()
      : undefined;
  }
}
