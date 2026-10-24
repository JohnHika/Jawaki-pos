import { BadRequestException, ConflictException, GoneException, HttpException } from '@nestjs/common';
import { StatementsService, overdueDaysFor } from './statements.service';
import { StatementView } from './statements.types';

const DAY = 86_400_000;

const baseView = (over: Partial<StatementView> = {}): StatementView => ({
  business: { name: 'Kamau Imports', phone: null, logo: null, payInstructions: null },
  debtor: { name: 'John Kamau', kind: 'CUSTOMER' },
  asOf: new Date(),
  outstanding: 5_000,
  overdue: 0,
  oldestOverdueDays: 0,
  items: [],
  payments: [],
  message: null,
  expiresAt: null,
  inviteCode: 'KAMA-7H2Q',
  ...over,
});

function build(opts: { outstanding?: number; env?: Record<string, string> } = {}) {
  const state = {
    links: [] as any[],
    claims: [] as any[],
    entries: [] as any[],
  };
  const prisma: any = {
    statementLink: {
      create: jest.fn(async ({ data }: any) => {
        const row = { id: `link-${state.links.length + 1}`, viewCount: 0, firstViewedAt: null, lastViewedAt: null, revokedAt: null, createdAt: new Date(), ...data };
        state.links.push(row);
        return row;
      }),
      findUnique: jest.fn(async ({ where }: any) => state.links.find((l) => l.token === where.token) ?? null),
      update: jest.fn(async ({ where, data }: any) => {
        const row = state.links.find((l) => l.id === where.id);
        if (data.viewCount?.increment) row.viewCount += data.viewCount.increment;
        for (const [k, v] of Object.entries(data)) if (k !== 'viewCount') row[k] = v;
        return row;
      }),
    },
    statementClaim: {
      count: jest.fn(async ({ where }: any) => state.claims.filter((c) => c.linkId === where.linkId && c.status === where.status).length),
      findFirst: jest.fn(async ({ where }: any) => {
        if (where.id) {
          const c = state.claims.find((x) => x.id === where.id && x.tenantId === where.tenantId);
          return c ? { ...c, link: state.links.find((l) => l.id === c.linkId) } : null;
        }
        return state.claims.find((c) => c.mpesaCode === where.mpesaCode && c.status !== 'REJECTED') ?? null;
      }),
      create: jest.fn(async ({ data }: any) => {
        const row = { id: `claim-${state.claims.length + 1}`, status: 'PENDING', createdAt: new Date(), ...data };
        state.claims.push(row);
        return row;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const row = state.claims.find((c) => c.id === where.id);
        Object.assign(row, data);
        return row;
      }),
    },
    mpesaEntry: {
      findUnique: jest.fn(async ({ where }: any) => state.entries.find((e) => e.code === where.tenantId_code.code) ?? null),
      upsert: jest.fn(async ({ create, update, where }: any) => {
        const existing = state.entries.find((e) => e.code === where.tenantId_code.code);
        if (existing) return Object.assign(existing, update);
        state.entries.push(create);
        return create;
      }),
    },
    tenant: { findUnique: jest.fn().mockResolvedValue({ name: 'Kamau Imports' }) },
    customer: { findFirst: jest.fn().mockResolvedValue({ name: 'John Kamau' }) },
    user: { findMany: jest.fn().mockResolvedValue([{ id: 'owner-1' }]) },
  };
  const audit = { record: jest.fn() };
  const notifications = { sendToUser: jest.fn() };
  const referrals = { getOrCreateCode: jest.fn().mockResolvedValue('KAMA-7H2Q') };
  const collections = {
    outstandingFor: jest.fn().mockResolvedValue(opts.outstanding ?? 5_000),
    applyPayment: jest.fn().mockResolvedValue({ applied: 2_000, unallocated: 0, debtsTouched: 1 }),
  };
  const config = { get: jest.fn((key: string) => opts.env?.[key]) };
  const service = new StatementsService(prisma, config as any, audit as any, notifications as any, referrals as any, collections as any);
  jest.spyOn(service, 'buildView').mockImplementation(async () => baseView({ outstanding: opts.outstanding ?? 5_000 }));
  return { service, prisma, state, audit, notifications, collections };
}

describe('overdueDaysFor', () => {
  const now = new Date('2026-10-24T12:00:00Z');
  it('counts whole days past due, at least one', () => {
    expect(overdueDaysFor(null, now)).toBe(0);
    expect(overdueDaysFor(new Date('2026-10-30T00:00:00Z'), now)).toBe(0);
    expect(overdueDaysFor(new Date('2026-10-24T06:00:00Z'), now)).toBe(1);
    expect(overdueDaysFor(new Date('2026-10-14T12:00:00Z'), now)).toBe(10);
  });
});

describe('creating a link', () => {
  it('needs exactly one of customer or shop', async () => {
    const { service } = build();
    await expect(service.createLink('u', 't', {} as any)).rejects.toBeInstanceOf(BadRequestException);
    await expect(service.createLink('u', 't', { customerId: 'a', debtorId: 'b' } as any)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('refuses to chase someone who owes nothing', async () => {
    const { service } = build({ outstanding: 0 });
    await expect(service.createLink('u', 't', { customerId: 'c1' } as any)).rejects.toThrow('does not owe anything');
  });

  it('makes a long unguessable token, an expiry, a public address and ready-to-send text', async () => {
    const { service, audit } = build({ env: { PUBLIC_API_URL: 'https://api.example.com/api/v1/' } });
    const link = await service.createLink('u', 't', { customerId: 'c1', message: 'Please pay Friday', days: 7 } as any);
    expect(link.token).toMatch(/^[A-Za-z0-9_-]{32}$/);
    expect(link.url).toBe(`https://api.example.com/s/${link.token}`);
    expect(link.path).toBe(`/s/${link.token}`);
    expect(Math.round((link.expiresAt.getTime() - Date.now()) / DAY)).toBe(7);
    expect(link.shareText.en).toContain(link.url as string);
    expect(link.shareText.sw).toContain('Habari John');
    expect(audit.record).toHaveBeenCalledWith(expect.objectContaining({ action: 'STATEMENT_LINK_CREATED' }));
    const second = await service.createLink('u', 't', { customerId: 'c1' } as any);
    expect(second.token).not.toBe(link.token);
  });

  it('falls back to a path when no public address is configured', async () => {
    const { service } = build();
    const link = await service.createLink('u', 't', { customerId: 'c1' } as any);
    expect(link.url).toBeNull();
    expect(link.shareText.en).toContain(link.path);
  });
});

describe('opening a link', () => {
  it('treats unknown, malformed, revoked and expired links the same', async () => {
    const { service, state } = build();
    const good = await service.createLink('u', 't', { customerId: 'c1' } as any);
    expect(await service.openLink(good.token)).not.toBeNull();
    expect(await service.openLink('nope')).toBeNull();
    expect(await service.openLink('x'.repeat(40))).toBeNull();
    state.links[0].revokedAt = new Date();
    expect(await service.openLink(good.token)).toBeNull();
    state.links[0].revokedAt = null;
    state.links[0].expiresAt = new Date(Date.now() - 1000);
    expect(await service.openLink(good.token)).toBeNull();
  });

  it('does not count the owner downloading the PDF as the customer opening it', async () => {
    const { service, state, notifications } = build();
    const link = await service.createLink('u', 't', { customerId: 'c1' } as any);
    const pdf = await service.renderPdfForToken(link.token, 'en');
    await new Promise((r) => setImmediate(r));
    expect(pdf?.buffer.subarray(0, 5).toString()).toBe('%PDF-');
    expect(state.links[0].viewCount).toBe(0);
    expect(notifications.sendToUser).not.toHaveBeenCalled();
    // A request with no user agent at all is not a browser either.
    await service.openLink(link.token);
    await new Promise((r) => setImmediate(r));
    expect(state.links[0].viewCount).toBe(0);
  });

  it('counts a real visit, tells the owner on the first one only, and ignores link-preview robots', async () => {
    const { service, state, notifications } = build();
    const link = await service.createLink('u', 't', { customerId: 'c1' } as any);

    await service.openLink(link.token, 'WhatsApp/2.23.20 A');
    await service.openLink(link.token, 'facebookexternalhit/1.1');
    await new Promise((r) => setImmediate(r));
    expect(state.links[0].viewCount).toBe(0);
    expect(notifications.sendToUser).not.toHaveBeenCalled();

    const phone = 'Mozilla/5.0 (Linux; Android 13) Chrome/120 Mobile Safari/537.36';
    await service.openLink(link.token, phone);
    await new Promise((r) => setImmediate(r));
    await service.openLink(link.token, phone);
    await new Promise((r) => setImmediate(r));
    expect(state.links[0].viewCount).toBe(2);
    expect(state.links[0].firstViewedAt).toBeInstanceOf(Date);
    expect(notifications.sendToUser).toHaveBeenCalledTimes(1);
    expect(notifications.sendToUser.mock.calls[0][0]).toBe('u');
  });
});

describe('replies from the link', () => {
  const setup = async (outstanding = 5_000) => {
    const ctx = build({ outstanding });
    const link = await ctx.service.createLink('owner', 't', { customerId: 'c1' } as any);
    return { ...ctx, token: link.token };
  };

  it('rejects an expired link with 410', async () => {
    const { service } = build();
    await expect(service.submitClaim('missing-token-missing-token', { kind: 'PAID' } as any)).rejects.toBeInstanceOf(GoneException);
  });

  it('takes an "I have paid" reply, caps it at what is owed, and alerts the owner', async () => {
    const { service, state, notifications, token } = await setup(3_000);
    const reply = await service.submitClaim(token, { kind: 'PAID', mpesaCode: 'qjk1a2b3c4', amount: 9_000, payerName: 'John' } as any);
    expect(reply.received).toBe(true);
    expect(state.claims[0]).toMatchObject({ kind: 'PAID', mpesaCode: 'QJK1A2B3C4', amount: 3_000, status: 'PENDING' });
    expect(notifications.sendToUser).toHaveBeenCalled();
  });

  it('needs the code and the amount', async () => {
    const { service, token } = await setup();
    await expect(service.submitClaim(token, { kind: 'PAID', amount: 100 } as any)).rejects.toThrow('M-Pesa code');
    await expect(service.submitClaim(token, { kind: 'PAID', mpesaCode: 'QJK1A2B3C4' } as any)).rejects.toThrow('amount');
  });

  it('refuses the same code twice', async () => {
    const { service, token } = await setup();
    await service.submitClaim(token, { kind: 'PAID', mpesaCode: 'QJK1A2B3C4', amount: 100 } as any);
    await expect(
      service.submitClaim(token, { kind: 'PAID', mpesaCode: 'QJK1A2B3C4', amount: 100 } as any),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('takes a promise date within 60 days and nothing else', async () => {
    const { service, state, token } = await setup();
    const soon = new Date(Date.now() + 5 * DAY).toISOString().slice(0, 10);
    await service.submitClaim(token, { kind: 'PROMISE', promisedFor: soon } as any);
    expect(state.claims[0]).toMatchObject({ kind: 'PROMISE' });
    await expect(service.submitClaim(token, { kind: 'PROMISE', promisedFor: '2020-01-01' } as any)).rejects.toThrow('next 60 days');
    const far = new Date(Date.now() + 90 * DAY).toISOString().slice(0, 10);
    await expect(service.submitClaim(token, { kind: 'PROMISE', promisedFor: far } as any)).rejects.toThrow('next 60 days');
    await expect(service.submitClaim(token, { kind: 'PROMISE' } as any)).rejects.toThrow('date');
  });

  it('says thank you without recording anything when nothing is owed', async () => {
    const { service, state, collections, token } = await setup();
    collections.outstandingFor.mockResolvedValue(0);
    const reply = await service.submitClaim(token, { kind: 'PAID', mpesaCode: 'QJK1A2B3C4', amount: 100 } as any);
    expect(reply.message).toContain('do not owe');
    expect(state.claims).toHaveLength(0);
  });

  it('stops a link from being flooded with replies', async () => {
    const { service, token } = await setup();
    for (let i = 0; i < 10; i++) {
      await service.submitClaim(token, { kind: 'PAID', mpesaCode: `QJK1A2B3${String(i).padStart(2, '0')}`, amount: 10 } as any);
    }
    await expect(
      service.submitClaim(token, { kind: 'PAID', mpesaCode: 'QJK1A2B399', amount: 10 } as any),
    ).rejects.toBeInstanceOf(HttpException);
  });
});

describe('deciding a reply', () => {
  const setup = async () => {
    const ctx = build();
    const link = await ctx.service.createLink('owner', 't', { customerId: 'c1' } as any);
    await ctx.service.submitClaim(link.token, { kind: 'PAID', mpesaCode: 'QJK1A2B3C4', amount: 2_000 } as any);
    return ctx;
  };

  it('does not settle an M-Pesa code reported by a customer', async () => {
    const { service, state, collections, audit } = await setup();
    await expect(
      service.decideClaim('owner', 't', 'claim-1', { action: 'CONFIRM' }),
    ).rejects.toThrow('not proof of payment');
    expect(collections.applyPayment).not.toHaveBeenCalled();
    expect(state.entries).toHaveLength(0);
    expect(state.claims[0].status).toBe('PENDING');
    expect(audit.record).not.toHaveBeenCalledWith(expect.objectContaining({ action: 'STATEMENT_CLAIM_CONFIRMED' }));
  });

  it('rejects without recording any money', async () => {
    const { service, state, collections } = await setup();
    const result = await service.decideClaim('owner', 't', 'claim-1', { action: 'REJECT' });
    expect(result.status).toBe('REJECTED');
    expect(collections.applyPayment).not.toHaveBeenCalled();
    expect(state.claims[0].status).toBe('REJECTED');
  });

  it('only decides each reply once, and a promise records no money', async () => {
    const ctx = await setup();
    await expect(
      ctx.service.decideClaim('owner', 't', 'claim-1', { action: 'CONFIRM' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    await ctx.service.decideClaim('owner', 't', 'claim-1', { action: 'REJECT' });
    await expect(ctx.service.decideClaim('owner', 't', 'claim-1', { action: 'REJECT' })).rejects.toBeInstanceOf(ConflictException);

    const link = ctx.state.links[0];
    const soon = new Date(Date.now() + 3 * DAY).toISOString().slice(0, 10);
    await ctx.service.submitClaim(link.token, { kind: 'PROMISE', promisedFor: soon } as any);
    ctx.collections.applyPayment.mockClear();
    const result = await ctx.service.decideClaim('owner', 't', 'claim-2', { action: 'CONFIRM' });
    expect(result.status).toBe('CONFIRMED');
    expect(ctx.collections.applyPayment).not.toHaveBeenCalled();
  });
});
