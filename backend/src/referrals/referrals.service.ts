import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { LegacyUserRole } from '@prisma/client';
import { randomInt } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PromoService, normalisePlatformCode } from './promo.service';
import { extendSubscriptionDays } from './subscription-days';

// No 0/O/1/I: codes get read out over the phone and typed on small keyboards.
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Extra trial days the new company gets once it activates. */
export const DEFAULT_REFERRED_DAYS = 14;
/** Free subscription days the referrer earns when that company activates. */
export const DEFAULT_REFERRER_DAYS = 30;

/** How long after a company is created a referral code can still be entered. */
const REDEEM_WINDOW_DAYS = 30;

export function buildReferralCode(companyName: string, pick: (n: number) => number = randomInt): string {
  const letters = companyName.toUpperCase().replace(/[^A-Z0-9]/g, '').replace(/[01OI]/g, '').slice(0, 4);
  const prefix = letters.length >= 3 ? letters : 'SHOP';
  let suffix = '';
  for (let i = 0; i < 4; i++) suffix += ALPHABET[pick(ALPHABET.length)];
  return `${prefix}-${suffix}`;
}

@Injectable()
export class ReferralsService {
  private readonly logger = new Logger(ReferralsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
    private readonly promo: PromoService,
    private readonly config: ConfigService,
  ) {}

  private days(key: string, fallback: number): number {
    const raw = Number(this.config.get<string>(key));
    return Number.isInteger(raw) && raw >= 0 && raw <= 365 ? raw : fallback;
  }

  get referredDays(): number {
    return this.days('REFERRAL_REFERRED_DAYS', DEFAULT_REFERRED_DAYS);
  }

  get referrerDays(): number {
    return this.days('REFERRAL_REFERRER_DAYS', DEFAULT_REFERRER_DAYS);
  }

  /** The company's own code; made on first ask. */
  async getOrCreateCode(tenantId: string): Promise<string> {
    const existing = await this.prisma.referralCode.findUnique({ where: { tenantId } });
    if (existing) return existing.code;

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { name: true },
    });
    if (!tenant) throw new BadRequestException('Company not found');

    for (let attempt = 0; attempt < 10; attempt++) {
      const code = buildReferralCode(tenant.name);
      try {
        const created = await this.prisma.referralCode.create({ data: { tenantId, code } });
        return created.code;
      } catch (error: any) {
        if (error?.code !== 'P2002') throw error;
        // Either the code is taken (try again) or another request just made
        // this company's code (use it).
        const raced = await this.prisma.referralCode.findUnique({ where: { tenantId } });
        if (raced) return raced.code;
      }
    }
    throw new BadRequestException('Could not make a referral code. Try again.');
  }

  async summary(tenantId: string) {
    const code = await this.getOrCreateCode(tenantId);
    const referrals = await this.prisma.referral.findMany({
      where: { referrerTenantId: tenantId },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    const names = await this.prisma.tenant.findMany({
      where: { id: { in: referrals.map((r) => r.referredTenantId) } },
      select: { id: true, name: true },
    });
    const nameOf = new Map(names.map((t) => [t.id, t.name]));
    const rewarded = referrals.filter((r) => r.status === 'REWARDED');
    const appUrl = this.config.get<string>('APP_DOWNLOAD_URL')?.trim();

    return {
      code,
      referredDays: this.referredDays,
      referrerDays: this.referrerDays,
      shareText:
        `Run your shop properly with Counterbase: stock, credit, cash and who did what, all on your phone. ` +
        `Use my code ${code} when you sign up and get ${this.referredDays} extra free days.` +
        (appUrl ? ` ${appUrl}` : ''),
      pending: referrals.filter((r) => r.status === 'PENDING').length,
      rewarded: rewarded.length,
      daysEarned: rewarded.reduce((sum, r) => sum + (r.referrerDays ?? 0), 0),
      referrals: referrals.map((r) => ({
        id: r.id,
        name: nameOf.get(r.referredTenantId) ?? 'A new shop',
        status: r.status,
        daysEarned: r.referrerDays ?? 0,
        createdAt: r.createdAt,
        rewardedAt: r.rewardedAt,
      })),
    };
  }

  /**
   * One box for any code. Promo codes are tried first (they are the platform's
   * own), then referral codes from other shops.
   */
  async redeemCode(tenantId: string, userId: string, rawCode: string) {
    const code = normalisePlatformCode(rawCode ?? '');
    if (code.length < 3) throw new BadRequestException('Enter the code you were given.');

    if (await this.promo.find(code)) return this.promo.redeem(tenantId, userId, code);
    return this.redeemReferral(tenantId, userId, code);
  }

  private async redeemReferral(tenantId: string, userId: string, code: string) {
    const owner = await this.prisma.referralCode.findUnique({ where: { code } });
    if (!owner) throw new BadRequestException('We do not recognise that code.');
    if (owner.tenantId === tenantId) throw new BadRequestException('You cannot use your own code.');

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { createdAt: true, activationStatus: true, activationPaidAt: true },
    });
    if (!tenant) throw new BadRequestException('Company not found');
    if (tenant.activationStatus === 'ACTIVE' || tenant.activationPaidAt) {
      throw new BadRequestException('Referral codes can only be used before your company is activated.');
    }
    const ageDays = (Date.now() - tenant.createdAt.getTime()) / 86_400_000;
    if (ageDays > REDEEM_WINDOW_DAYS) {
      throw new BadRequestException('This company is too old to use a referral code.');
    }

    // A company can only ever have one referrer. Never reward a referral loop:
    // if the referrer was itself referred by this company, refuse.
    const loop = await this.prisma.referral.findFirst({
      where: { referrerTenantId: tenantId, referredTenantId: owner.tenantId },
      select: { id: true },
    });
    if (loop) throw new BadRequestException('That shop already joined through you.');

    try {
      await this.prisma.referral.create({
        data: { referrerTenantId: owner.tenantId, referredTenantId: tenantId, code },
      });
    } catch (error: any) {
      if (error?.code === 'P2002') {
        throw new BadRequestException('Your company has already used a referral code.');
      }
      throw error;
    }

    await this.audit.record({
      userId,
      action: 'REFERRAL_REDEEMED',
      entityType: 'Tenant',
      entityId: tenantId,
      newValues: { code, referrerTenantId: owner.tenantId },
    });

    return {
      type: 'REFERRAL' as const,
      days: this.referredDays,
      applied: false,
      periodEnd: null,
      message: `Code accepted. You will get ${this.referredDays} extra free days when your company is activated.`,
    };
  }

  /**
   * Called when a company pays its activation. Lands waiting promo days and
   * pays out a referral exactly once. Never throws: activation must not fail
   * because of a bonus.
   */
  async onActivated(tenantId: string): Promise<void> {
    try {
      await this.promo.applyPending(tenantId);

      const claimed = await this.prisma.referral.updateMany({
        where: { referredTenantId: tenantId, status: 'PENDING' },
        data: {
          status: 'REWARDED',
          rewardedAt: new Date(),
          referredDays: this.referredDays,
          referrerDays: this.referrerDays,
        },
      });
      if (claimed.count === 0) return;

      const referral = await this.prisma.referral.findUnique({ where: { referredTenantId: tenantId } });
      if (!referral) return;

      if (this.referredDays > 0) await extendSubscriptionDays(this.prisma, tenantId, this.referredDays);
      if (this.referrerDays > 0) {
        await extendSubscriptionDays(this.prisma, referral.referrerTenantId, this.referrerDays);
      }

      const newShop = await this.prisma.tenant.findUnique({
        where: { id: tenantId },
        select: { name: true },
      });
      await this.audit.record({
        userId: null,
        action: 'REFERRAL_REWARDED',
        entityType: 'Referral',
        entityId: referral.id,
        newValues: {
          referrerTenantId: referral.referrerTenantId,
          referredTenantId: tenantId,
          referrerDays: this.referrerDays,
          referredDays: this.referredDays,
        },
      });
      await this.notifications.sendToTenantRoles(referral.referrerTenantId, [LegacyUserRole.ADMIN], {
        title: 'You earned free days',
        body: `${newShop?.name ?? 'A shop you referred'} joined Counterbase. ${this.referrerDays} free days were added to your subscription.`,
        data: { type: 'referral_reward' },
      });
    } catch (error) {
      this.logger.error(`Referral payout failed for ${tenantId}: ${error}`);
    }
  }
}
