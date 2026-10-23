import {
  Injectable,
  BadRequestException,
  NotFoundException,
  Logger,
  Optional,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, timingSafeEqual } from 'crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { JengaPaymentService } from '../payments/jenga-payment.service';
import { SubscriptionRenewalSettler } from './subscription-renewal-settler.service';
import { PLAN_PRICING, VALID_PLANS, selectedTrialPlan } from '../subscription/subscription.service';
import { describeLicense, resolveLicense } from '../license/license.catalog';
import { LegalPolicyService } from '../legal/legal-policy.service';

/** Grace days after an unpaid renewal before the tenant is suspended. */
const GRACE_DAYS = 3;
/** How long an auto-charge STK push may stay pending before we retry. */
const STK_PUSH_EXPIRY_HOURS = 24;
/** Max automatic STK prompts per invoice before Paystack checkout is required. */
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
    @Optional() private readonly legalPolicies?: LegalPolicyService,
  ) {}

  // ===== ADMIN CONFIGURATION =====

  /**
   * Owner-level billing settings: which phone gets the renewal STK push,
   * whether auto-renew is on and the billing phone.
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
        settings: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    const hasAutoRenewAuthorization = await this.legalPolicies?.hasCurrentAcceptance(
      tenantId,
      'AUTO_RENEWAL_AUTHORIZATION',
    ) ?? false;

    return {
      plan: tenant.plan,
      pendingPlan: selectedTrialPlan(tenant.settings) ??
        (tenant.subscriptionStatus === 'TRIAL' && tenant.plan !== 'TRIAL' ? tenant.plan : null),
      autoRenewEnabled: tenant.autoRenewEnabled && hasAutoRenewAuthorization,
      autoRenewAuthorizationRequired: !hasAutoRenewAuthorization,
      billingPhone: tenant.billingPhone,
      subscriptionStatus: tenant.subscriptionStatus,
      currentPeriodStart: tenant.currentPeriodStart,
      currentPeriodEnd: tenant.currentPeriodEnd,
      graceDays: GRACE_DAYS,
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

    if (input.autoRenewEnabled === true) {
      await this.legalPolicies?.assertCurrentAcceptance(
        tenantId,
        'AUTO_RENEWAL_AUTHORIZATION',
      );
    }

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, billingPhone: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    const nextBillingPhone = input.billingPhone !== undefined
      ? input.billingPhone
      : tenant.billingPhone;
    if (input.autoRenewEnabled === true && !nextBillingPhone) {
      throw new BadRequestException('Add a billing phone number before enabling Auto-Renew');
    }

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
        plan: { in: VALID_PLANS },
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
        settings: true,
      },
    });

    for (const tenant of due) {
      try {
        // Reuse an outstanding invoice before considering a new period.
        const planForInvoice = tenant.plan === 'TRIAL'
          ? selectedTrialPlan(tenant.settings) ?? 'CORE'
          : tenant.plan;
        const invoice = await this.ensureInvoiceForPeriod(tenant.id, planForInvoice, now);

        // Auto-charge only an unpaid invoice with no provider checkout already
        // in flight. A daily cron must never send duplicate STK prompts.
        if (invoice.status === 'PENDING') {
          const hasAutoRenewAuthorization = await this.legalPolicies?.hasCurrentAcceptance(
            tenant.id,
            'AUTO_RENEWAL_AUTHORIZATION',
          ) ?? false;
          if (
            invoice.provider === 'PAYSTACK' ||
            invoice.provider === 'PAYSTACK_INITIALIZING'
          ) {
            // Do not send an M-Pesa prompt while this same invoice has an
            // active hosted checkout; that could collect twice.
            summary.skipped.push({
              tenantId: tenant.id,
              reason: 'Paystack checkout is active for this invoice',
            });
          } else if (invoice.provider === 'JENGA_STK_INITIALIZING') {
            // A previous cron tick reserved this invoice before calling
            // Jenga. The provider request may have been accepted even if its
            // response timed out, so never issue a second prompt here.
            summary.skipped.push({
              tenantId: tenant.id,
              reason: 'An M-Pesa renewal request is being confirmed',
            });
          } else {
            let hasPendingStkPrompt = false;
            if (invoice.provider === 'JENGA_STK' && invoice.mpesaCheckoutId) {
              const existingPrompt = await this.prisma.mpesaTransaction.findUnique({
                where: { checkoutRequestId: invoice.mpesaCheckoutId },
                select: { status: true },
              });
              const terminalStatuses = ['failed', 'cancelled', 'canceled'];
              hasPendingStkPrompt = !existingPrompt ||
                !terminalStatuses.includes(existingPrompt.status.toLowerCase());
            }
            if (hasPendingStkPrompt) {
              summary.skipped.push({
                tenantId: tenant.id,
                reason: 'An M-Pesa renewal prompt is already awaiting a result',
              });
            } else if (!tenant.autoRenewEnabled || !tenant.billingPhone || !hasAutoRenewAuthorization) {
              summary.skipped.push({
                tenantId: tenant.id,
                reason: 'auto-renew disabled or no billing phone',
              });
            } else if (invoice.renewalSequence >= MAX_AUTO_CHARGE_ATTEMPTS) {
              summary.skipped.push({
                tenantId: tenant.id,
                reason: 'Automatic M-Pesa prompt limit reached — use the Paystack invoice checkout',
              });
            } else {
              // A saved Pesapal card can renew the same invoice. Never also
              // send an automatic M-Pesa prompt for that company.
              const cardToken = await this.prisma.subscriptionCardToken.findUnique({
                where: { tenantId: tenant.id },
                select: { status: true },
              });
              if (cardToken && ['ACTIVE', 'PENDING'].includes(cardToken.status)) {
                summary.skipped.push({
                  tenantId: tenant.id,
                  reason: 'Card auto-renewal is active or being set up',
                });
              } else {
                const pushed = await this.fireRenewalCharge(tenant, invoice);
                if (pushed) summary.charged.push(tenant.id);
              }
            }
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
    invoice: {
      id: string;
      amount: Prisma.Decimal;
      renewalSequence: number;
      provider?: string | null;
      reference?: string | null;
      mpesaCheckoutId?: string | null;
    },
  ): Promise<boolean> {
    const plan = PLAN_PRICING[tenant.plan];
    if (!plan) return false;

    const amount = Number(invoice.amount);
    if (amount <= 0) return false;

    const reference = `AXONSUB-${tenant.id.slice(0, 8)}-${invoice.renewalSequence}-${Date.now()}`;

    // Claim the invoice before contacting Jenga. The conditional update is a
    // single database operation, so parallel cron ticks or a simultaneous
    // Paystack checkout cannot both start a charge for the same invoice.
    const reserved = await this.prisma.subscriptionInvoice.updateMany({
      where: {
        id: invoice.id,
        status: 'PENDING',
        provider: invoice.provider ?? null,
        reference: invoice.reference,
        mpesaCheckoutId: invoice.mpesaCheckoutId,
        renewalSequence: invoice.renewalSequence,
      },
      data: {
        provider: 'JENGA_STK_INITIALIZING',
        reference,
        renewalSequence: { increment: 1 },
      },
    });
    if (reserved.count !== 1) return false;

    try {
      const push = await this.jenga.initiate({
        phoneNumber: tenant.billingPhone as string,
        amount,
        reference,
        description: `Counterbase ${plan.name} plan — ${this.monthLabel(new Date())}`,
      });

      await this.prisma.subscriptionInvoice.updateMany({
        where: {
          id: invoice.id,
          status: 'PENDING',
          provider: 'JENGA_STK_INITIALIZING',
          reference,
        },
        data: {
          mpesaCheckoutId: push.checkout_request_id,
          provider: 'JENGA_STK',
        },
      });
      return true;
    } catch (error: any) {
      this.logger.warn(
        `Renewal STK push failed for tenant ${tenant.id}: ${error?.message ?? error}`,
      );
      // A clear client rejection means Jenga did not accept the charge.
      // Release the reservation. Network/server errors stay reserved because
      // the provider may have accepted the request before timing out.
      const status = Number(error?.response?.status);
      if (status >= 400 && status < 500) {
        await this.prisma.subscriptionInvoice.updateMany({
          where: {
            id: invoice.id,
            status: 'PENDING',
            provider: 'JENGA_STK_INITIALIZING',
            reference,
          },
          data: { provider: null, reference: null },
        });
      }
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
    orderTrackingId: string,
    providerReference: string,
    amount: number | null,
    currency: string | null,
  ) {
    const cardToken = await this.prisma.subscriptionCardToken.findUnique({
      where: { tenantId },
      select: {
        orderTrackingId: true,
        billingCycle: true,
        plan: true,
        status: true,
      },
    });
    if (!cardToken || cardToken.orderTrackingId !== orderTrackingId || !providerReference) {
      this.logger.warn(`Pesapal recurring payment did not match a saved card mandate for tenant ${tenantId}`);
      return null;
    }

    const plan = PLAN_PRICING[cardToken.plan];
    const cycle = cardToken.billingCycle === 'YEARLY' ? 'YEARLY' : 'MONTHLY';
    const expectedAmount = plan
      ? plan.monthlyAmountKes * (cycle === 'YEARLY' ? 12 : 1)
      : null;
    if (
      !plan ||
      expectedAmount == null ||
      !Number.isFinite(amount) ||
      Math.abs(Number(amount) - expectedAmount) > 0.01 ||
      currency?.toUpperCase() !== 'KES'
    ) {
      this.logger.error(
        `Pesapal recurring payment mismatch for tenant ${tenantId}; expected ${expectedAmount} KES, received ${amount ?? 'unknown'} ${currency ?? 'unknown'}`,
      );
      return null;
    }

    const existing = await this.prisma.subscriptionInvoice.findUnique({
      where: { reference: providerReference },
    });
    if (existing && (
      existing.tenantId !== tenantId ||
      existing.plan !== cardToken.plan ||
      existing.currency !== 'KES' ||
      Math.abs(Number(existing.amount) - expectedAmount) > 0.01
    )) {
      this.logger.error(`Pesapal reference ${providerReference} is already bound to a different invoice`);
      return null;
    }
    if (existing?.status === 'PAID') return existing;

    return this.prisma.$transaction(async (tx) => {
      const invoice = await tx.subscriptionInvoice.findUnique({
        where: { reference: providerReference },
      });
      if (invoice && (
        invoice.tenantId !== tenantId ||
        invoice.plan !== cardToken.plan ||
        invoice.currency !== 'KES' ||
        Math.abs(Number(invoice.amount) - expectedAmount) > 0.01
      )) {
        return null;
      }
      if (invoice?.status === 'PAID') return invoice;

      const tenant = await tx.tenant.findUnique({
        where: { id: tenantId },
        select: { currentPeriodEnd: true },
      });
      if (!tenant) return null;
      const now = new Date();
      const periodStart = invoice?.periodStart ?? (
        tenant.currentPeriodEnd && tenant.currentPeriodEnd > now
          ? tenant.currentPeriodEnd
          : now
      );
      const periodEnd = cycle === 'YEARLY'
        ? this.addYear(periodStart)
        : this.addMonth(periodStart);
      const lastInvoice = await tx.subscriptionInvoice.findFirst({
        where: { tenantId },
        orderBy: { renewalSequence: 'desc' },
        select: { renewalSequence: true },
      });
      const paidInvoice = invoice
        ? await tx.subscriptionInvoice.update({
            where: { id: invoice.id },
            data: {
              status: 'PAID',
              amount: new Prisma.Decimal(expectedAmount),
              currency: 'KES',
              plan: cardToken.plan,
              paidAt: now,
              periodStart,
              periodEnd,
              provider: 'PESAPAL_CARD',
            },
          })
        : await tx.subscriptionInvoice.create({
            data: {
              tenantId,
              plan: cardToken.plan,
              amount: new Prisma.Decimal(expectedAmount),
              currency: 'KES',
              status: 'PAID',
              provider: 'PESAPAL_CARD',
              reference: providerReference,
              paidAt: now,
              periodStart,
              periodEnd,
              renewalSequence: (lastInvoice?.renewalSequence ?? 0) + 1,
            },
          });

      await tx.tenant.update({
        where: { id: tenantId },
        data: {
          plan: cardToken.plan,
          ...(plan ? {
            maxBranches: plan.features.maxBranches,
            maxUsers: plan.features.maxUsers,
          } : {}),
          subscriptionStatus: 'ACTIVE',
          currentPeriodStart: periodStart,
          currentPeriodEnd: periodEnd,
          subscriptionProvider: 'PESAPAL_CARD',
          subscriptionReference: providerReference,
        },
      });
      if (cardToken.status !== 'CANCELLED') {
        await tx.subscriptionCardToken.updateMany({
          where: { tenantId, orderTrackingId, status: { not: 'CANCELLED' } },
          data: { status: 'ACTIVE', cancelledAt: null },
        });
      }
      return paidInvoice;
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
        settings: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const effectivePlan = tenant.subscriptionStatus === 'TRIAL' ? 'TRIAL' : tenant.plan ?? 'TRIAL';
    const planMeta = PLAN_PRICING[effectivePlan] ?? PLAN_PRICING.TRIAL;
    const status = tenant.subscriptionStatus ?? 'ACTIVE';
    const paidUntil = tenant.currentPeriodEnd ?? null;
    const msPerDay = 24 * 60 * 60 * 1000;
    // Never negative: a lapsed period has 0 days left, and how late it is goes
    // in daysOverdue so the app can say "overdue by 3 days" instead of "-3".
    const rawDays =
      paidUntil !== null
        ? Math.floor((paidUntil.getTime() - Date.now()) / msPerDay)
        : 0;
    const daysRemaining = Math.max(0, rawDays);
    const daysOverdue =
      paidUntil !== null && paidUntil.getTime() < Date.now()
        ? Math.floor((Date.now() - paidUntil.getTime()) / msPerDay)
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
      plan: effectivePlan,
      status,
      paidUntil,
      daysRemaining,
      daysOverdue,
      graceUntil,
      features: {
        maxBranches: tenant.subscriptionStatus === 'TRIAL'
          ? planMeta.features.maxBranches
          : tenant.maxBranches ?? planMeta.features.maxBranches,
        maxUsers: tenant.subscriptionStatus === 'TRIAL'
          ? planMeta.features.maxUsers
          : tenant.maxUsers ?? planMeta.features.maxUsers,
      },
      restrictedMode,
      restrictedReason,
      // Which modules this company has paid for (see src/license). Everything
      // reads as unlocked until the operator switches enforcement on.
      license: describeLicense(
        resolveLicense(tenant, {
          defaultMode: this.config.get<'off' | 'warn' | 'enforce'>('LICENSE_ENFORCEMENT') ?? 'off',
        }),
      ),
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
      select: {
        id: true,
        plan: true,
        subscriptionStatus: true,
        currentPeriodEnd: true,
        maxBranches: true,
        maxUsers: true,
        settings: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    const license = describeLicense(
      resolveLicense(tenant, {
        defaultMode: this.config.get<'off' | 'warn' | 'enforce'>('LICENSE_ENFORCEMENT') ?? 'off',
      }),
    );

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
      plan: tenant.subscriptionStatus === 'TRIAL' ? 'TRIAL' : tenant.plan ?? 'TRIAL',
      validUntil: validUntil.toISOString(),
      offlineGraceUntil: new Date(
        validUntil.getTime() + OFFLINE_ENTITLEMENT_TTL_DAYS * 24 * 60 * 60 * 1000,
      ).toISOString(),
      issuedAt: now.toISOString(),
      // Signed so a device that is offline keeps the same module gates and
      // cannot unlock one by editing local storage.
      features: license.features,
      enforced: license.enforced,
      licenseExpiresAt: license.validUntil,
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
      select: { plan: true, currentPeriodEnd: true, subscriptionStatus: true, settings: true },
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

    const planForInvoice = tenant.plan === 'TRIAL'
      ? selectedTrialPlan(tenant.settings) ?? 'CORE'
      : tenant.plan ?? 'CORE';
    return this.ensureInvoiceForPeriod(tenantId, planForInvoice, now);
  }

  /** Return the current unpaid invoice for a customer-initiated checkout. */
  getInvoiceForPayment(tenantId: string) {
    return this.getCurrentInvoice(tenantId);
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
    // SERIALIZABLE prevents concurrent cron invocations from both observing
    // an empty period and creating duplicate invoices. Retry the one expected
    // serialization conflict so callers receive the winning invoice.
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        return await this.prisma.$transaction(async (tx) => {
          const openInvoice = await tx.subscriptionInvoice.findFirst({
            where: {
              tenantId,
              status: { in: ['PENDING', 'PENDING_CONFIRMATION'] },
            },
            orderBy: { createdAt: 'desc' },
          });
          if (openInvoice) return openInvoice;

          const existing = await tx.subscriptionInvoice.findFirst({
            where: { tenantId, periodStart },
          });
          if (existing) return existing;

          const plan = PLAN_PRICING[planId] ?? PLAN_PRICING.CORE;
          const periodEnd = this.addMonth(now);
          const lastInvoice = await tx.subscriptionInvoice.findFirst({
            where: { tenantId },
            orderBy: { renewalSequence: 'desc' },
            select: { renewalSequence: true },
          });

          return tx.subscriptionInvoice.create({
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
        }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
      } catch (error: any) {
        if (error?.code !== 'P2034' || attempt > 0) throw error;
      }
    }
    throw new Error('Could not reserve the subscription invoice');
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
