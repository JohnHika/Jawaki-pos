import { Injectable, Logger, HttpException, HttpStatus } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AiSubscriptionStatus, AiPaymentStatus } from '@prisma/client';

@Injectable()
export class AiBillingService {
  private readonly logger = new Logger(AiBillingService.name);
  private readonly TRIAL_DAYS = 7;
  private readonly SUBSCRIPTION_DAYS = 30;
  private readonly RECIPIENT_PHONE = '0742126582';

  constructor(private prisma: PrismaService) {}

  /** Start or check free trial for a branch */
  async startTrial(branchId: string) {
    const existing = await this.prisma.aiSubscription.findUnique({
      where: { branchId },
    });

    if (existing) {
      return this.formatSubscription(existing);
    }

    const now = new Date();
    const trialEnds = new Date(now);
    trialEnds.setDate(trialEnds.getDate() + this.TRIAL_DAYS);

    const sub = await this.prisma.aiSubscription.create({
      data: {
        branchId,
        status: 'TRIAL',
        trialStartedAt: now,
        trialEndsAt: trialEnds,
        price: 600.00,
      },
    });

    this.logger.log(`Trial started for branch ${branchId}, ends ${trialEnds.toISOString()}`);
    return this.formatSubscription(sub);
  }

  /** Get current subscription status */
  async getStatus(branchId: string) {
    const sub = await this.prisma.aiSubscription.findUnique({
      where: { branchId },
      include: { payments: { orderBy: { createdAt: 'desc' }, take: 5 } },
    });

    if (!sub) {
      return { hasSubscription: false, status: null, message: 'No subscription found. Start your free trial!' };
    }

    // Check if trial or subscription expired
    const now = new Date();
    if (sub.status === 'TRIAL' && sub.trialEndsAt < now) {
      await this.prisma.aiSubscription.update({
        where: { id: sub.id },
        data: { status: 'EXPIRED' },
      });
      sub.status = 'EXPIRED';
    }
    if (sub.status === 'ACTIVE' && sub.expiresAt && sub.expiresAt < now) {
      await this.prisma.aiSubscription.update({
        where: { id: sub.id },
        data: { status: 'EXPIRED' },
      });
      sub.status = 'EXPIRED';
    }

    return this.formatSubscription(sub);
  }

  /** Check if a branch can use AI */
  async canUseAi(branchId: string): Promise<boolean> {
    const sub = await this.prisma.aiSubscription.findUnique({ where: { branchId } });
    if (!sub) return false;

    const now = new Date();
    if (sub.status === 'TRIAL' && sub.trialEndsAt > now) return true;
    if (sub.status === 'ACTIVE' && sub.expiresAt && sub.expiresAt > now) return true;
    return false;
  }

  /** Submit M-Pesa code for verification */
  async submitPayment(branchId: string, mpesaCode: string, senderPhone?: string, smsRaw?: string) {
    // Get or create subscription
    let sub = await this.prisma.aiSubscription.findUnique({ where: { branchId } });
    if (!sub) {
      // Create trial first
      const result = await this.startTrial(branchId);
      sub = await this.prisma.aiSubscription.findUnique({ where: { branchId } });
    }

    // Check for duplicate code
    const existing = await this.prisma.aiPayment.findUnique({ where: { mpesaCode } });
    if (existing) {
      throw new HttpException('This M-Pesa code has already been used', HttpStatus.CONFLICT);
    }

    // Validate code format (M-Pesa codes are typically 10 chars, alphanumeric)
    if (mpesaCode.length < 5 || mpesaCode.length > 20) {
      throw new HttpException('Invalid M-Pesa confirmation code format', HttpStatus.BAD_REQUEST);
    }

    const payment = await this.prisma.aiPayment.create({
      data: {
        subscriptionId: sub.id,
        mpesaCode: mpesaCode.toUpperCase(),
        amount: 600.00,
        senderPhone: senderPhone || null,
        recipientPhone: this.RECIPIENT_PHONE,
        smsRaw: smsRaw || null,
        status: 'PENDING',
        verified: false,
      },
    });

    this.logger.log(`Payment submitted: ${mpesaCode} from branch ${branchId}`);
    return {
      success: true,
      message: 'Payment submitted for verification. It will be processed shortly.',
      paymentId: payment.id,
      mpesaCode: payment.mpesaCode,
    };
  }

  /** Auto-verify from SMS content (parsed by mobile app) */
  async verifyFromSms(branchId: string, mpesaCode: string, amount: string, recipient: string) {
    // Validate amount
    const parsedAmount = parseFloat(amount.replace(/[^0-9.]/g, ''));
    if (parsedAmount < 590 || parsedAmount > 610) {
      this.logger.warn(`SMS verification failed: amount ${parsedAmount} not ~600`);
      return { verified: false, reason: 'Amount does not match 600 KES' };
    }

    // Validate recipient (your number)
    const cleanRecipient = recipient.replace(/[^0-9]/g, '');
    const cleanYourNumber = this.RECIPIENT_PHONE.replace(/[^0-9]/g, '');
    if (!cleanRecipient.includes(cleanYourNumber) && !cleanYourNumber.includes(cleanRecipient)) {
      this.logger.warn(`SMS verification failed: recipient ${cleanRecipient} != ${cleanYourNumber}`);
      return { verified: false, reason: 'Recipient number does not match' };
    }

    // Get or create subscription
    let sub = await this.prisma.aiSubscription.findUnique({ where: { branchId } });
    if (!sub) {
      const result = await this.startTrial(branchId);
      sub = await this.prisma.aiSubscription.findUnique({ where: { branchId } });
    }

    // Check for duplicate code
    const existing = await this.prisma.aiPayment.findUnique({
      where: { mpesaCode: mpesaCode.toUpperCase() },
    });
    if (existing) {
      return { verified: false, reason: 'Code already used' };
    }

    // Auto-verify and create payment
    const payment = await this.prisma.aiPayment.create({
      data: {
        subscriptionId: sub.id,
        mpesaCode: mpesaCode.toUpperCase(),
        amount: parsedAmount,
        recipientPhone: this.RECIPIENT_PHONE,
        status: 'VERIFIED',
        verified: true,
        verifiedAt: new Date(),
        verifiedBy: 'auto_sms',
      },
    });

    // Activate subscription
    const now = new Date();
    const expiresAt = new Date(now);
    expiresAt.setDate(expiresAt.getDate() + this.SUBSCRIPTION_DAYS);

    await this.prisma.aiSubscription.update({
      where: { id: sub.id },
      data: {
        status: 'ACTIVE',
        subscribedAt: now,
        expiresAt,
        mpesaPhone: null,
      },
    });

    this.logger.log(`Auto-verified payment ${mpesaCode}, branch ${branchId} active until ${expiresAt.toISOString()}`);
    return {
      verified: true,
      expiresAt: expiresAt.toISOString(),
      message: `Subscription active! Expires ${expiresAt.toLocaleDateString()}`,
    };
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
      orderBy: { name: 'asc' },
    });
  }

  /** Get branches for a POS client */
  async getClientBranches(slug: string) {
    const client = await this.prisma.posClient.findUnique({
      where: { slug },
      include: {
        branches: {
          orderBy: { name: 'asc' },
          include: {
            aiSubscription: true,
          },
        },
      },
    });

    if (!client) {
      throw new HttpException('POS client not found', HttpStatus.NOT_FOUND);
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
        aiSubscription: b.aiSubscription ? this.formatSubscription(b.aiSubscription) : null,
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
        payments: { take: 5, orderBy: { createdAt: 'desc' } },
      },
      orderBy: { createdAt: 'desc' },
    });

    return subscriptions.map((sub: any) => this.formatSubscription(sub));
  }

  /** Get pending payments (admin approval queue) */
  async getPendingPayments(clientSlug?: string) {
    const where: any = { status: 'PENDING' };
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
      orderBy: { createdAt: 'asc' },
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
  async handlePayment(paymentId: string, action: 'approve' | 'reject', notes?: string) {
    const payment = await this.prisma.aiPayment.findUnique({
      where: { id: paymentId },
      include: { subscription: { include: { branch: true } } },
    });

    if (!payment) {
      throw new HttpException('Payment not found', HttpStatus.NOT_FOUND);
    }

    if (payment.status !== 'PENDING') {
      throw new HttpException('Payment already processed', HttpStatus.BAD_REQUEST);
    }

    if (action === 'approve') {
      // Mark payment as verified and activate subscription
      await this.prisma.aiPayment.update({
        where: { id: paymentId },
        data: {
          status: 'VERIFIED',
          verified: true,
          verifiedAt: new Date(),
          verifiedBy: 'admin_manual',
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
            status: 'ACTIVE',
            subscribedAt: now,
            expiresAt,
          },
        });
      }

      this.logger.log(`Admin approved payment ${payment.mpesaCode}`);
      return { success: true, message: 'Payment approved' };
    } else {
      // Reject
      await this.prisma.aiPayment.update({
        where: { id: paymentId },
        data: {
          status: 'REJECTED',
          verified: false,
          verifiedBy: 'admin_manual',
          adminNotes: notes || null,
        },
      });

      this.logger.log(`Admin rejected payment ${payment.mpesaCode}`);
      return { success: true, message: 'Payment rejected' };
    }
  }

  /** Revenue summary */
  async getRevenueSummary(clientSlug?: string) {
    const where: any = { status: 'VERIFIED' };
    if (clientSlug) {
      where.subscription = { branch: { posClient: { slug: clientSlug } } };
    }

    const payments = await this.prisma.aiPayment.findMany({
      where,
      select: { amount: true, createdAt: true, subscriptionId: true },
    });

    const total = payments.reduce((sum, p) => sum + Number(p.amount), 0);
    const thisMonth = payments.filter(p => {
      const d = new Date(p.createdAt);
      const now = new Date();
      return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear();
    });
    const monthlyTotal = thisMonth.reduce((sum, p) => sum + Number(p.amount), 0);

    const activeSubs = await this.prisma.aiSubscription.count({
      where: {
        status: 'ACTIVE',
        expiresAt: { gt: new Date() },
        ...(clientSlug ? { branch: { posClient: { slug: clientSlug } } } : {}),
      },
    });

    const trialSubs = await this.prisma.aiSubscription.count({
      where: {
        status: 'TRIAL',
        trialEndsAt: { gt: new Date() },
        ...(clientSlug ? { branch: { posClient: { slug: clientSlug } } } : {}),
      },
    });

    return {
      totalRevenue: total,
      monthlyRevenue: monthlyTotal,
      totalPayments: payments.length,
      activeSubscriptions: activeSubs,
      trialSubscriptions: trialSubs,
    };
  }

  // ===== HELPERS =====

  private formatSubscription(sub: any) {
    const now = new Date();
    let daysLeft = 0;
    let statusLabel = sub.status;

    if (sub.status === 'TRIAL') {
      daysLeft = Math.max(0, Math.ceil((sub.trialEndsAt.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)));
      statusLabel = 'TRIAL';
    } else if (sub.status === 'ACTIVE' && sub.expiresAt) {
      daysLeft = Math.max(0, Math.ceil((sub.expiresAt.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)));
      statusLabel = 'ACTIVE';
    } else {
      statusLabel = 'EXPIRED';
    }

    return {
      id: sub.id,
      branchId: sub.branchId,
      branchName: sub.branch?.name,
      branchCode: sub.branch?.code,
      posClient: sub.branch?.posClient?.name,
      status: statusLabel,
      daysLeft,
      trialEndsAt: sub.trialEndsAt?.toISOString(),
      expiresAt: sub.expiresAt?.toISOString(),
      subscribedAt: sub.subscribedAt?.toISOString(),
      price: Number(sub.price),
      payments: sub.payments?.map((p: any) => ({
        id: p.id,
        mpesaCode: p.mpesaCode,
        amount: Number(p.amount),
        status: p.status,
        verifiedAt: p.verifiedAt?.toISOString(),
        createdAt: p.createdAt?.toISOString(),
      })) || [],
    };
  }
}
