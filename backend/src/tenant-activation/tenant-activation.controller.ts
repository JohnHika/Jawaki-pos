import {
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, timingSafeEqual } from 'crypto';
import { Request } from 'express';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { TenantActivationService } from './tenant-activation.service';

@ApiTags('tenant-activation')
@Controller({ path: 'tenant-activation', version: '1' })
export class TenantActivationController {
  constructor(
    private readonly activationService: TenantActivationService,
    private readonly configService: ConfigService,
  ) {}

  @Get('status')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Get the current company activation status' })
  getStatus(@Req() req: any) {
    return this.activationService.getStatus(req.user.tenantId);
  }

  @Post('paystack/initialize')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Initialize the one-time KES 1,500 company activation checkout' })
  initialize(@Req() req: any, @Headers('idempotency-key') idempotencyKey?: string) {
    return this.activationService.initialize(
      req.user.tenantId,
      req.user.sub,
      req.user.email,
      idempotencyKey,
    );
  }

  @Get('paystack/verify/:reference')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Verify and activate a completed Paystack checkout' })
  verify(@Req() req: any, @Param('reference') reference: string) {
    return this.activationService.verify(req.user.tenantId, reference);
  }

  @Post('paystack/webhook')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Paystack webhook for company activation payments' })
  async webhook(
    @Req() req: Request & { rawBody?: Buffer },
    @Headers('x-paystack-signature') signature: string,
  ) {
    this.verifySignature(req.rawBody, signature);
    const { event, data } = req.body as { event: string; data: any };
    return this.activationService.handleWebhook(event, data);
  }

  private verifySignature(rawBody: Buffer | undefined, signature: string | undefined) {
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
