import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, timingSafeEqual } from 'crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { JengaPaymentService } from '../payments/jenga-payment.service';
import { SubscriptionRenewalSettler } from './subscription-renewal-settler.service';
import { PLAN_PRICING, VALID_PLANS } from '../subscription/subscription.service';

/** Grace days after an unpaid renewal before the tenant is suspended. */
const GRACE_DAYS = 3;
/** How long an auto-charge STK push may stay pending before we retry. */
const STK_PUSH_EXPIRY_HOURS = 24;
/** Max auto-charge attempts per invoice before it must be paid manually. */
const MAX_AUTO_CHARGE_ATTEMPTS = 3;
/** How long a signed offline entitlement stays valid (7 days). */
export const OFFLINE_ENTITLEMENT_TTL_DAYS = 7;

@Injectable()
export class RecurringBillingService {
  private readonly logger = new Logger(RecurringBillingService.name);

  /**
   * Optional Pesapal card-billing hook, set by PesapalRecurringService on
   * module init (avoids a circular constructor dependency). Used only for
   * the stale-card-renewal safety net inside runRenewalCycle.
   */
  cardBilling?: {
    reportStaleCardRenewals(now: Date): Promise<{
      checked: number;
      warnings: { tenantId: string; reason: string }[];
    }>;
  };

  constructor(
    private readonly prisma: PrismaService,
    private readonly jenga: JengaPaymentService,
    private readonly config: ConfigService,
    private readonly settler: SubscriptionRenewalSettler,
  ) {}

  // ===== ADMIN CONFIGURATION =====

  /**
   * Owner-level billing settings: which phone gets the renewal STK push,
   * whether auto-renew is on, and the manual-paybill fallback details.
   */
  async getBillingSettings(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: {
        plan: true,
        autoRenewEnabled: true,
        billingPhone: true,
        subscriptionStatus: true,
        currentPeriodStart: true,
        currentPeriodEnd: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    return {
      plan: tenant.plan,
      autoRenewEnabled: tenant.autoRenewEnabled,
      billingPhone: tenant.billingPhone,
      subscriptionStatus: tenant.subscriptionStatus,
      currentPeriodStart: tenant.currentPeriodStart,
      currentPeriodEnd: tenant.currentPeriodEnd,
      graceDays: GRACE_DAYS,
      // Manual fallback (the "pay my paybill" path) — the number the
      // client can pay to when STK is not possible. Configurable via env.
      manualPaybill: {
        phone: this.config.get<string>('AXON_BILLING_PHONE', '0742126582'),
        accountFormat: 'COMPANY-<companyId>',
      },
    };
  }

  async updateBillingSettings(
    tenantId: string,
    input: { autoRenewEnabled?: boolean; billingPhone?: string | null },
  ) {
    if (input.billingPhone !== undefined && input.billingPhone !== null) {
      // Store normalized 2547XXXXXXXX so Jenga can dial it directly.
      try {
        input.billingPhone = normalizeKenyanPhone(input.billingPhone);
      } catch {
        throw new BadRequestException('billingPhone must be a valid Kenyan mobile number');
      }
    }

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const updated = await this.prisma.tenant.update({
      where: { id: tenantId },
      data: {
        ...(input.autoRenewEnabled !== undefined
          ? { autoRenewEnabled: input.autoRenewEnabled }
          : {}),
        ...(input.billingPhone !== undefined ? { billingPhone: input.billingPhone } : {}),
      },
      select: {
        autoRenewEnabled: true,
        billingPhone: true,
        plan: true,
        subscriptionStatus: true,
        currentPeriodEnd: true,
      },
    });
    return updated;
  }

  // ===== MANUAL PAYMENT (paybill / M-Pesa code entry) =====

  /**
   * Manual fallback: the client pays the AXON_BILLING_PHONE paybill from
   * their own M-Pesa menu and enters the confirmation code here. The code
   * is recorded as a claim against the current invoice and marked PENDING
   * until the owner confirms it (or until a matching amount shows up —
   * the owner has an admin confirm route below). This deliberately does
   * NOT auto-activate on code entry alone: unlike SMS text, we never
   * treat the client's typed code as proof of payment.
   */
  async submitManualPayment(
    tenantId: string,
    userId: string,
    input: { mpesaCode: string; amount?: number },
  ) {
    const invoice = await this.getCurrentInvoice(tenantId);
    if (!invoice) {
      throw new NotFoundException('No open invoice for this company');
    }

    const code = input.mpesaCode.trim().toUpperCase();
    if (!/^[A-Z0-9]{8,15}$/.test(code)) {
      throw new BadRequestException('M-Pesa confirmation code looks invalid');
    }

    const existing = await this.prisma.subscriptionPaymentClaim.findUnique({
      where: { mpesaCode: code },
    });
    if (existing) {
      throw new ConflictLikeError('This M-Pesa code has already been submitted');
    }

    const claim = await this.prisma.subscriptionPaymentClaim.create({
      data: {
        tenantId,
        invoiceId: invoice.id,
        mpesaCode: code,
        amount: input.amount ?? invoice.amount,
        submittedById: userId,
        status: 'PENDING',
      },
    });

    await this.prisma.subscriptionInvoice.update({
      where: { id: invoice.id },
      data: { status: 'PENDING_CONFIRMATION', provider: 'MPESA_MANUAL' },
    });

    return {
      claimId: claim.id,
      status: 'PENDING_CONFIRMATION',
      message:
        'Payment code received. Axon will confirm shortly and your subscription will continue.',
    };
  }

  /** Owner/admin confirms (or rejects) a manual payment claim. */
  async confirmManualPayment(
    ownerTenantId: string,
    claimId: string,
    approve: boolean,
  ) {
    const claim = await this.prisma.subscriptionPaymentClaim.findUnique({
      where: { id: claimId },
    });
    if (!claim) throw new NotFoundException('Payment claim not found');
    if (claim.tenantId !== ownerTenantId) {
      throw new ForbiddenException('Claim belongs to another company');
    }
    if (claim.status !== 'PENDING') {
      throw new BadRequestException(`Claim already ${claim.status}`);
    }

    if (!approve) {
      const rejected = await this.prisma.subscriptionPaymentClaim.update({
        where: { id: claimId },
        data: { status: 'REJECTED' },
      });
      return { claim: rejected, invoice: null };
    }

    const result = await this.prisma.$transaction(async (tx) => {
      const invoice = await tx.subscriptionInvoice.update({
        where: { id: claim.invoiceId },
        data: {
          status: 'PAID',
          paidAt: new Date(),
          provider: 'MPESA_MANUAL',
          reference: claim.mpesaCode,
        },
      });
      const updatedClaim = await tx.subscriptionPaymentClaim.update({
        where: { id: claimId },
        data: { status: 'APPROVED', decidedAt: new Date() },
      });
      // Payment covers the current period: mark the invoice PAID, then
      // activate + extend the tenant's period in the same transaction so a
      // crash can never leave an invoice paid but the tenant suspended.
      await this.activatePeriod(tx, claim.tenantId, invoice);
      return { claim: updatedClaim, invoice };
    });

    return result;
  }

  // ===== AUTO RENEWAL (cron) =====

  /**
   * The monthly renewal tick. For every tenant whose period has ended:
   * 1. Create the new period's invoice (idempotent per periodStart).
   * 2. If autoRenewEnabled + billingPhone set + Jenga configured → fire an
   *    STK push for the plan price (funds settle to the owner's Equity
   *    account via Jenga account-based settlement).
   * 3. If the invoice is still unpaid GRACE_DAYS after period end →
   *    suspend the tenant (subscriptionStatus = 'PAST_DUE').
   */
  async runRenewalCycle(now = new Date()) {
    const summary = {
      renewed: [] as string[],
      charged: [] as string[],
      suspended: [] as string[],
      skipped: [] as { tenantId: string; reason: string }[],
      cardRenewalWarnings: [] as { tenantId: string; reason: string }[],
    };

    const due = await this.prisma.tenant.findMany({
      where: {
        currentPeriodEnd: { lte: now },
        plan: { in: VALID_PLANS.filter((p) => p !== 'TRIAL') },
        activationStatus: 'ACTIVE',
      },
      select: {
        id: true,
        name: true,
        plan: true,
        autoRenewEnabled: true,
        billingPhone: true,
        subscriptionStatus: true,
        currentPeriodStart: true,
        currentPeriodEnd: true,
      },
    });

    for (const tenant of due) {
      try {
        // 1. Idempotent invoice creation for the new period.
        const invoice = await this.ensureInvoiceForPeriod(tenant.id, tenant.plan, now);

        // 2. Auto-charge if the invoice is still open.
        if (invoice.status === 'PENDING' || invoice.status === 'PENDING_CONFIRMATION') {
          if (!tenant.autoRenewEnabled || !tenant.billingPhone) {
            summary.skipped.push({
              tenantId: tenant.id,
              reason: 'auto-renew disabled or no billing phone',
            });
          } else if (invoice.renewalSequence >= MAX_AUTO_CHARGE_ATTEMPTS) {
            summary.skipped.push({
              tenantId: tenant.id,
              reason: 'max auto-charge attempts reached — manual payment required',
            });
          } else {
            const pushed = await this.fireRenewalCharge(tenant, invoice);
            if (pushed) summary.charged.push(tenant.id);
          }
        }

        // 3. Suspension check (only when well past grace).
        if (invoice.status === 'PENDING') {
          const invoiceAgeDays = Math.floor(
            (now.getTime() - new Date(invoice.createdAt).getTime()) / (1000 * 60 * 60 * 24),
          );
          const graceExpired =
            invoiceAgeDays >= GRACE_DAYS &&
            tenant.subscriptionStatus !== 'PAST_DUE';
          if (graceExpired) {
            await this.suspendTenant(tenant.id);
            summary.suspended.push(tenant.id);
          } else {
            summary.renewed.push(tenant.id);
          }
        } else if (invoice.status === 'PAID') {
          // Invoice paid but tenant row not yet activated — heal it.
          if (tenant.subscriptionStatus !== 'ACTIVE') {
            await this.prisma.tenant.update({
              where: { id: tenant.id },
              data: {
                subscriptionStatus: 'ACTIVE',
                currentPeriodStart: invoice.periodStart ?? now,
                currentPeriodEnd: invoice.periodEnd ?? this.addMonth(now),
              },
            });
          }
          summary.renewed.push(tenant.id);
        }
      } catch (error: any) {
        this.logger.error(
          `Renewal failed for tenant ${tenant.id}: ${error?.message ?? error}`,
        );
        summary.skipped.push({ tenantId: tenant.id, reason: 'error' });
      }
    }

    // 4. Card-renewal safety net: Pesapal owns the recurring charge schedule,
    //    so we never charge here — but if a tenant with a live card
    //    subscription still has a PENDING invoice >24h after period end,
    //    surface a warning so failures are visible in the logs.
    try {
      const staleCard = await this.cardBilling?.reportStaleCardRenewals(now);
      if (staleCard && staleCard.warnings.length > 0) {
        summary.cardRenewalWarnings = staleCard.warnings;
      }
    } catch (error: any) {
      this.logger.warn(
        `Card renewal safety net failed: ${error?.message ?? error}`,
      );
    }

    return summary;
  }

  /**
   * Fires the renewal STK push for an open invoice and links the checkout
   * reference to the invoice so the webhook/status query can settle it.
   */
  private async fireRenewalCharge(
    tenant: {
      id: string;
      plan: string;
      billingPhone: string | null;
    },
    invoice: { id: string; amount: Prisma.Decimal; renewalSequence: number },
  ): Promise<boolean> {
    const plan = PLAN_PRICING[tenant.plan];
    if (!plan) return false;

    const amount = Number(invoice.amount);
    if (amount <= 0) return false;

    const reference = `AXONSUB-${tenant.id.slice(0, 8)}-${invoice.renewalSequence}-${Date.now()}`;

    try {
      const push = await this.jenga.initiate({
        phoneNumber: tenant.billingPhone as string,
        amount,
        reference,
        description: `Axon POS ${plan.name} plan — ${this.monthLabel(new Date())}`,
      });

      await this.prisma.subscriptionInvoice.update({
        where: { id: invoice.id },
        data: {
          mpesaCheckoutId: push.checkout_request_id,
          provider: 'JENGA_STK',
          renewalSequence: { increment: 1 },
        },
      });
      return true;
    } catch (error: any) {
      this.logger.warn(
        `Renewal STK push failed for tenant ${tenant.id}: ${error?.message ?? error}`,
      );
      return false;
    }
  }

  /** Marks a tenant PAST_DUE (read-only mode handled by guards). */
  private async suspendTenant(tenantId: string) {
    await this.prisma.tenant.update({
      where: { id: tenantId },
      data: { subscriptionStatus: 'PAST_DUE' },
    });
    this.logger.warn(`Tenant ${tenantId} suspended (PAST_DUE) after grace period`);
  }

  /**
   * Called by the payments module when an STK push for an AXONSUB
   * reference completes: mark the invoice paid and activate the period.
   *
   * Delegates to SubscriptionRenewalSettler, a Prisma-only provider, so the
   * Jenga status query can settle AXONSUB-* payments directly through it
   * without RecurringBillingService and JengaPaymentService importing each
   * other (no circular dependency).
   */
  async settleRenewalPayment(checkoutRequestId: string) {
    return this.settler.settleByCheckoutId(checkoutRequestId);
  }

  /**
   * Card auto-renewal settlement (Pesapal recurring): marks the tenant's
   * open invoice PAID and extends the period by the card subscription's
   * billing cycle. correlationId is Pesapal's recurring-payment id kept
   * on the invoice reference for reconciliation.
   */
  async settleCardRenewal(
    tenantId: string,
    correlationId: string,
    _amount?: number,
  ) {
    const invoice = await this.prisma.subscriptionInvoice.findFirst({
      where: {
        tenantId,
        status: { notIn: ['PAID'] },
        periodStart: { not: null },
      },
      orderBy: { createdAt: 'desc' },
    });
    if (!invoice) return null;

    // Period length follows the card subscription's billing cycle — ANNUAL
    // billing extends by one year, otherwise by one month.
    const cardToken = await this.prisma.subscriptionCardToken.findUnique({
      where: { tenantId },
      select: { billingCycle: true },
    });
    const cycle = cardToken?.billingCycle === 'YEARLY' ? 'YEARLY' : 'MONTHLY';

    const periodStart = new Date();
    const periodEnd =
      cycle === 'YEARLY' ? this.addYear(periodStart) : this.addMonth(periodStart);

    return this.prisma.$transaction(async (tx) => {
      const paid = await tx.subscriptionInvoice.update({
        where: { id: invoice.id },
        data: {
          status: 'PAID',
          paidAt: new Date(),
          periodStart,
          periodEnd,
          provider: 'PESAPAL_CARD',
          reference: correlationId,
        },
      });
      await tx.tenant.update({
        where: { id: tenantId },
        data: {
          subscriptionStatus: 'ACTIVE',
          currentPeriodStart: periodStart,
          currentPeriodEnd: periodEnd,
          subscriptionProvider: 'PESAPAL_CARD',
        },
      });
      return paid;
    });
  }

  // ===== ENTITLEMENTS =====

  /**
   * The tenant's entitlement snapshot: plan, status, days remaining, grace
   * window, plan feature limits, and whether the tenant is currently in
   * restricted (read-only) mode. Guards reuse isTenantRestricted; this
   * endpoint powers the mobile app's subscription banner and offline gate.
   */
  async getEntitlement(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: {
        id: true,
        plan: true,
        subscriptionStatus: true,
        currentPeriodEnd: true,
        maxBranches: true,
        maxUsers: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const planMeta = PLAN_PRICING[tenant.plan ?? 'TRIAL'] ?? PLAN_PRICING.TRIAL;
    const status = tenant.subscriptionStatus ?? 'ACTIVE';
    const paidUntil = tenant.currentPeriodEnd ?? null;
    const msPerDay = 24 * 60 * 60 * 1000;
    const daysRemaining =
      paidUntil !== null
        ? Math.floor((paidUntil.getTime() - Date.now()) / msPerDay)
        : 0;

    // Within the grace window the tenant keeps full write access even though
    // the paid period has lapsed.
    const graceUntil =
      paidUntil !== null
        ? new Date(paidUntil.getTime() + GRACE_DAYS * msPerDay)
        : null;
    const inGrace = graceUntil !== null && graceUntil.getTime() > Date.now();

    let restrictedMode = false;
    let restrictedReason: string | null = null;
    if (status === 'ACTIVE' || status === 'TRIAL') {
      // Paid/trial period still running (or the period simply hasn't been
      // ticked over by the cron yet): never restricted. An expired period
      // with a stale ACTIVE status heals on the next renewal tick.
      restrictedMode = false;
      restrictedReason = null;
    } else if (status === 'PAST_DUE') {
      if (inGrace) {
        restrictedMode = false;
        restrictedReason = 'grace_period';
      } else {
        restrictedMode = true;
        restrictedReason = 'payment_overdue';
      }
    } else {
      // SUSPENDED / CANCELLED
      restrictedMode = true;
      restrictedReason = 'payment_overdue';
    }

    return {
      plan: tenant.plan ?? 'TRIAL',
      status,
      paidUntil,
      daysRemaining,
      graceUntil,
      features: {
        maxBranches: tenant.maxBranches ?? planMeta.features.maxBranches,
        maxUsers: tenant.maxUsers ?? planMeta.features.maxUsers,
      },
      restrictedMode,
      restrictedReason,
    };
  }

  /**
   * Signed offline entitlement: lets a device keep operating through the
   * 7-day offline grace even if it cannot reach the API to re-check status.
   * HMAC-SHA256 over the base64url payload with ENTITLEMENT_SECRET (falls
   * back to JWT_SECRET); format: base64url(payload JSON) + '.' + base64url(hmac).
   */
  async buildOfflineEntitlement(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, plan: true, subscriptionStatus: true, currentPeriodEnd: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const now = new Date();
    const paidUntil = tenant.currentPeriodEnd ?? new Date(now.getTime() + OFFLINE_ENTITLEMENT_TTL_DAYS * 24 * 60 * 60 * 1000);
    // A suspended tenant gets an already-expired entitlement (validUntil in
    // the past), so offline devices degrade to read-only immediately.
    const validUntil =
      tenant.subscriptionStatus === 'PAST_DUE' || tenant.subscriptionStatus === 'SUSPENDED'
        ? now
        : paidUntil;
    const payload = {
      tenantId: tenant.id,
      plan: tenant.plan ?? 'TRIAL',
      validUntil: validUntil.toISOString(),
      offlineGraceUntil: new Date(
        validUntil.getTime() + OFFLINE_ENTITLEMENT_TTL_DAYS * 24 * 60 * 60 * 1000,
      ).toISOString(),
      issuedAt: now.toISOString(),
    };

    const secret = this.config.get<string>('ENTITLEMENT_SECRET') || this.config.get<string>('JWT_SECRET') || '';
    const body = base64UrlEncode(JSON.stringify(payload));
    const signature = base64UrlEncode(
      createHmac('sha256', secret).update(body).digest(),
    );
    return { ...payload, signature: `${body}.${signature}` };
  }

  /**
   * Verifies a signed offline entitlement (see buildOfflineEntitlement).
   * Static so offline tooling and tests can validate without DI. Returns
   * the payload when valid; throws when the signature or shape is wrong.
   */
  static verifyOfflineEntitlement(
    payload: Record<string, unknown>,
    signature: string,
    secretOverride?: string,
  ): Record<string, unknown> {
    if (typeof signature !== 'string' || !signature.includes('.')) {
      throw new Error('Malformed entitlement signature');
    }
    const [body, mac] = signature.split('.');
    const secret =
      secretOverride ?? process.env.ENTITLEMENT_SECRET ?? process.env.JWT_SECRET ?? '';
    const expected = createHmac('sha256', secret).update(body).digest();
    const given = base64UrlDecode(mac);
    if (given.length !== expected.length || !timingSafeEqual(given, expected)) {
      throw new Error('Invalid entitlement signature');
    }
    const decoded = JSON.parse(base64UrlDecode(body).toString('utf8')) as Record<string, unknown>;
    if (decoded.tenantId !== payload.tenantId) {
      throw new Error('Entitlement payload does not match signature');
    }
    return decoded;
  }

  // ===== HELPERS =====

  /**
   * Marks a period as paid: activates the tenant and sets the new period
   * window from the invoice. Runs inside the caller's transaction so the
   * invoice write and the tenant activation commit atomically.
   */
  private async activatePeriod(
    tx: { tenant: { update: (args: any) => Promise<any> } },
    tenantId: string,
    invoice: { periodStart?: Date | null; periodEnd?: Date | null; plan?: string },
  ) {
    const now = new Date();
    const periodStart = invoice.periodStart ?? now;
    const periodEnd = invoice.periodEnd ?? this.addMonth(now);
    return tx.tenant.update({
      where: { id: tenantId },
      data: {
        subscriptionStatus: 'ACTIVE',
        currentPeriodStart: periodStart,
        currentPeriodEnd: periodEnd,
        ...(invoice.plan ? { plan: invoice.plan } : {}),
      },
    });
  }

  /** The current open (unpaid) invoice, creating one if the period ended. */
  private async getCurrentInvoice(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { plan: true, currentPeriodEnd: true, subscriptionStatus: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const now = new Date();
    const invoice = await this.prisma.subscriptionInvoice.findFirst({
      where: { tenantId, status: { notIn: ['PAID'] } },
      orderBy: { createdAt: 'desc' },
    });
    if (invoice) return invoice;

    // Period may not have ended yet — no open invoice.
    if (tenant.currentPeriodEnd && tenant.currentPeriodEnd > now) return null;

    return this.ensureInvoiceForPeriod(tenantId, tenant.plan ?? 'CORE', now);
  }

  /**
   * Creates exactly one invoice per (tenantId, periodStart). Idempotent:
   * concurrent cron ticks can't double-invoice the same period.
   */
  private async ensureInvoiceForPeriod(
    tenantId: string,
    planId: string,
    now: Date,
  ) {
    const periodStart = this.startOfDay(now);
    const existing = await this.prisma.subscriptionInvoice.findFirst({
      where: { tenantId, periodStart },
    });
    if (existing) return existing;

    const plan = PLAN_PRICING[planId] ?? PLAN_PRICING.CORE;
    const periodEnd = this.addMonth(now);

    const lastInvoice = await this.prisma.subscriptionInvoice.findFirst({
      where: { tenantId },
      orderBy: { renewalSequence: 'desc' },
      select: { renewalSequence: true },
    });

    return this.prisma.subscriptionInvoice.create({
      data: {
        tenantId,
        plan: planId,
        amount: new Prisma.Decimal(plan.monthlyAmountKes),
        currency: 'KES',
        status: 'PENDING',
        periodStart,
        periodEnd,
        renewalSequence: (lastInvoice?.renewalSequence ?? 0) + 1,
      },
    });
  }

  private startOfDay(d: Date) {
    return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  }

  private addMonth(d: Date) {
    const next = new Date(d);
    next.setMonth(next.getMonth() + 1);
    return next;
  }

  private addYear(d: Date) {
    const next = new Date(d);
    next.setFullYear(next.getFullYear() + 1);
    return next;
  }

  private monthLabel(d: Date) {
    return d.toLocaleString('en-KE', { month: 'long', year: 'numeric' });
  }
}

/** Local conflict error to avoid importing HttpException plumbing. */
class ConflictLikeError extends Error {}

/** Normalizes 07.. / 2547.. / +2547.. into 2547XXXXXXXX. */
export function normalizeKenyanPhone(value: string): string {
  const digits = value.replace(/\D/g, '');
  if (/^0[17]\d{8}$/.test(digits)) return `254${digits.slice(1)}`;
  if (/^[17]\d{8}$/.test(digits)) return `254${digits}`;
  if (/^254[17]\d{8}$/.test(digits)) return digits;
  throw new BadRequestException('Invalid Kenyan mobile number');
}

/** Base64url encode (no padding) for the offline entitlement token. */
export function base64UrlEncode(value: string | Buffer): string {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/** Base64url decode (padding-tolerant). */
export function base64UrlDecode(value: string): Buffer {
  const b64 = value.replace(/-/g, '+').replace(/_/g, '/');
  return Buffer.from(b64, 'base64');
}

/** Minimal shape of the tenant row the restriction helper needs. */
export interface RestrictionTenantLike {
  subscriptionStatus?: string | null;
  currentPeriodEnd?: Date | null;
  plan?: string | null;
}

/**
 * True when the tenant is in restricted (read-only) mode: PAST_DUE beyond
 * the grace window, SUSPENDED, or CANCELLED. Guards call this so a mutating
 * route can be answered with 402 while read-only routes stay open — never
 * block historical data.
 */
export function isTenantRestricted(tenant: RestrictionTenantLike, now = new Date()) {
  const status = (tenant.subscriptionStatus ?? 'ACTIVE').toUpperCase();
  if (status === 'ACTIVE' || status === 'TRIAL') {
    return { restricted: false as const, reason: null };
  }
  const periodEnd = tenant.currentPeriodEnd
    ? new Date(tenant.currentPeriodEnd)
    : null;
  if (!periodEnd) {
    // No period window at all: cannot compute grace, treat as restricted.
    return { restricted: true as const, reason: 'payment_overdue' };
  }
  const graceUntil = periodEnd.getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000;
  if (status === 'PAST_DUE' && now.getTime() <= graceUntil) {
    return { restricted: false as const, reason: 'grace_period' as const };
  }
  return { restricted: true as const, reason: 'payment_overdue' };
}