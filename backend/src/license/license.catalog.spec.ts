import {
  generateLicenseKey,
  isFeatureAllowed,
  isWithinLimit,
  resolveLicense,
} from './license.catalog';

const NOW = new Date('2026-10-16T10:00:00Z');
const tenant = (over: Partial<Parameters<typeof resolveLicense>[0]> = {}) => ({
  plan: 'CORE',
  maxBranches: 1,
  maxUsers: 3,
  settings: {},
  ...over,
});

describe('resolveLicense', () => {
  it('reports plan flags but never gates when enforcement is off (the default)', () => {
    const lic = resolveLicense(tenant({ plan: 'TRIAL' }), { now: NOW });
    expect(lic.enforcement).toBe('off');
    expect(lic.features.aiAssistant).toEqual({ allowed: false, source: 'plan' });
    expect(isFeatureAllowed(lic, 'aiAssistant')).toBe(true);
    expect(isWithinLimit(lic, 'branches', 99)).toBe(true);
  });

  it('gates modules the plan does not include once enforced', () => {
    const lic = resolveLicense(
      tenant({ plan: 'CORE', settings: { license: { enforcement: 'enforce' } } }),
      { now: NOW },
    );
    expect(isFeatureAllowed(lic, 'analytics')).toBe(true); // Core includes it
    expect(isFeatureAllowed(lic, 'aiAssistant')).toBe(false);
    expect(isFeatureAllowed(lic, 'customReports')).toBe(false);
  });

  it('limits unpaid trial selections to trial features and seats', () => {
    const lic = resolveLicense(
      tenant({
        plan: 'ENTERPRISE', subscriptionStatus: 'TRIAL',
        maxBranches: 999999, maxUsers: 999999,
        settings: { license: { enforcement: 'enforce' } },
      }),
      { now: NOW },
    );
    expect(lic.plan).toBe('TRIAL');
    expect(lic.limits).toEqual({ maxBranches: 1, maxUsers: 3 });
    expect(isFeatureAllowed(lic, 'aiAssistant')).toBe(false);
  });

  it('lets the operator grant or revoke a module regardless of plan', () => {
    const lic = resolveLicense(
      tenant({
        plan: 'CORE',
        settings: {
          license: {
            enforcement: 'enforce',
            overrides: { aiAssistant: true, analytics: false },
          },
        },
      }),
      { now: NOW },
    );
    expect(lic.features.aiAssistant).toEqual({ allowed: true, source: 'override' });
    expect(isFeatureAllowed(lic, 'aiAssistant')).toBe(true);
    expect(isFeatureAllowed(lic, 'analytics')).toBe(false);
  });

  it('takes the platform default mode unless the tenant sets its own', () => {
    expect(
      resolveLicense(tenant(), { now: NOW, defaultMode: 'enforce' }).enforced,
    ).toBe(true);
    expect(
      resolveLicense(
        tenant({ settings: { license: { enforcement: 'off' } } }),
        { now: NOW, defaultMode: 'enforce' },
      ).enforced,
    ).toBe(false);
    // Garbage in settings falls back to the default instead of enforcing.
    expect(
      resolveLicense(tenant({ settings: { license: { enforcement: 'maybe' } } }), {
        now: NOW,
      }).enforcement,
    ).toBe('off');
  });

  it('never locks a paying client to the schema default of 1 branch / 3 users', () => {
    const lic = resolveLicense(
      tenant({
        plan: 'BUSINESS',
        maxBranches: 1,
        maxUsers: 3,
        settings: { license: { enforcement: 'enforce' } },
      }),
      { now: NOW },
    );
    expect(lic.limits).toEqual({ maxBranches: 10, maxUsers: 50 });
    expect(isWithinLimit(lic, 'branches', 9)).toBe(true);
    expect(isWithinLimit(lic, 'branches', 10)).toBe(false);
  });

  it('honours explicit operator limits over the plan', () => {
    const lic = resolveLicense(
      tenant({
        plan: 'BUSINESS',
        settings: {
          license: { enforcement: 'enforce', maxBranches: 2, maxUsers: 5 },
        },
      }),
      { now: NOW },
    );
    expect(lic.limits).toEqual({ maxBranches: 2, maxUsers: 5 });
  });

  it('blocks every module once an enforced licence has expired', () => {
    const lic = resolveLicense(
      tenant({
        plan: 'ENTERPRISE',
        settings: {
          license: { enforcement: 'enforce', validUntil: '2026-10-01T00:00:00Z' },
        },
      }),
      { now: NOW },
    );
    expect(lic.expired).toBe(true);
    expect(isFeatureAllowed(lic, 'analytics')).toBe(false);
  });

  it('ignores expiry while enforcement is off or warn', () => {
    const lic = resolveLicense(
      tenant({
        settings: {
          license: { enforcement: 'warn', validUntil: '2026-10-01T00:00:00Z' },
        },
      }),
      { now: NOW },
    );
    expect(lic.expired).toBe(true);
    expect(isFeatureAllowed(lic, 'analytics')).toBe(true);
  });

  it('treats an unknown plan as a trial', () => {
    expect(resolveLicense(tenant({ plan: 'MYSTERY' }), { now: NOW }).limits).toEqual({
      maxBranches: 1,
      maxUsers: 3,
    });
  });
});

describe('generateLicenseKey', () => {
  it('is AXON-XXXX-XXXX-XXXX without look-alike characters', () => {
    const key = generateLicenseKey(() => Uint8Array.from({ length: 12 }, (_, i) => i * 7));
    expect(key).toMatch(/^AXON-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
  });
});

describe('legacy plans', () => {
  it('never locks a company whose plan is not in the price list', () => {
    const lic = resolveLicense(
      {
        plan: 'PRO',
        maxBranches: 3,
        maxUsers: 10,
        settings: { license: { enforcement: 'enforce' } },
      },
      { now: NOW },
    );
    expect(lic.unknownPlan).toBe(true);
    expect(isFeatureAllowed(lic, 'aiAssistant')).toBe(true);
    expect(lic.limits).toEqual({ maxBranches: 3, maxUsers: 10 });
  });

  it('still lets the operator revoke a module for an unknown plan', () => {
    const lic = resolveLicense(
      {
        plan: 'PRO',
        maxBranches: null,
        maxUsers: null,
        settings: { license: { enforcement: 'enforce', overrides: { aiAssistant: false } } },
      },
      { now: NOW },
    );
    expect(isFeatureAllowed(lic, 'aiAssistant')).toBe(false);
    expect(isFeatureAllowed(lic, 'analytics')).toBe(true);
    expect(lic.limits.maxBranches).toBeGreaterThanOrEqual(1000);
  });
});
