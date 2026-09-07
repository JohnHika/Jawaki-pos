import {
  BadRequestException,
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
    if (existing && existing.status !== "CANCELLED") {
      if (existing.status === "ACTIVE" && existing.plan === planId && existing.billingCycle === billingCycle) {
        return {
          alreadyActive: true,
          subscriptionId: existing.id,
          message: "A card subscription for this plan is already active.",
        };
      }
      const ageHours = (Date.now() - new Date(existing.createdAt).getTime()) / 3_600_000;
      if (existing.status === "PENDING" && ageHours < CARD_SUBSCRIPTION_PENDING_HOURS) {
        return {
          alreadyPending: true,
          subscriptionId: existing.id,
          message: "A card subscription setup is already awaiting the customer on the Pesapal page.",
        };
      }
    }

    const accountNumber = buildAccountNumber(tenantId, now);
    const startDate = now;
    const endDate = addCycle(now, "YEARLY"); // Pesapal contract: end = start + 1 year

    const payload = this.pesapal.buildRecurringOrderRequest({
      accountNumber,
      amount: Number(amount),
      description: `Axon POS ${plan.name} plan — card auto-renew (${billingCycle.toLowerCase()})`,
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

    const token = await this.prisma.subscriptionCardToken.findUnique({
      where: { orderTrackingId },
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

    if (!token || token.status === "CANCELLED") {
      this.logger.warn(
        `Pesapal recurring IPN for unknown/cancelled tracking id ${orderTrackingId}`,
      );
      return { result: "ignored", reason: "unknown or cancelled subscription" };
    }

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

    // Cross-check the correlation id Pesapal returns for the subscription.
    const correlationId =
      status.subscriptionTransactionInfo?.correlationId || token.pesapalCorrelationId;
    if (
      status.subscriptionTransactionInfo &&
      status.subscriptionTransactionInfo.accountReference &&
      status.subscriptionTransactionInfo.accountReference !== merchantReference &&
      status.subscriptionTransactionInfo.accountReference !== token.pesapalCorrelationId
    ) {
      this.logger.warn(
        `Pesapal recurring IPN account_reference mismatch for ${orderTrackingId}: ${status.subscriptionTransactionInfo.accountReference}`,
      );
      return { result: "rejected", reason: "account_reference mismatch" };
    }

    const amount = status.amount ?? undefined;
    const invoice = await this.recurring.settleCardRenewal(
      token.tenantId,
      correlationId,
      amount,
    );

    if (!invoice) {
      return { result: "accepted", settled: false, reason: "no open invoice to settle" };
    }

    // First successful charge ⇒ the card subscription is live.
    if (token.status !== "ACTIVE") {
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

  /**
   * Pesapal 3.0 has no direct "cancel recurring subscription" API endpoint
   * exposed for merchants; deactivation on the Pesapal side happens via the
   * merchant dashboard. Cancellation here therefore = removing the token
   * mapping (mark CANCELLED), which stops us from ever settling future IPNs.
   * We keep the row (not delete) for audit.
   */
  async cancelCardSubscription(tenantId: string) {
    const token = await this.prisma.subscriptionCardToken.findUnique({
      where: { tenantId },
    });
    if (!token || token.status === "CANCELLED") {
      throw new NotFoundException("No active card subscription for this company");
    }
    const cancelled = await this.prisma.subscriptionCardToken.update({
      where: { id: token.id },
      data: { status: "CANCELLED", cancelledAt: new Date() },
    });
    this.logger.log(`Card subscription cancelled for tenant ${tenantId}`);
    return {
      subscriptionId: cancelled.id,
      status: cancelled.status,
      cancelledAt: cancelled.cancelledAt,
      note: "Pesapal will no longer auto-charge this card. Renewal falls back to manual/STK billing.",
    };
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