import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { PaystackService } from '../ai-billing/paystack.service';

export const AXON_STARTUP_FEE_KES = 50000;
const ACTIVATION_PRODUCT = 'axon_startup_activation';

@Injectable()
export class TenantActivationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystackService: PaystackService,
    private readonly configService: ConfigService,
  ) {}

  async getStatus(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { activationStatus: true, activationAmount: true, activationPaidAt: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    const attempt = await this.prisma.tenantActivationAttempt.findFirst({
      where: { tenantId }, orderBy: { createdAt: 'desc' },
    });
    return this.formatStatus(tenant, attempt);
  }

  async initialize(tenantId: string, userId: string, email: string, idempotencyKey?: string) {
    const verifiedUser = await this.prisma.user.findFirst({
      where: { id: userId, tenantId, email, isActive: true, identityVerifiedAt: { not: null } },
      select: { id: true },
    });
    if (!verifiedUser) {
      throw new ForbiddenException('A verified account is required to initialize activation payment');
    }
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, name: true, activationStatus: true, activationAmount: true, activationPaidAt: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    if (tenant.activationStatus === 'ACTIVE') return this.getStatus(tenantId);

    const key = idempotencyKey?.trim() || `legacy:${userId}`;
    const prior = await this.prisma.tenantActivationAttempt.findUnique({
      where: { tenantId_idempotencyKey: { tenantId, idempotencyKey: key } },
    });
    if (prior) return this.formatStatus(tenant, prior);

    const reference = `AXON-${tenant.id.slice(0, 8).toUpperCase()}-${randomUUID()}`;
    let attempt: any;
    try {
      attempt = await this.prisma.tenantActivationAttempt.create({
        data: {
          tenantId,
          userId,
          email: email.trim().toLowerCase(),
          idempotencyKey: key,
          reference,
          provider: 'PAYSTACK',
          amount: AXON_STARTUP_FEE_KES,
          status: 'INITIALIZED',
        },
      });
    } catch (error: any) {
      if (error?.code === 'P2002') {
        const raced = await this.prisma.tenantActivationAttempt.findUnique({
          where: { tenantId_idempotencyKey: { tenantId, idempotencyKey: key } },
        });
        if (raced) return this.formatStatus(tenant, raced);
      }
      throw error;
    }

    try {
      const checkout = await this.paystackService.initializeTransaction({
        email,
        amountKes: AXON_STARTUP_FEE_KES,
        reference,
        metadata: { product: ACTIVATION_PRODUCT, tenantId, userId, companyName: tenant.name, attemptId: attempt.id },
        callbackUrl: this.configService.get<string>('PAYSTACK_ACTIVATION_CALLBACK_URL'),
      });
      const updated = await this.prisma.tenantActivationAttempt.update({
        where: { id: attempt.id },
        data: { status: 'PENDING', authorizationUrl: checkout.authorizationUrl, providerResponse: checkout as any },
      });
      return this.formatStatus(tenant, updated);
    } catch (error) {
      await this.prisma.tenantActivationAttempt.update({
        where: { id: attempt.id }, data: { status: 'FAILED' },
      });
      throw error;
    }
  }

  async verify(tenantId: string, reference: string) {
    const attempt = await this.prisma.tenantActivationAttempt.findFirst({ where: { tenantId, reference } });
    if (!attempt) throw new BadRequestException('Activation payment reference does not match this company');
    const charge = await this.paystackService.verifyTransaction(reference);
    return this.activateFromCharge(reference, charge);
  }

  async handleWebhook(event: string, data: any) {
    if (event !== 'charge.success' || data?.metadata?.product !== ACTIVATION_PRODUCT) {
      return { received: true, handled: false };
    }
    return this.activateFromCharge(data.reference, data);
  }

  private async activateFromCharge(reference: string, charge: any) {
    if (charge?.status !== 'success') throw new BadRequestException('Activation payment has not completed successfully');
    if (Number(charge.amount) !== AXON_STARTUP_FEE_KES * 100) {
      throw new BadRequestException('Activation payment amount does not match KSh 50,000');
    }
    const attempt = await this.prisma.tenantActivationAttempt.findUnique({ where: { reference } });
    if (!attempt) throw new NotFoundException('Activation payment reference not found');

    const paidAt = new Date();
    const updatedAttempt = await this.prisma.tenantActivationAttempt.update({
      where: { id: attempt.id },
      data: { status: 'PAID', verifiedAt: paidAt, providerResponse: charge as any },
    });
    // Compatibility snapshot only: initialization never writes mutable tenant
    // references, so repeat checkouts cannot overwrite an earlier attempt.
    const tenant = await this.prisma.tenant.update({
      where: { id: attempt.tenantId },
      data: {
        activationStatus: 'ACTIVE', isActive: true, activationAmount: AXON_STARTUP_FEE_KES,
        activationReference: reference, activationProvider: 'PAYSTACK', activationPaidAt: paidAt,
      },
      select: { activationStatus: true, activationAmount: true, activationPaidAt: true },
    });
    return this.formatStatus(tenant, updatedAttempt);
  }

  private formatStatus(tenant: any, attempt: any) {
    return {
      status: tenant.activationStatus,
      amountKes: Number(tenant.activationAmount ?? AXON_STARTUP_FEE_KES),
      currency: 'KES',
      attemptId: attempt?.id,
      reference: attempt?.reference,
      provider: attempt?.provider,
      authorizationUrl: attempt?.authorizationUrl,
      attemptStatus: attempt?.status,
      paidAt: attempt?.verifiedAt ?? tenant.activationPaidAt,
      product: ACTIVATION_PRODUCT,
    };
  }
}
