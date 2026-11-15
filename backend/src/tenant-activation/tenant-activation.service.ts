import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  Optional,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { publicApiBase } from '../common/public-api-url';
import { PaystackService } from '../ai-billing/paystack.service';
import { ReferralsService } from '../referrals/referrals.service';

/**
 * One-time setup fee, per the owner-approved terms (2026-11-04). It was
 * KES 35,000 before; shops that already paid keep that amount on record.
 */
export const AXON_STARTUP_FEE_KES = 125000;
const ACTIVATION_PRODUCT = 'axon_startup_activation';
/** Attempts opened at an older price, or paid with a different amount, wait here. */
const NEEDS_REVIEW = 'NEEDS_REVIEW';
const SUPERSEDED = 'SUPERSEDED';
// A checkout link older than this is replaced rather than reopened; a link
// that is still being created (INITIALIZED) is left alone for a short moment
// so a double tap does not open two.
const CHECKOUT_LINK_TTL_MS = 30 * 60 * 1000;
const SETUP_GRACE_MS = 60 * 1000;

@Injectable()
export class TenantActivationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystackService: PaystackService,
    private readonly configService: ConfigService,
    // Optional so the payment tests can build the service without it.
    @Optional() private readonly referrals?: ReferralsService,
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

    let key = idempotencyKey?.trim() || `legacy:${userId}`;
    const prior = await this.prisma.tenantActivationAttempt.findUnique({
      where: { tenantId_idempotencyKey: { tenantId, idempotencyKey: key } },
    });
    if (prior) {
      // A paid or held attempt is never touched. An unpaid one is reused only
      // while it can still be paid: a live checkout at the current price, or
      // one that was created a moment ago and is still being set up. Anything
      // else (failed, half-created, superseded, expired, or opened at an older
      // price) is closed and replaced, so a retry always gets a working link
      // instead of the same dead one.
      const unpaid = ['INITIALIZED', 'PENDING', 'FAILED'].includes(prior.status);
      if (prior.status !== SUPERSEDED && !unpaid) return this.formatStatus(tenant, prior);
      if (this.isUsableCheckout(prior)) return this.formatStatus(tenant, prior);
      if (unpaid) {
        await this.prisma.tenantActivationAttempt.update({
          where: { id: prior.id },
          data: { status: SUPERSEDED, authorizationUrl: null },
        });
      }
      // The client keeps sending the same key, so the replacement attempt is
      // found by recency rather than by key.
      const latest = await this.prisma.tenantActivationAttempt.findFirst({
        where: { tenantId }, orderBy: { createdAt: 'desc' },
      });
      if (latest && latest.id !== prior.id && this.isUsableCheckout(latest)) {
        return this.formatStatus(tenant, latest);
      }
      key = `${key}:${randomUUID().slice(0, 8)}`;
    }

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
        callbackUrl: this.activationCallbackUrl(),
        useEnabledChannels: true,
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

  /** A checkout the owner can still pay: current price and a link, or one being set up right now. */
  private isUsableCheckout(attempt: any): boolean {
    if (Number(attempt.amount ?? AXON_STARTUP_FEE_KES) !== AXON_STARTUP_FEE_KES) return false;
    const age = attempt.createdAt ? Date.now() - new Date(attempt.createdAt).getTime() : 0;
    if (attempt.status === 'PENDING') return !!attempt.authorizationUrl && age < CHECKOUT_LINK_TTL_MS;
    if (attempt.status === 'INITIALIZED') return age < SETUP_GRACE_MS;
    return false;
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
    const attempt = await this.prisma.tenantActivationAttempt.findUnique({ where: { reference } });
    if (!attempt) throw new NotFoundException('Activation payment reference not found');
    if (attempt.status === NEEDS_REVIEW) {
      return this.heldStatus(attempt);
    }

    // The payment must match both what this checkout was opened for and the
    // current setup fee. Anything else is real money that must not be lost or
    // silently accepted: hold it for a person to review, activate nothing.
    const quoted = Number(attempt.amount ?? AXON_STARTUP_FEE_KES);
    if (
      attempt.status !== 'PAID' &&
      (Number(charge.amount) !== quoted * 100 || quoted !== AXON_STARTUP_FEE_KES)
    ) {
      const held = await this.prisma.tenantActivationAttempt.update({
        where: { id: attempt.id },
        data: { status: NEEDS_REVIEW, authorizationUrl: null, providerResponse: charge as any },
      });
      return this.heldStatus(held);
    }

    // The webhook and the app's own verify call both land here for the same
    // payment. The second one must not restart the trial, or any bonus days
    // added after the first would be wiped.
    if (attempt.status === 'PAID') {
      const settled = await this.prisma.tenant.findUnique({
        where: { id: attempt.tenantId },
        select: { activationStatus: true, activationAmount: true, activationPaidAt: true },
      });
      return this.formatStatus(settled, attempt);
    }

    const paidAt = new Date();
    const trialEndsAt = new Date(paidAt);
    trialEndsAt.setDate(trialEndsAt.getDate() + 7);
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
        // Activation unlocks the workspace and starts a real seven-day trial.
        // Plan selection later replaces TRIAL with the chosen paid tier while
        // preserving this period end; the renewal cron then creates the first
        // monthly invoice when the trial expires.
        plan: 'TRIAL', subscriptionStatus: 'TRIAL',
        currentPeriodStart: paidAt, currentPeriodEnd: trialEndsAt,
        setupFeePaidAt: paidAt, maxBranches: 1, maxUsers: 3,
      },
      select: { activationStatus: true, activationAmount: true, activationPaidAt: true },
    });
    // Bonus days for referrals and promo codes. It never throws, so a problem
    // there cannot undo a payment that already went through.
    await this.referrals?.onActivated(attempt.tenantId);
    return this.formatStatus(tenant, updatedAttempt);
  }

  private activationCallbackUrl(): string | undefined {
    const explicit = this.configService
      .get<string>('PAYSTACK_ACTIVATION_CALLBACK_URL')
      ?.trim();
    if (explicit) return explicit;

    const publicBase = publicApiBase(this.configService);
    if (!publicBase) return undefined;

    const normalized = publicBase.replace(/\/+$/, '');
    const apiPrefix = normalized.endsWith('/api/v1')
        ? normalized
        : `${normalized}/api/v1`;
    return `${apiPrefix}/tenant-activation/paystack/callback`;
  }

  /** The payment went through but needs a person to check it; nothing activates. */
  private heldStatus(attempt: any) {
    return {
      status: 'PENDING',
      amountKes: AXON_STARTUP_FEE_KES,
      currency: 'KES',
      attemptId: attempt?.id,
      reference: attempt?.reference,
      provider: attempt?.provider,
      attemptStatus: NEEDS_REVIEW,
      paidAt: null,
      product: ACTIVATION_PRODUCT,
    };
  }

  private formatStatus(tenant: any, attempt: any) {
    return {
      status: tenant.activationStatus,
      // A shop that has paid keeps the amount it paid on record (35,000 for
      // the early shops). A shop that has not paid is quoted today's fee,
      // whatever default was stored when its row was created.
      amountKes:
        tenant.activationStatus === 'ACTIVE'
          ? Number(tenant.activationAmount ?? AXON_STARTUP_FEE_KES)
          : AXON_STARTUP_FEE_KES,
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
