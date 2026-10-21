import {
  PLATFORM_PERMISSIONS,
  PLATFORM_ROLES,
  ROLE_PERMISSIONS,
  assignableRoles,
  canManageRole,
  permissionsForRole,
  roleHasPermission,
} from './platform-permissions';
import {
  base32Decode,
  base32Encode,
  generateBackupCodes,
  generateTempPassword,
  hotp,
  normalizeBackupCode,
  openSecret,
  passwordMeetsPolicy,
  sealSecret,
  totpNow,
  verifyTotp,
} from '../security/totp.util';
import { canSecureTarget } from '../platform-team.service';

describe('platform role matrix', () => {
  it('only OWNER and ADMIN can manage the team', () => {
    const managers = PLATFORM_ROLES.filter((r) => roleHasPermission(r, 'team.manage'));
    expect(managers.sort()).toEqual(['ADMIN', 'OWNER']);
  });

  it('only finance-capable roles can touch money', () => {
    const money = PLATFORM_ROLES.filter((r) => roleHasPermission(r, 'billing.manage'));
    expect(money.sort()).toEqual(['ADMIN', 'FINANCE', 'OWNER']);
  });

  it('SECURITY can lock accounts and read the audit trail but cannot change billing or the team', () => {
    expect(roleHasPermission('SECURITY', 'security.manage')).toBe(true);
    expect(roleHasPermission('SECURITY', 'audit.view')).toBe(true);
    expect(roleHasPermission('SECURITY', 'tenants.security')).toBe(true);
    expect(roleHasPermission('SECURITY', 'billing.manage')).toBe(false);
    expect(roleHasPermission('SECURITY', 'team.manage')).toBe(false);
  });

  it('VIEWER is strictly read-only', () => {
    for (const p of permissionsForRole('VIEWER')) {
      expect(p.endsWith('.view')).toBe(true);
    }
  });

  it('every role only references known permissions, and OWNER holds all of them', () => {
    for (const role of PLATFORM_ROLES) {
      for (const p of ROLE_PERMISSIONS[role]) expect(PLATFORM_PERMISSIONS).toContain(p);
    }
    expect([...ROLE_PERMISSIONS.OWNER].sort()).toEqual([...PLATFORM_PERMISSIONS].sort());
  });

  it('unknown roles get no permissions', () => {
    expect(permissionsForRole('HACKER')).toEqual([]);
  });

  it('ADMIN cannot create or manage owners or other admins; OWNER can manage anyone', () => {
    expect(canManageRole('ADMIN', 'OWNER')).toBe(false);
    expect(canManageRole('ADMIN', 'ADMIN')).toBe(false);
    expect(canManageRole('ADMIN', 'SECURITY')).toBe(true);
    expect(canManageRole('OWNER', 'OWNER')).toBe(true);
    expect(assignableRoles('SUPPORT')).toEqual([]);
  });

  it('security actions only reach strictly lower-ranked staff (owner reaches all)', () => {
    expect(canSecureTarget('OWNER', 'OWNER')).toBe(true);
    expect(canSecureTarget('SECURITY', 'ADMIN')).toBe(false);
    expect(canSecureTarget('SECURITY', 'SECURITY')).toBe(false);
    expect(canSecureTarget('SECURITY', 'SUPPORT')).toBe(true);
    expect(canSecureTarget('ADMIN', 'SECURITY')).toBe(true);
  });
});

describe('TOTP and secret handling', () => {
  it('matches the RFC 4226 HOTP test vectors', () => {
    const secret = base32Encode(Buffer.from('12345678901234567890'));
    const expected = ['755224', '287082', '359152', '969429', '338314', '254676'];
    expected.forEach((code, counter) => expect(hotp(secret, counter)).toBe(code));
  });

  it('round-trips base32', () => {
    const raw = Buffer.from([1, 2, 3, 250, 251, 252, 0, 9]);
    expect(base32Decode(base32Encode(raw))).toEqual(raw);
  });

  it('accepts the current code, tolerates one step of drift, rejects older and malformed codes', () => {
    const secret = base32Encode(Buffer.from('12345678901234567890'));
    const t = 1_700_000_000_000;
    const code = totpNow(secret, t);
    expect(verifyTotp(secret, code, t)).toBe(true);
    expect(verifyTotp(secret, code, t + 30_000)).toBe(true);
    expect(verifyTotp(secret, code, t + 120_000)).toBe(false);
    expect(verifyTotp(secret, '12345', t)).toBe(false);
    expect(verifyTotp(secret, 'abcdef', t)).toBe(false);
  });

  it('seals and opens secrets, and fails with the wrong key or tampering', () => {
    const sealed = sealSecret('JBSWY3DPEHPK3PXP', 'key-one');
    expect(sealed).not.toContain('JBSWY3DPEHPK3PXP');
    expect(openSecret(sealed, 'key-one')).toBe('JBSWY3DPEHPK3PXP');
    expect(() => openSecret(sealed, 'key-two')).toThrow();
    const parts = sealed.split('.');
    parts[2] = Buffer.from('tampered').toString('base64url');
    expect(() => openSecret(parts.join('.'), 'key-one')).toThrow();
  });

  it('generates unique, well-formed backup codes', () => {
    const codes = generateBackupCodes(8);
    expect(new Set(codes).size).toBe(8);
    for (const c of codes) expect(c).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    expect(normalizeBackupCode('ab12-cd34')).toBe('AB12CD34');
  });

  it('temporary passwords always satisfy the password policy', () => {
    for (let i = 0; i < 50; i++) expect(passwordMeetsPolicy(generateTempPassword())).toBe(true);
  });

  it('enforces the password policy', () => {
    expect(passwordMeetsPolicy('short1!A')).toBe(false);
    expect(passwordMeetsPolicy('alllowercase123!')).toBe(false);
    expect(passwordMeetsPolicy('NOLOWERCASE123!')).toBe(false);
    expect(passwordMeetsPolicy('NoDigitsHere!!!!')).toBe(false);
    expect(passwordMeetsPolicy('NoSymbolsHere1234')).toBe(false);
    expect(passwordMeetsPolicy('Str0ng&LongEnough')).toBe(true);
  });
});
