import { BadRequestException, ConflictException } from '@nestjs/common';
import { ReferralsService, buildReferralCode } from './referrals.service';
import { PromoService } from './promo.service';

const DAY = 86_400_000;

function build(options: { tenants?: Record<string, any>; env?: Record<string, string> } = {}) {
  const tenants: Record<string, any> = {
    me: { id: 'me', name: 'Mama Njeri Traders', createdAt: new Date(Date.now() - 2 * DAY), activationStatus: 'PENDING', activationPaidAt: null, currentPeriodEnd: null },
    ref: { id: 'ref', name: 'Kamau Imports', createdAt: new Date(Date.now() - 90 * DAY), activationStatus: 'ACTIVE', activationPaidAt: new Date(), currentPeriodEnd: new Date(Date.now() + 10 * DAY) },
    ...(options.tenants ?? {}),
  };
  const state = {
    referralCodes: [{ tenantId: 'ref', code: 'KAMA-7H2Q' }] as any[],
    referrals: [] as any[],
    promos: [] as any[],
    redemptions: [] as any[],
  };

  const prisma: any = {
    tenant: {
      findUnique: jest.fn(async ({ where }: any) => tenants[where.id] ?? null),
      update: jest.fn(async ({ where, data }: any) => {
        Object.assign(tenants[where.id], data);
        return tenants[where.id];
      }),
      findMany: jest.fn(async () => Object.values(tenants)),
    },
    referralCode: {
      findUnique: jest.fn(async ({ where }: any) =>
        state.referralCodes.find((c) => (where.code ? c.code === where.code : c.tenantId === where.tenantId)) ?? null),
      create: jest.fn(async ({ data }: any) => {
        if (state.referralCodes.some((c) => c.code === data.code)) throw Object.assign(new Error('dup'), { code: 'P2002' });
        state.referralCodes.push(data);
        return data;
      }),
    },
    referral: {
      findFirst: jest.fn(async ({ where }: any) =>
        state.referrals.find((r) => r.referrerTenantId === where.referrerTenantId && r.referredTenantId === where.referredTenantId) ?? null),
      findMany: jest.fn(async ({ where }: any) => state.referrals.filter((r) => r.referrerTenantId === where.referrerTenantId)),
      findUnique: jest.fn(async ({ where }: any) => state.referrals.find((r) => r.referredTenantId === where.referredTenantId) ?? null),
      create: jest.fn(async ({ data }: any) => {
        if (state.referrals.some((r) => r.referredTenantId === data.referredTenantId)) {
          throw Object.assign(new Error('dup'), { code: 'P2002' });
        }
        const row = { id: `r${state.referrals.length + 1}`, status: 'PENDING', createdAt: new Date(), ...data };
        state.referrals.push(row);
        return row;
      }),
      updateMany: jest.fn(async ({ where, data }: any) => {
        const rows = state.referrals.filter((r) => r.referredTenantId === where.referredTenantId && r.status === where.status);
        rows.forEach((r) => Object.assign(r, data));
        return { count: rows.length };
      }),
    },
    promoCode: {
      findUnique: jest.fn(async ({ where }: any) => state.promos.find((p) => p.code === where.code) ?? null),
      updateMany: jest.fn(async ({ where }: any) => {
        const p = state.promos.find((x) => x.id === where.id);
        if (!p || !p.isActive) return { count: 0 };
        if (where.redeemedCount?.lt != null && p.redeemedCount >= where.redeemedCount.lt) return { count: 0 };
        p.redeemedCount += 1;
        return { count: 1 };
      }),
    },
    promoRedemption: {
      create: jest.fn(async ({ data }: any) => {
        if (state.redemptions.some((r) => r.tenantId === data.tenantId)) throw Object.assign(new Error('dup'), { code: 'P2002' });
        const row = { id: `x${state.redemptions.length + 1}`, ...data };
        state.redemptions.push(row);
        return row;
      }),
      findFirst: jest.fn(async ({ where }: any) =>
        state.redemptions.find((r) => r.tenantId === where.tenantId && r.appliedAt == null) ?? null),
      updateMany: jest.fn(async ({ where, data }: any) => {
        const r = state.redemptions.find((x) => x.id === where.id && x.appliedAt == null);
        if (!r) return { count: 0 };
        Object.assign(r, data);
        return { count: 1 };
      }),
    },
    $transaction: jest.fn(async (work: any) => work(prisma)),
  };

  const audit = { record: jest.fn() };
  const notifications = { sendToTenantRoles: jest.fn() };
  const config = { get: jest.fn((key: string) => options.env?.[key]) };
  const promo = new PromoService(prisma, audit as any);
  const service = new ReferralsService(prisma, audit as any, notifications as any, promo, config as any);
  return { service, promo, prisma, state, tenants, audit, notifications };
}

describe('buildReferralCode', () => {
  const first = (n: number) => 0 * n; // always the first letter of the alphabet

  it('uses the first letters of the shop name plus a four character suffix', () => {
    expect(buildReferralCode('Kamau Imports', first)).toBe('KAMA-AAAA');
  });

  it('falls back to SHOP for a very short or symbolic name', () => {
    expect(buildReferralCode('X1', first)).toBe('SHOP-AAAA');
    expect(buildReferralCode('@@', first)).toBe('SHOP-AAAA');
  });

  it('never produces look-alike characters', () => {
    for (let i = 0; i < 200; i++) {
      expect(buildReferralCode('Oliver 101 Shop')).not.toMatch(/[01OI](?=.*-)/);
    }
  });
});

describe('referral codes', () => {
  it('makes a company one stable code', async () => {
    const { service, state } = build();
    const a = await service.getOrCreateCode('me');
    const b = await service.getOrCreateCode('me');
    expect(a).toBe(b);
    expect(state.referralCodes.filter((c) => c.tenantId === 'me')).toHaveLength(1);
  });

  it('accepts another shop\'s code before activation, without paying anything yet', async () => {
    const { service, state, tenants } = build();
    const result = await service.redeemCode('me', 'user-1', 'kama-7h2q');
    expect(result).toMatchObject({ type: 'REFERRAL', applied: false, days: 14 });
    expect(state.referrals).toHaveLength(1);
    expect(state.referrals[0]).toMatchObject({ referrerTenantId: 'ref', referredTenantId: 'me', status: 'PENDING' });
    expect(tenants.me.currentPeriodEnd).toBeNull();
  });

  it('refuses a company\'s own code, an activated company, and a second referrer', async () => {
    const own = build();
    own.state.referralCodes.push({ tenantId: 'me', code: 'MAMA-2222' });
    await expect(own.service.redeemCode('me', 'u', 'MAMA-2222')).rejects.toThrow('own code');

    const active = build({ tenants: { me: { id: 'me', name: 'Old', createdAt: new Date(), activationStatus: 'ACTIVE', activationPaidAt: new Date() } } });
    await expect(active.service.redeemCode('me', 'u', 'KAMA-7H2Q')).rejects.toThrow('before your company is activated');

    const twice = build();
    await twice.service.redeemCode('me', 'u', 'KAMA-7H2Q');
    await expect(twice.service.redeemCode('me', 'u', 'KAMA-7H2Q')).rejects.toThrow('already used a referral code');
  });

  it('refuses a referral loop', async () => {
    const { service, state } = build();
    state.referralCodes.push({ tenantId: 'me', code: 'MAMA-2222' });
    state.referrals.push({ id: 'r0', referrerTenantId: 'me', referredTenantId: 'ref', status: 'PENDING' });
    await expect(service.redeemCode('me', 'u', 'KAMA-7H2Q')).rejects.toThrow('already joined through you');
  });

  it('refuses a company that is too old and an unknown code', async () => {
    const old = build({ tenants: { me: { id: 'me', name: 'Old', createdAt: new Date(Date.now() - 60 * DAY), activationStatus: 'PENDING', activationPaidAt: null } } });
    await expect(old.service.redeemCode('me', 'u', 'KAMA-7H2Q')).rejects.toThrow('too old');
    const { service } = build();
    await expect(service.redeemCode('me', 'u', 'NOPE-0000')).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('paying out on activation', () => {
  it('gives both shops their days exactly once', async () => {
    const { service, tenants, notifications, audit } = build();
    await service.redeemCode('me', 'u', 'KAMA-7H2Q');
    const refEndBefore = tenants.ref.currentPeriodEnd.getTime();
    // The activation payment sets a fresh 7-day trial first.
    tenants.me.currentPeriodEnd = new Date(Date.now() + 7 * DAY);
    const meBefore = tenants.me.currentPeriodEnd.getTime();

    await service.onActivated('me');
    await service.onActivated('me');

    expect(tenants.me.currentPeriodEnd.getTime() - meBefore).toBe(14 * DAY);
    expect(tenants.ref.currentPeriodEnd.getTime() - refEndBefore).toBe(30 * DAY);
    expect(notifications.sendToTenantRoles).toHaveBeenCalledTimes(1);
    expect(audit.record).toHaveBeenCalledWith(expect.objectContaining({ action: 'REFERRAL_REWARDED' }));
  });

  it('can be tuned from the environment', async () => {
    const { service, tenants } = build({ env: { REFERRER_DAYS_UNUSED: '1', REFERRAL_REFERRER_DAYS: '45', REFERRAL_REFERRED_DAYS: '3' } });
    await service.redeemCode('me', 'u', 'KAMA-7H2Q');
    tenants.me.currentPeriodEnd = new Date(Date.now() + 7 * DAY);
    const meBefore = tenants.me.currentPeriodEnd.getTime();
    const refBefore = tenants.ref.currentPeriodEnd.getTime();
    await service.onActivated('me');
    expect(tenants.me.currentPeriodEnd.getTime() - meBefore).toBe(3 * DAY);
    expect(tenants.ref.currentPeriodEnd.getTime() - refBefore).toBe(45 * DAY);
  });

  it('does nothing for a company nobody referred, and never throws', async () => {
    const { service, prisma, notifications } = build();
    await expect(service.onActivated('me')).resolves.toBeUndefined();
    expect(notifications.sendToTenantRoles).not.toHaveBeenCalled();

    prisma.referral.updateMany.mockRejectedValueOnce(new Error('db down'));
    await expect(service.onActivated('me')).resolves.toBeUndefined();
  });

  it('summarises what the referrer earned', async () => {
    const { service, tenants } = build();
    await service.redeemCode('me', 'u', 'KAMA-7H2Q');
    tenants.me.currentPeriodEnd = new Date(Date.now() + 7 * DAY);
    await service.onActivated('me');
    const summary = await service.summary('ref');
    expect(summary).toMatchObject({ code: 'KAMA-7H2Q', rewarded: 1, pending: 0, daysEarned: 30 });
    expect(summary.referrals[0]).toMatchObject({ name: 'Mama Njeri Traders', status: 'REWARDED' });
    expect(summary.shareText).toContain('KAMA-7H2Q');
  });
});

describe('promo codes', () => {
  const addPromo = (state: any, over: Record<string, unknown> = {}) =>
    state.promos.push({ id: 'p1', code: 'LAUNCH30', freeDays: 30, isActive: true, redeemedCount: 0, maxRedemptions: null, expiresAt: null, ...over });

  it('adds the days at once to an active company', async () => {
    const { service, state, tenants } = build();
    addPromo(state);
    const before = tenants.ref.currentPeriodEnd.getTime();
    const result = await service.redeemCode('ref', 'u', 'launch30');
    expect(result).toMatchObject({ type: 'PROMO', applied: true, days: 30 });
    expect(tenants.ref.currentPeriodEnd.getTime() - before).toBe(30 * DAY);
  });

  it('holds the days for a company that has not activated, then lands them', async () => {
    const { service, state, tenants } = build();
    addPromo(state);
    const result = await service.redeemCode('me', 'u', 'LAUNCH30');
    expect(result).toMatchObject({ applied: false });
    expect(tenants.me.currentPeriodEnd).toBeNull();

    tenants.me.currentPeriodEnd = new Date(Date.now() + 7 * DAY);
    const before = tenants.me.currentPeriodEnd.getTime();
    await service.onActivated('me');
    await service.onActivated('me');
    expect(tenants.me.currentPeriodEnd.getTime() - before).toBe(30 * DAY);
  });

  it('allows one promo per company and respects limits and expiry', async () => {
    const { service, state } = build();
    addPromo(state);
    addPromo(state, { id: 'p2', code: 'OTHER', maxRedemptions: 1, redeemedCount: 1 });
    addPromo(state, { id: 'p3', code: 'OLD', expiresAt: new Date(Date.now() - DAY) });

    await service.redeemCode('ref', 'u', 'LAUNCH30');
    await expect(service.redeemCode('ref', 'u', 'LAUNCH30')).rejects.toBeInstanceOf(ConflictException);
    await expect(service.redeemCode('me', 'u', 'OTHER')).rejects.toThrow('fully used');
    await expect(service.redeemCode('me', 'u', 'OLD')).rejects.toThrow('expired');
  });
});
