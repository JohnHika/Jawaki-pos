import { ConfigService } from '@nestjs/config';
import { HttpException } from '@nestjs/common';
import { LicenseService } from './license.service';

function build(opts: {
  plan?: string;
  settings?: unknown;
  branches?: number;
  users?: number;
  env?: string;
}) {
  const tenantRow = {
    id: 't1',
    plan: opts.plan ?? 'CORE',
    maxBranches: 1,
    maxUsers: 3,
    settings: opts.settings ?? {},
  };
  const prisma: any = {
    tenant: {
      findUnique: jest.fn().mockResolvedValue(tenantRow),
      findMany: jest.fn().mockResolvedValue([
        { ...tenantRow, name: 'Acme', slug: 'acme', _count: { branches: 2, users: 4 } },
      ]),
      update: jest.fn().mockResolvedValue({}),
    },
    branch: { count: jest.fn().mockResolvedValue(opts.branches ?? 0) },
    user: { count: jest.fn().mockResolvedValue(opts.users ?? 0) },
  };
  const config = { get: jest.fn().mockReturnValue(opts.env) } as unknown as ConfigService;
  return { svc: new LicenseService(prisma, config), prisma };
}

const enforce = { license: { enforcement: 'enforce' } };

describe('LicenseService', () => {
  it('lets everything through while enforcement is off', async () => {
    const { svc } = build({ plan: 'TRIAL' });
    await expect(svc.assertFeature('t1', 'aiAssistant')).resolves.toBeUndefined();
    await expect(svc.assertWithinLimit('t1', 'branches')).resolves.toBeUndefined();
  });

  it('refuses an unpaid module with 402 FEATURE_NOT_LICENSED', async () => {
    const { svc } = build({ plan: 'CORE', settings: enforce });
    const err: HttpException = await svc
      .assertFeature('t1', 'aiAssistant')
      .catch((e) => e);
    expect(err.getStatus()).toBe(402);
    expect(err.getResponse()).toMatchObject({
      code: 'FEATURE_NOT_LICENSED',
      feature: 'aiAssistant',
      plan: 'CORE',
    });
  });

  it('reports LICENSE_EXPIRED instead when the licence term has ended', async () => {
    const { svc } = build({
      plan: 'ENTERPRISE',
      settings: { license: { enforcement: 'enforce', validUntil: '2020-01-01T00:00:00Z' } },
    });
    const err: HttpException = await svc.assertFeature('t1', 'analytics').catch((e) => e);
    expect(err.getResponse()).toMatchObject({ code: 'LICENSE_EXPIRED' });
  });

  it('refuses a branch beyond the plan with 402 LICENSE_LIMIT_REACHED', async () => {
    const { svc } = build({ plan: 'CORE', settings: enforce, branches: 3 });
    const err: HttpException = await svc.assertWithinLimit('t1', 'branches').catch((e) => e);
    expect(err.getStatus()).toBe(402);
    expect(err.getResponse()).toMatchObject({
      code: 'LICENSE_LIMIT_REACHED',
      limit: 'branches',
      max: 3,
    });
  });

  it('allows adding up to the limit', async () => {
    const { svc } = build({ plan: 'CORE', settings: enforce, users: 9 });
    await expect(svc.assertWithinLimit('t1', 'users')).resolves.toBeUndefined();
  });

  it('follows the LICENSE_ENFORCEMENT env default', async () => {
    const { svc } = build({ plan: 'CORE', env: 'enforce' });
    await expect(svc.assertFeature('t1', 'aiAssistant')).rejects.toBeInstanceOf(HttpException);
  });

  it('describes the client view: unlocked modules and plan answers', async () => {
    const { svc } = build({ plan: 'CORE', settings: enforce });
    const view = await svc.describeForClient('t1');
    expect(view.enforced).toBe(true);
    expect(view.features).toMatchObject({ analytics: true, aiAssistant: false });
    expect(view.planFeatures).toMatchObject({ aiAssistant: false });
  });

  it('unlocks everything in the client view while enforcement is off', async () => {
    const { svc } = build({ plan: 'TRIAL' });
    const view = await svc.describeForClient('t1');
    expect(Object.values(view.features).every(Boolean)).toBe(true);
    expect(view.planFeatures).toMatchObject({ aiAssistant: false });
  });

  it('previews what enforcing would lock for each client', async () => {
    const { svc } = build({ plan: 'TRIAL' });
    const [row] = await svc.preview();
    expect(row).toMatchObject({
      slug: 'acme',
      enforcement: 'off',
      wouldBeAffected: true,
      overLimit: { branches: 1, users: 1 },
    });
    expect(row.lockedFeatures).toContain('aiAssistant');
  });

  describe('update', () => {
    it('merges overrides, issues a key and stores under settings.license', async () => {
      const { svc, prisma } = build({ settings: { theme: 'x' } });
      const { after } = await svc.update('t1', {
        enforcement: 'enforce',
        overrides: { aiAssistant: true },
        validUntil: '2027-01-01T00:00:00Z',
        maxUsers: 12,
        note: 'Paid KES 35,000 on 16 Oct',
      });
      expect(after.licenseKey).toMatch(/^AXON-/);
      const saved = prisma.tenant.update.mock.calls[0][0].data.settings;
      expect(saved.theme).toBe('x'); // unrelated settings survive
      expect(saved.license).toMatchObject({
        enforcement: 'enforce',
        overrides: { aiAssistant: true },
        maxUsers: 12,
        validUntil: '2027-01-01T00:00:00.000Z',
      });
    });

    it('null clears an override', async () => {
      const { svc } = build({
        settings: { license: { overrides: { aiAssistant: true }, licenseKey: 'AXON-KEEP' } },
      });
      const { after } = await svc.update('t1', { overrides: { aiAssistant: null } });
      expect(after.overrides).toEqual({});
      expect(after.licenseKey).toBe('AXON-KEEP'); // key is kept unless reissued
    });

    it('rejects nonsense', async () => {
      const { svc } = build({});
      await expect(svc.update('t1', { enforcement: 'maybe' as any })).rejects.toThrow();
      await expect(svc.update('t1', { overrides: { nope: true } as any })).rejects.toThrow();
      await expect(svc.update('t1', { validUntil: 'soon' })).rejects.toThrow();
      await expect(svc.update('t1', { maxBranches: 0 })).rejects.toThrow();
    });
  });
});
