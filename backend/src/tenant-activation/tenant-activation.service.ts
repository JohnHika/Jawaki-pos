import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
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
      select: {
        activationStatus: true,
        activationAmount: true,
        activationReference: true,
        activationProvider: true,
        activationAuthorizationUrl: true,
        activationPaidAt: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    return {
      status: tenant.activationStatus,
      amountKes: Number(tenant.activationAmount),
      currency: 'KES',
      reference: tenant.activationReference,
      provider: tenant.activationProvider,
      authorizationUrl: tenant.activationAuthorizationUrl,
      paidAt: tenant.activationPaidAt,
      product: ACTIVATION_PRODUCT,
    };
  }

  async initialize(tenantId: string, userId: string, email: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: {
        id: true,
        name: true,
        activationStatus: true,
        activationReference: true,
        activationAuthorizationUrl: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    if (tenant.activationStatus === 'ACTIVE') {
      return this.getStatus(tenantId);
    }

    if (tenant.activationReference && tenant.activationAuthorizationUrl) {
      return this.getStatus(tenantId);
    }

    const reference = `AXON-${tenant.id.slice(0, 8).toUpperCase()}-${Date.now()}`;
    const callbackUrl = this.configService.get<string>('PAYSTACK_ACTIVATION_CALLBACK_URL');
    const checkout = await this.paystackService.initializeTransaction({
      email,
      amountKes: AXON_STARTUP_FEE_KES,
      reference,
      metadata: {
        product: ACTIVATION_PRODUCT,
        tenantId,
        userId,
        companyName: tenant.name,
      },
      callbackUrl,
    });

    await this.prisma.tenant.update({
      where: { id: tenantId },
      data: {
        activationStatus: 'PENDING',
        activationAmount: AXON_STARTUP_FEE_KES,
        activationReference: checkout.reference,
        activationProvider: 'PAYSTACK',
        activationAuthorizationUrl: checkout.authorizationUrl,
      },
    });

    return this.getStatus(tenantId);
  }

  async verify(tenantId: string, reference: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { activationReference: true },
    });
    if (!tenant || tenant.activationReference !== reference) {
      throw new BadRequestException('Activation payment reference does not match this company');
    }

    const charge = await this.paystackService.verifyTransaction(reference);
    return this.activateFromCharge(reference, charge);
  }

  async handleWebhook(event: string, data: any) {
    if (event !== 'charge.success') {
      return { received: true, handled: false };
    }

    const metadata = data?.metadata as Record<string, unknown> | undefined;
    if (metadata?.product !== ACTIVATION_PRODUCT) {
      return { received: true, handled: false };
    }

    return this.activateFromCharge(data.reference, data);
  }

  private async activateFromCharge(reference: string, charge: any) {
    if (charge?.status !== 'success') {
      throw new BadRequestException('Activation payment has not completed successfully');
    }

    const expectedSubunits = AXON_STARTUP_FEE_KES * 100;
    if (Number(charge.amount) !== expectedSubunits) {
      throw new BadRequestException('Activation payment amount does not match KSh 50,000');
    }

    const tenant = await this.prisma.tenant.findUnique({
      where: { activationReference: reference },
      select: { id: true },
    });
    if (!tenant) throw new NotFoundException('Activation payment reference not found');

    const updated = await this.prisma.tenant.update({
      where: { id: tenant.id },
      data: {
        activationStatus: 'ACTIVE',
        isActive: true,
        activationProvider: 'PAYSTACK',
        activationPaidAt: new Date(),
      },
      select: {
        activationStatus: true,
        activationAmount: true,
        activationReference: true,
        activationProvider: true,
        activationPaidAt: true,
      },
    });

    return {
      status: updated.activationStatus,
      amountKes: Number(updated.activationAmount),
      currency: 'KES',
      reference: updated.activationReference,
      provider: updated.activationProvider,
      paidAt: updated.activationPaidAt,
      product: ACTIVATION_PRODUCT,
    };
  }
}
