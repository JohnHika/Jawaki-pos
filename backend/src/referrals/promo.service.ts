import { BadRequestException, ConflictException, HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { extendSubscriptionDays } from './subscription-days';

export const normalisePlatformCode = (value: string): string =>
  value.trim().toUpperCase().replace(/\s+/g, '');

export interface CreatePromoInput {
  code: string;
  freeDays: number;
  description?: string;
  maxRedemptions?: number | null;
  expiresAt?: Date | null;
}

function notFound(message: string): HttpException {
  return new HttpException({ statusCode: 404, message, error: 'Not Found' }, HttpStatus.NOT_FOUND);
}

/**
 * Platform promo codes: Counterbase gives a company free subscription days.
 * Days only, never a price cut, so the billing code stays untouched.
 */
@Injectable()
export class PromoService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async create(input: CreatePromoInput) {
    const code = normalisePlatformCode(input.code);
    if (!/^[A-Z0-9_-]{3,24}$/.test(code)) {
      throw new BadRequestException('Code must be 3-24 letters, digits, - or _');
    }
    if (!Number.isInteger(input.freeDays) || input.freeDays < 1 || input.freeDays > 365) {
      throw new BadRequestException('Free days must be between 1 and 365');
    }
    try {
      return await this.prisma.promoCode.create({
        data: {
          code,
          freeDays: input.freeDays,
          description: input.description?.trim() || null,
          maxRedemptions: input.maxRedemptions ?? null,
          expiresAt: input.expiresAt ?? null,
        },
      });
    } catch (error: any) {
      if (error?.code === 'P2002') throw new ConflictException(`The code ${code} already exists`);
      throw error;
    }
  }

  list() {
    return this.prisma.promoCode.findMany({ orderBy: { createdAt: 'desc' }, take: 200 });
  }

  async setActive(id: string, isActive: boolean) {
    const existing = await this.prisma.promoCode.findUnique({ where: { id } });
    if (!existing) throw notFound('Promo code not found');
    return this.prisma.promoCode.update({ where: { id }, data: { isActive } });
  }

  /** Looks a code up; null when it is not a promo code at all. */
  find(code: string) {
    return this.prisma.promoCode.findUnique({ where: { code: normalisePlatformCode(code) } });
  }

  /**
   * Redeems a promo code for a company. The days land at once on an active
   * company; for one that has not paid its activation they wait, because
   * activation starts a fresh trial that would overwrite them.
   */
  async redeem(tenantId: string, userId: string, code: string) {
    const promo = await this.find(code);
    if (!promo) throw new BadRequestException('We do not recognise that code.');
    const now = new Date();
    if (!promo.isActive) throw new BadRequestException('This code is no longer available.');
    if (promo.expiresAt && promo.expiresAt < now) throw new BadRequestException('This code has expired.');
    if (promo.maxRedemptions != null && promo.redeemedCount >= promo.maxRedemptions) {
      throw new BadRequestException('This code has been fully used.');
    }

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { activationStatus: true },
    });
    if (!tenant) throw new BadRequestException('Company not found');
    const activated = tenant.activationStatus === 'ACTIVE';

    let periodEnd: Date | null = null;
    try {
      await this.prisma.$transaction(async (tx) => {
        const claimed = await tx.promoCode.updateMany({
          where: {
            id: promo.id,
            isActive: true,
            ...(promo.maxRedemptions != null ? { redeemedCount: { lt: promo.maxRedemptions } } : {}),
          },
          data: { redeemedCount: { increment: 1 } },
        });
        if (claimed.count === 0) throw new BadRequestException('This code has been fully used.');
        await tx.promoRedemption.create({
          data: {
            promoId: promo.id,
            tenantId,
            daysGranted: promo.freeDays,
            appliedAt: activated ? now : null,
          },
        });
        if (activated) periodEnd = await extendSubscriptionDays(tx, tenantId, promo.freeDays, now);
      });
    } catch (error: any) {
      if (error?.code === 'P2002') {
        throw new ConflictException('Your company has already used a promo code.');
      }
      throw error;
    }

    await this.audit.record({
      userId,
      action: 'PROMO_REDEEMED',
      entityType: 'Tenant',
      entityId: tenantId,
      newValues: { code: promo.code, days: promo.freeDays, applied: activated },
    });

    return {
      type: 'PROMO' as const,
      days: promo.freeDays,
      applied: activated,
      periodEnd,
      message: activated
        ? `${promo.freeDays} free days added to your subscription.`
        : `${promo.freeDays} free days will be added as soon as your company is activated.`,
    };
  }

  /** Called when a company activates: lands any promo days that were waiting. */
  async applyPending(tenantId: string): Promise<number> {
    const waiting = await this.prisma.promoRedemption.findFirst({
      where: { tenantId, appliedAt: null },
    });
    if (!waiting) return 0;
    const claimed = await this.prisma.promoRedemption.updateMany({
      where: { id: waiting.id, appliedAt: null },
      data: { appliedAt: new Date() },
    });
    if (claimed.count === 0) return 0;
    await extendSubscriptionDays(this.prisma, tenantId, waiting.daysGranted);
    return waiting.daysGranted;
  }
}
