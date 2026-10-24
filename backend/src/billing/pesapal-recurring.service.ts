import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../common/prisma/prisma.service";
import { PesapalPaymentService } from "../payments/pesapal-payment.service";
import { RecurringBillingService } from "./recurring-billing.service";
import { PLAN_PRICING, VALID_PLANS } from "../subscription/subscription.service";

/** How long a submitted subscription may stay PENDING before we re-submit. */
const CARD_SUBSCRIPTION_PENDING_HOURS = 24;
/** Grace window before a stale card token is flagged. */
const CARD_STALE_HOURS = 24;

export type BillingCycle = "MONTHLY" | "YEARLY";

export function addCycle(date: Date, cycle: BillingCycle): Date {
  const next = new Date(date);
  if (cycle === "YEARLY") next.setFullYear(next.getFullYear() + 1);
  else next.setMonth(next.getMonth() + 1);
  return next;
}

export function buildAccountNumber(tenantId: string, now: Date): string {
  return `AXONSUBCARD-${tenantId}-${now.getTime()}`;
}

@Injectable()
export class PesapalRecurringService implements OnModuleInit {
  private readonly logger = new Logger(PesapalRecurringService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly pesapal: PesapalPaymentService,
    private readonly recurring: RecurringBillingService,
    private readonly config: ConfigService,
  ) {}

  /** Registers the stale-card-renewal safety net with the cron service. */
  onModuleInit() {
    this.recurring.cardBilling = {
      reportStaleCardRenewals: (now: Date) => this.reportStaleCardRenewals(now),
    };
  }

  // ===== (a) START CARD SUBSCRIPTION =====

  /**
   * Kicks off a Pesapal card subscription for the tenant's plan.
   * Returns the Pesapal redirect URL — the customer completes the opt-in
   * (and card tokenization) on the Pesapal iframe; we never see card data.
   */
  async startCardSubscription(tenantId: string, planId: string, billingCycle: BillingCycle) {
    if (billingCycle !== "MONTHLY" && billingCycle !== "YEARLY") {
      throw new BadRequestException("billingCycle must be MONTHLY or YEARLY");
    }
    if (!VALID_PLANS.includes(planId) || planId === "TRIAL") {
      throw new BadRequestException(
        `planId must be a paid plan (${VALID_PLANS.filter((p) => p !== "TRIAL").join(" / ")})`,
      );
    }
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, name: true, plan: true, subscriptionStatus: true },
    });
    if (!tenant) throw new NotFoundException("Company not found");

    const plan = PLAN_PRICING[planId];
    const now = new Date();
    // Annual pricing = 12 × monthly, as the current plan catalog has no
    // separate annual price point.
    const amount = new Prisma.Decimal(plan.monthlyAmountKes).mul(
      billingCycle === "YEARLY" ? 12 : 1,
    );

    // Idempotency: reuse an existing live subscription instead of stacking a
    // second one on the same card.
    const existing = await this.prisma.subscriptionCardToken.findUnique({
      where: { tenantId },
    });
    if (existing && existing.status !== "CANCELLED" && existing.status !== "FAILED") {
      if (existing.status === "ACTIVE" && existing.plan === planId && existing.billingCycle === billingCycle) {
        return {
          alreadyActive: true,
          subscriptionId: existing.id,
          message: "A card subscription for this plan is already active.",
        };
      }
      if (existing.status === "ACTIVE") {
        throw new ConflictException(
          "An active Pesapal card subscription already exists. Cancel it through the management link in Pesapal’s email before changing plans or billing frequency.",
        );
      }
      if (existing.status === "PENDING") {
        const ageHours = (Date.now() - new Date(existing.createdAt).getTime()) / 3_600_000;
        if (
          existing.plan === planId &&
          existing.billingCycle === billingCycle &&
          ageHours < CARD_SUBSCRIPTION_PENDING_HOURS
        ) {
          return {
            alreadyPending: true,
            subscriptionId: existing.id,
            message: "A card subscription setup is already awaiting the customer on the Pesapal page.",
          };
        }
        throw new ConflictException(
          "A Pesapal card setup is still pending. Complete or cancel it through Pesapal before starting another subscription.",
        );
      }
      throw new ConflictException(
        "A card subscription already exists and its provider status is not safe to replace. Contact support before starting another one.",
      );
    }

    const accountNumber = buildAccountNumber(tenantId, now);
    const startDate = now;
    const endDate = addCycle(now, "YEARLY"); // Pesapal contract: end = start + 1 year

    const payload = this.pesapal.buildRecurringOrderRequest({
      accountNumber,
      amount: Number(amount),
      description: `Counterbase ${plan.name} plan — card auto-renew (${billingCycle.toLowerCase()})`,
      billingCycle,
      startDate,
      endDate,
    });

    const submitted = await this.pesapal.submitOrderRequest(payload);

    const token = await this.prisma.subscriptionCardToken.upsert({
      where: { tenantId },
      create: {
        tenantId,
        pesapalCorrelationId: accountNumber,
        orderTrackingId: submitted.orderTrackingId,
        status: "PENDING",
        billingCycle,
        plan: planId,
      },
      update: {
        pesapalCorrelationId: accountNumber,
        orderTrackingId: submitted.orderTrackingId,
        status: "PENDING",
        billingCycle,
        plan: planId,
        cancelledAt: null,
      },
    });

    return {
      subscriptionId: token.id,
      orderTrackingId: submitted.orderTrackingId,
      redirectUrl: submitted.redirectUrl,
      accountNumber,
      plan: planId,
      billingCycle,
      amount: Number(amount),
      currency: "KES",
      nextChargeDate: addCycle(now, billingCycle),
    };
  }

  // ===== (b) RECURRING IPN =====

  /**
   * Pesapal recurring IPN. Query shape (GET):
   *   OrderNotificationType=RECURRING&OrderTrackingId=...&OrderMerchantReference=...
   *
   * The IPN is unauthenticated, so nothing in the query is trusted: the
   * only state change happens after an authenticated GetTransactionStatus
   * call confirms the payment (the Jenga callback pattern in this codebase).
   */
  async handleRecurringIpn(query: Record<string, unknown>) {
    const type = String(query.OrderNotificationType ?? "").toUpperCase();
    const orderTrackingId = String(query.OrderTrackingId ?? "").trim();
    const merchantReference = String(query.OrderMerchantReference ?? "").trim();

    if (!orderTrackingId || !merchantReference) {
      throw new BadRequestException("IPN missing OrderTrackingId/OrderMerchantReference");
    }
    if (type && type !== "RECURRING") {
      // Not a recurring notification — accept (200) but do nothing.
      return { result: "ignored", reason: `notification type ${type} not handled` };
    }

    const token = await this.prisma.subscriptionCardToken.findFirst({
      where: { pesapalCorrelationId: merchantReference },
    });

    await this.prisma.pesapalTransaction.create({
      data: {
        orderTrackingId,
        merchantReference,
        amount: new Prisma.Decimal(0),
        currency: "KES",
        description: `RECURRING IPN type=${type || "UNKNOWN"}`,
        status: "ipn_received",
        ipnPayload: query as Prisma.InputJsonValue,
      },
    });

    if (!token) {
      this.logger.warn(
        `Pesapal recurring IPN for unknown tracking id ${orderTrackingId}`,
      );
      return { result: "ignored", reason: "unknown subscription" };
    }

    // The recurring IPN's OrderMerchantReference is the stable account_number
    // submitted when the mandate was created. Reject mismatches before the
    // provider status lookup; provider-generated transaction references are
    // checked separately below.
    // IPN carries no payment details → authenticate then settle server-side.
    const status = await this.pesapal.getTransactionStatus(orderTrackingId);

    if (status.paymentStatus !== "COMPLETED") {
      this.logger.warn(
        `Pesapal recurring IPN for ${orderTrackingId}: status ${status.paymentStatus || "UNKNOWN"} — not settling`,
      );
      return {
        result: "accepted",
        settled: false,
        paymentStatus: status.paymentStatus || "UNKNOWN",
      };
    }

    if (status.orderTrackingId !== orderTrackingId) {
      this.logger.warn(
        `Pesapal recurring tracking id mismatch for ${orderTrackingId}`,
      );
      return { result: "rejected", reason: "provider tracking id mismatch" };
    }

    const providerAccountReference = status.subscriptionTransactionInfo?.accountReference;
    if (
      !providerAccountReference ||
      providerAccountReference !== token.pesapalCorrelationId
    ) {
      this.logger.warn(
        `Pesapal recurring IPN account reference mismatch for ${orderTrackingId}`,
      );
      return { result: "rejected", reason: "subscription account reference mismatch" };
    }

    // Pesapal documents correlation_id as the unique ID for each recurring
    // payment. The account_reference above identifies the mandate; using that
    // stable account number as an invoice reference would collapse every
    // renewal into the first paid invoice.
    const providerCorrelation = status.subscriptionTransactionInfo?.correlationId?.trim();
    if (!providerCorrelation) {
      this.logger.warn(
        `Pesapal recurring payment has no unique correlation id for ${orderTrackingId}`,
      );
      return { result: "rejected", reason: "unique recurring payment reference missing" };
    }

    const amount = status.amount ?? status.subscriptionTransactionInfo?.amount ?? null;
    const invoice = await this.recurring.settleCardRenewal(
      token.tenantId,
      providerCorrelation,
      amount,
      status.currency,
    );

    if (!invoice) {
      return {
        result: "rejected",
        settled: false,
        reason: "verified payment did not match an invoice amount or existing provider reference",
      };
    }

    // A completed charge settles the period, but a cancellation state must
    // never be reactivated by a late provider notification.
    if (token.status !== "ACTIVE" && token.status !== "CANCELLED") {
      await this.prisma.subscriptionCardToken.update({
        where: { id: token.id },
        data: { status: "ACTIVE", cancelledAt: null },
      });
    }

    return {
      result: "accepted",
      settled: true,
      invoiceId: invoice.id,
      tenantId: token.tenantId,
    };
  }

  // ===== (c) CANCEL =====

  /** Pesapal cancellation is not exposed through the configured API client. */
  async cancelCardSubscription(tenantId: string) {
    const token = await this.prisma.subscriptionCardToken.findUnique({
      where: { tenantId },
    });
    if (!token || token.status === "CANCELLED") {
      throw new NotFoundException("No active card subscription for this company");
    }
    throw new ConflictException(
      "This card authorization must be cancelled in your Pesapal account. Counterbase has not changed its status because that would not stop provider-side charges.",
    );
  }

  // ===== SAFETY NET (called from runRenewalCycle) =====

  /**
   * For tenants with a live card subscription whose invoice is still PENDING
   * more than 24h after period end: log a warning row so failures are
   * visible. We never charge here — Pesapal owns the charge schedule.
   */
  async reportStaleCardRenewals(now = new Date()) {
    const cutoff = new Date(now.getTime() - CARD_STALE_HOURS * 3_600_000);
    const stale = await this.prisma.subscriptionCardToken.findMany({
      where: {
        status: "ACTIVE",
        tenant: {
          currentPeriodEnd: { lte: cutoff },
          subscriptionStatus: { not: "ACTIVE" },
        },
      },
      include: {
        tenant: {
          select: {
            id: true,
            plan: true,
            subscriptionStatus: true,
            currentPeriodEnd: true,
          },
        },
      },
    });

    const warnings: {
      tenantId: string;
      reason: string;
    }[] = [];
    for (const token of stale) {
      const openInvoice = await this.prisma.subscriptionInvoice.findFirst({
        where: { tenantId: token.tenantId, status: "PENDING" },
        orderBy: { createdAt: "desc" },
      });
      if (!openInvoice) continue;
      const message = `Card auto-renew overdue: tenant ${token.tenantId} has a PENDING invoice ${openInvoice.id} >24h after period end — Pesapal has not charged. Check the Pesapal dashboard.`;
      this.logger.warn(message);
      warnings.push({ tenantId: token.tenantId, reason: message });
    }
    return { checked: stale.length, warnings };
  }
}
