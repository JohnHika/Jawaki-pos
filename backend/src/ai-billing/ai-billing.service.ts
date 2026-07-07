import { Injectable, Logger, HttpException, HttpStatus } from "@nestjs/common";
import { randomUUID } from "crypto";
import { PrismaService } from "../common/prisma/prisma.service";
import { AiSubscriptionStatus, AiPaymentStatus } from "@prisma/client";
import { PaystackService } from "./paystack.service";

@Injectable()
export class AiBillingService {
  private readonly logger = new Logger(AiBillingService.name);
  private readonly SUBSCRIPTION_PRICE = 1500.0;
  private readonly SUBSCRIPTION_DAYS = 30;
  private readonly RECIPIENT_PHONE = "0742126582";
  // M-Pesa SMS amounts must match the subscription price within this margin,
  // since senders occasionally round to the nearest shilling in their SMS.
  private readonly AMOUNT_TOLERANCE = 10;
  // Stop auto-retrying a card renewal after this many consecutive failures
  // (expired card, insufficient funds, etc.) rather than hammering Paystack
  // and the customer's bank indefinitely.
  private readonly MAX_RENEWAL_FAILURES = 3;

  constructor(
    private prisma: PrismaService,
    private paystackService: PaystackService,
  ) {}

  /** Get or create the (unpaid) subscription record for a branch */
  private async getOrCreateSubscription(branchId: string) {
    const existing = await this.prisma.aiSubscription.findUnique({
      where: { branchId },
    });
    if (existing) return existing;

    return this.prisma.aiSubscription.create({
      data: {
        branchId,
        status: "UNPAID",
        price: this.SUBSCRIPTION_PRICE,
      },
    });
  }

  /** Get current subscription status */
  async getStatus(branchId: string) {
    if (this.isBillingDisabled()) {
      return this.freeAccessStatus(branchId);
    }

    const sub = await this.prisma.aiSubscription.findUnique({
      where: { branchId },
      include: { payments: { orderBy: { createdAt: "desc" }, take: 5 } },
    });

    if (!sub) {
      return {
        hasSubscription: false,
        status: null,
        message: `Subscribe for KES ${this.SUBSCRIPTION_PRICE.toFixed(0)}/month to use the AI assistant.`,
      };
    }

    // Check if subscription expired
    const now = new Date();
    if (sub.status === "ACTIVE" && sub.expiresAt && sub.expiresAt < now) {
      await this.prisma.aiSubscription.update({
        where: { id: sub.id },
        data: { status: "EXPIRED" },
      });
      sub.status = "EXPIRED";
    }

    return this.formatSubscription(sub);
  }

  /** Check if a branch can use AI */
  async canUseAi(branchId: string): Promise<boolean> {
    if (this.isBillingDisabled()) {
      return true;
    }

    const sub = await this.prisma.aiSubscription.findUnique({
      where: { branchId },
    });
    if (!sub) return false;

    const now = new Date();
    return (
      sub.status === "ACTIVE" && !!sub.expiresAt && sub.expiresAt > now
    );
  }

  /** Submit M-Pesa code for verification */
  async submitPayment(
    branchId: string,
    mpesaCode: string,
    senderPhone?: string,
    smsRaw?: string,
  ) {
    const sub = await this.getOrCreateSubscription(branchId);

    // Check for duplicate code
    const existing = await this.prisma.aiPayment.findUnique({
      where: { mpesaCode },
    });
    if (existing) {
      throw new HttpException(
        "This M-Pesa code has already been used",
        HttpStatus.CONFLICT,
      );
    }

    // Validate code format (M-Pesa codes are typically 10 chars, alphanumeric)
    if (mpesaCode.length < 5 || mpesaCode.length > 20) {
      throw new HttpException(
        "Invalid M-Pesa confirmation code format",
        HttpStatus.BAD_REQUEST,
      );
    }

    const payment = await this.prisma.aiPayment.create({
      data: {
        subscriptionId: sub.id,
        mpesaCode: mpesaCode.toUpperCase(),
        amount: this.SUBSCRIPTION_PRICE,
        senderPhone: senderPhone || null,
        recipientPhone: this.RECIPIENT_PHONE,
        smsRaw: smsRaw || null,
        status: "PENDING",
        verified: false,
      },
    });

    this.logger.log(`Payment submitted: ${mpesaCode} from branch ${branchId}`);
    return {
      success: true,
      message:
        "Payment submitted for verification. It will be processed shortly.",
      paymentId: payment.id,
      mpesaCode: payment.mpesaCode,
    };
  }

  /** Auto-verify from SMS content (parsed by mobile app) */
  async verifyFromSms(
    branchId: string,
    mpesaCode: string,
    amount: string,
    recipient: string,
  ) {
    // Validate amount
    const parsedAmount = parseFloat(amount.replace(/[^0-9.]/g, ""));
    const minAmount = this.SUBSCRIPTION_PRICE - this.AMOUNT_TOLERANCE;
    const maxAmount = this.SUBSCRIPTION_PRICE + this.AMOUNT_TOLERANCE;
    if (parsedAmount < minAmount || parsedAmount > maxAmount) {
      this.logger.warn(
        `SMS verification failed: amount ${parsedAmount} not ~${this.SUBSCRIPTION_PRICE}`,
      );
      return {
        verified: false,
        reason: `Amount does not match KES ${this.SUBSCRIPTION_PRICE.toFixed(0)}`,
      };
    }

    // Validate recipient (your number)
    const cleanRecipient = recipient.replace(/[^0-9]/g, "");
    const cleanYourNumber = this.RECIPIENT_PHONE.replace(/[^0-9]/g, "");
    if (
      !cleanRecipient.includes(cleanYourNumber) &&
      !cleanYourNumber.includes(cleanRecipient)
    ) {
      this.logger.warn(
        `SMS verification failed: recipient ${cleanRecipient} != ${cleanYourNumber}`,
      );
      return { verified: false, reason: "Recipient number does not match" };
    }

    const sub = await this.getOrCreateSubscription(branchId);

    // Check for duplicate code
    const existing = await this.prisma.aiPayment.findUnique({
      where: { mpesaCode: mpesaCode.toUpperCase() },
    });
    if (existing) {
      return { verified: false, reason: "Code already used" };
    }

    // Auto-verify and create payment
    const payment = await this.prisma.aiPayment.create({
      data: {
        subscriptionId: sub.id,
        mpesaCode: mpesaCode.toUpperCase(),
        amount: parsedAmount,
        recipientPhone: this.RECIPIENT_PHONE,
        status: "VERIFIED",
        verified: true,
        verifiedAt: new Date(),
        verifiedBy: "auto_sms",
      },
    });

    // Activate subscription
    const now = new Date();
    const expiresAt = new Date(now);
    expiresAt.setDate(expiresAt.getDate() + this.SUBSCRIPTION_DAYS);

    await this.prisma.aiSubscription.update({
      where: { id: sub.id },
      data: {
        status: "ACTIVE",
        subscribedAt: now,
        expiresAt,
        mpesaPhone: null,
      },
    });

    this.logger.log(
      `Auto-verified payment ${mpesaCode}, branch ${branchId} active until ${expiresAt.toISOString()}`,
    );
    return {
      verified: true,
      expiresAt: expiresAt.toISOString(),
      message: `Subscription active! Expires ${expiresAt.toLocaleDateString()}`,
    };
  }

  // ===== PAYSTACK (card, auto-renewing) =====

  /** Start a Paystack checkout for a fresh card-based subscription. */
  async initializePaystackPayment(branchId: string, email: string) {
    const sub = await this.getOrCreateSubscription(branchId);
    const reference = `axon-ai-${branchId}-${randomUUID()}`;

    const { authorizationUrl, accessCode } =
      await this.paystackService.initializeTransaction({
        email,
        amountKes: this.SUBSCRIPTION_PRICE,
        reference,
        metadata: { branchId, subscriptionId: sub.id, isRenewal: false },
      });

    await this.prisma.aiPayment.create({
      data: {
        subscriptionId: sub.id,
        method: "PAYSTACK_CARD",
        paystackReference: reference,
        amount: this.SUBSCRIPTION_PRICE,
        status: "PENDING",
        verified: false,
      },
    });

    return { authorizationUrl, accessCode, reference };
  }

  /**
   * Handle a Paystack webhook event. Called only after the caller has
   * verified the `x-paystack-signature` header — this method trusts its
   * input.
   */
  async handlePaystackWebhook(event: string, data: any) {
    if (event !== "charge.success") {
      this.logger.log(`Ignoring Paystack event: ${event}`);
      return { handled: false };
    }

    const reference: string = data.reference;
    const payment = await this.prisma.aiPayment.findUnique({
      where: { paystackReference: reference },
      include: { subscription: true },
    });

    if (!payment) {
      this.logger.warn(`Paystack webhook for unknown reference: ${reference}`);
      return { handled: false };
    }

    if (payment.status === "VERIFIED") {
      // Already processed (Paystack retries webhooks) — no-op.
      return { handled: true, alreadyProcessed: true };
    }

    await this.activateFromPaystackCharge(payment.subscriptionId, payment.id, data);
    return { handled: true };
  }

  /** Shared activation logic for both the initial webhook and renewal charges. */
  private async activateFromPaystackCharge(
    subscriptionId: string,
    paymentId: string,
    chargeData: any,
  ) {
    const authorizationCode: string | undefined =
      chargeData.authorization?.authorization_code;
    const customerCode: string | undefined = chargeData.customer?.customer_code;
    const customerEmail: string | undefined = chargeData.customer?.email;

    await this.prisma.aiPayment.update({
      where: { id: paymentId },
      data: {
        status: "VERIFIED",
        verified: true,
        verifiedAt: new Date(),
        verifiedBy: "paystack_webhook",
      },
    });

    const now = new Date();
    const expiresAt = new Date(now);
    expiresAt.setDate(expiresAt.getDate() + this.SUBSCRIPTION_DAYS);

    await this.prisma.aiSubscription.update({
      where: { id: subscriptionId },
      data: {
        status: "ACTIVE",
        subscribedAt: now,
        expiresAt,
        autoRenew: true,
        renewalFailureCount: 0,
        lastRenewalAttemptAt: now,
        ...(authorizationCode ? { paystackAuthorizationCode: authorizationCode } : {}),
        ...(customerCode ? { paystackCustomerCode: customerCode } : {}),
        ...(customerEmail ? { paystackCustomerEmail: customerEmail } : {}),
      },
    });

    this.logger.log(
      `Subscription ${subscriptionId} active until ${expiresAt.toISOString()} (Paystack)`,
    );
  }

  /**
   * Daily cron target: find subscriptions expiring within the next day
   * that have auto-renew enabled and a saved card, and charge them again
   * with no customer action needed — the actual "auto subscribe" behavior.
   */
  async renewExpiringSubscriptions() {
    if (this.isBillingDisabled()) return;

    const renewalWindow = new Date();
    renewalWindow.setDate(renewalWindow.getDate() + 1);

    const dueForRenewal = await this.prisma.aiSubscription.findMany({
      where: {
        status: "ACTIVE",
        autoRenew: true,
        expiresAt: { lte: renewalWindow },
        paystackAuthorizationCode: { not: null },
        renewalFailureCount: { lt: this.MAX_RENEWAL_FAILURES },
      },
    });

    this.logger.log(`Renewal check: ${dueForRenewal.length} subscription(s) due`);

    for (const sub of dueForRenewal) {
      await this.attemptRenewal(sub);
    }
  }

  private async attemptRenewal(sub: {
    id: string;
    branchId: string;
    paystackAuthorizationCode: string | null;
    paystackCustomerEmail: string | null;
    renewalFailureCount: number;
  }) {
    if (!sub.paystackAuthorizationCode || !sub.paystackCustomerEmail) return;

    const reference = `axon-ai-renewal-${sub.branchId}-${randomUUID()}`;
    const payment = await this.prisma.aiPayment.create({
      data: {
        subscriptionId: sub.id,
        method: "PAYSTACK_CARD",
        paystackReference: reference,
        amount: this.SUBSCRIPTION_PRICE,
        status: "PENDING",
        verified: false,
        isRenewal: true,
      },
    });

    try {
      const chargeResult = await this.paystackService.chargeAuthorization({
        email: sub.paystackCustomerEmail,
        authorizationCode: sub.paystackAuthorizationCode,
        amountKes: this.SUBSCRIPTION_PRICE,
        reference,
        metadata: { branchId: sub.branchId, subscriptionId: sub.id, isRenewal: true },
      });

      if (chargeResult.status === "success") {
        await this.activateFromPaystackCharge(sub.id, payment.id, chargeResult);
        this.logger.log(`Auto-renewed subscription for branch ${sub.branchId}`);
      } else {
        await this.recordRenewalFailure(sub.id, payment.id, chargeResult.status);
      }
    } catch (error: any) {
      await this.recordRenewalFailure(sub.id, payment.id, error?.message || "unknown error");
    }
  }

  private async recordRenewalFailure(
    subscriptionId: string,
    paymentId: string,
    reason: string,
  ) {
    this.logger.warn(`Renewal charge failed for subscription ${subscriptionId}: ${reason}`);

    await this.prisma.aiPayment.update({
      where: { id: paymentId },
      data: {
        status: "REJECTED",
        adminNotes: `Auto-renewal failed: ${reason}`,
      },
    });

    const sub = await this.prisma.aiSubscription.update({
      where: { id: subscriptionId },
      data: {
        lastRenewalAttemptAt: new Date(),
        renewalFailureCount: { increment: 1 },
      },
    });

    if (sub.renewalFailureCount >= this.MAX_RENEWAL_FAILURES) {
      this.logger.warn(
        `Subscription ${subscriptionId} disabled auto-renew after ${sub.renewalFailureCount} failed attempts`,
      );
      await this.prisma.aiSubscription.update({
        where: { id: subscriptionId },
        data: { autoRenew: false },
      });
    }
  }

  // ===== ADMIN METHODS =====

  /** Get POS clients (Levisa, TSL, Kate, etc.) */
  async listPosClients() {
    return this.prisma.posClient.findMany({
      where: { isActive: true },
      include: {
        branches: {
          select: {
            id: true,
            name: true,
            code: true,
          },
        },
      },
      orderBy: { name: "asc" },
    });
  }

  /** Get branches for a POS client */
  async getClientBranches(slug: string) {
    const client = await this.prisma.posClient.findUnique({
      where: { slug },
      include: {
        branches: {
          orderBy: { name: "asc" },
          include: {
            aiSubscription: true,
          },
        },
      },
    });

    if (!client) {
      throw new HttpException("POS client not found", HttpStatus.NOT_FOUND);
    }

    return {
      client: {
        id: client.id,
        name: client.name,
        slug: client.slug,
      },
      branches: client.branches.map((b: any) => ({
        id: b.id,
        name: b.name,
        code: b.code,
        aiSubscription: b.aiSubscription
          ? this.formatSubscription(b.aiSubscription)
          : null,
      })),
    };
  }

  /** List all subscriptions (admin view) */
  async listAllSubscriptions(clientSlug?: string) {
    const where: any = {};
    if (clientSlug) {
      where.branch = { posClient: { slug: clientSlug } };
    }

    const subscriptions = await this.prisma.aiSubscription.findMany({
      where,
      include: {
        branch: {
          include: {
            posClient: true,
          },
        },
        payments: { take: 5, orderBy: { createdAt: "desc" } },
      },
      orderBy: { createdAt: "desc" },
    });

    return subscriptions.map((sub: any) => this.formatSubscription(sub));
  }

  /** Get pending payments (admin approval queue) */
  async getPendingPayments(clientSlug?: string) {
    const where: any = { status: "PENDING" };
    if (clientSlug) {
      where.subscription = { branch: { posClient: { slug: clientSlug } } };
    }

    const payments = await this.prisma.aiPayment.findMany({
      where,
      include: {
        subscription: {
          include: {
            branch: {
              include: {
                posClient: true,
              },
            },
          },
        },
      },
      orderBy: { createdAt: "asc" },
    });

    return payments.map((p: any) => ({
      id: p.id,
      mpesaCode: p.mpesaCode,
      amount: Number(p.amount),
      senderPhone: p.senderPhone,
      branchName: p.subscription?.branch?.name,
      branchCode: p.subscription?.branch?.code,
      posClient: p.subscription?.branch?.posClient?.name,
      createdAt: p.createdAt.toISOString(),
    }));
  }

  /** Admin: approve or reject a payment */
  async handlePayment(
    paymentId: string,
    action: "approve" | "reject",
    notes?: string,
  ) {
    const payment = await this.prisma.aiPayment.findUnique({
      where: { id: paymentId },
      include: { subscription: { include: { branch: true } } },
    });

    if (!payment) {
      throw new HttpException("Payment not found", HttpStatus.NOT_FOUND);
    }

    if (payment.status !== "PENDING") {
      throw new HttpException(
        "Payment already processed",
        HttpStatus.BAD_REQUEST,
      );
    }

    if (action === "approve") {
      // Mark payment as verified and activate subscription
      await this.prisma.aiPayment.update({
        where: { id: paymentId },
        data: {
          status: "VERIFIED",
          verified: true,
          verifiedAt: new Date(),
          verifiedBy: "admin_manual",
          adminNotes: notes || null,
        },
      });

      // Update subscription to ACTIVE
      const sub = await this.prisma.aiSubscription.findUnique({
        where: { branchId: payment.subscription.branch.id },
      });
      if (sub) {
        const now = new Date();
        const expiresAt = new Date(now);
        expiresAt.setDate(expiresAt.getDate() + 30); // 30 days from now

        await this.prisma.aiSubscription.update({
          where: { id: sub.id },
          data: {
            status: "ACTIVE",
            subscribedAt: now,
            expiresAt,
          },
        });
      }

      this.logger.log(`Admin approved payment ${payment.mpesaCode}`);
      return { success: true, message: "Payment approved" };
    } else {
      // Reject
      await this.prisma.aiPayment.update({
        where: { id: paymentId },
        data: {
          status: "REJECTED",
          verified: false,
          verifiedBy: "admin_manual",
          adminNotes: notes || null,
        },
      });

      this.logger.log(`Admin rejected payment ${payment.mpesaCode}`);
      return { success: true, message: "Payment rejected" };
    }
  }

  /** Revenue summary */
  async getRevenueSummary(clientSlug?: string) {
    const where: any = { status: "VERIFIED" };
    if (clientSlug) {
      where.subscription = { branch: { posClient: { slug: clientSlug } } };
    }

    const payments = await this.prisma.aiPayment.findMany({
      where,
      select: { amount: true, createdAt: true, subscriptionId: true },
    });

    const total = payments.reduce((sum, p) => sum + Number(p.amount), 0);
    const thisMonth = payments.filter((p) => {
      const d = new Date(p.createdAt);
      const now = new Date();
      return (
        d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()
      );
    });
    const monthlyTotal = thisMonth.reduce(
      (sum, p) => sum + Number(p.amount),
      0,
    );

    const activeSubs = await this.prisma.aiSubscription.count({
      where: {
        status: "ACTIVE",
        expiresAt: { gt: new Date() },
        ...(clientSlug ? { branch: { posClient: { slug: clientSlug } } } : {}),
      },
    });

    const unpaidSubs = await this.prisma.aiSubscription.count({
      where: {
        status: "UNPAID",
        ...(clientSlug ? { branch: { posClient: { slug: clientSlug } } } : {}),
      },
    });

    return {
      totalRevenue: total,
      monthlyRevenue: monthlyTotal,
      totalPayments: payments.length,
      activeSubscriptions: activeSubs,
      unpaidSubscriptions: unpaidSubs,
    };
  }

  // ===== HELPERS =====

  private formatSubscription(sub: any) {
    const now = new Date();
    let daysLeft = 0;
    let statusLabel = sub.status;

    if (sub.status === "ACTIVE" && sub.expiresAt) {
      daysLeft = Math.max(
        0,
        Math.ceil(
          (sub.expiresAt.getTime() - now.getTime()) / (1000 * 60 * 60 * 24),
        ),
      );
      statusLabel = "ACTIVE";
    } else if (sub.status === "UNPAID") {
      statusLabel = "UNPAID";
    } else {
      statusLabel = "EXPIRED";
    }

    return {
      id: sub.id,
      branchId: sub.branchId,
      branchName: sub.branch?.name,
      branchCode: sub.branch?.code,
      posClient: sub.branch?.posClient?.name,
      status: statusLabel,
      daysLeft,
      expiresAt: sub.expiresAt?.toISOString(),
      subscribedAt: sub.subscribedAt?.toISOString(),
      price: Number(sub.price),
      autoRenew: sub.autoRenew,
      hasSavedCard: Boolean(sub.paystackAuthorizationCode),
      renewalFailureCount: sub.renewalFailureCount ?? 0,
      payments:
        sub.payments?.map((p: any) => ({
          id: p.id,
          method: p.method,
          mpesaCode: p.mpesaCode,
          amount: Number(p.amount),
          status: p.status,
          isRenewal: p.isRenewal,
          verifiedAt: p.verifiedAt?.toISOString(),
          createdAt: p.createdAt?.toISOString(),
        })) || [],
    };
  }

  private isBillingDisabled(): boolean {
    return process.env.AI_BILLING_DISABLED !== "false";
  }

  private freeAccessStatus(branchId: string) {
    return {
      id: "included",
      branchId,
      branchName: null,
      branchCode: null,
      posClient: null,
      hasSubscription: true,
      status: "ACTIVE",
      daysLeft: 3650,
      expiresAt: null,
      subscribedAt: null,
      price: 0,
      payments: [],
      message: "AI is included in this Axon POS release.",
    };
  }
}
