/**
 * ACA (Axon Counterbase Admin) role-based access control.
 *
 * The Counterbase team is small and its roles are fixed, so the matrix lives
 * in code (reviewable, versioned, testable) rather than in the database. The
 * database only stores which role a staff member holds.
 */

export const PLATFORM_ROLES = [
  'OWNER',
  'ADMIN',
  'SECURITY',
  'FINANCE',
  'SUPPORT',
  'VIEWER',
] as const;
export type PlatformRole = (typeof PLATFORM_ROLES)[number];

export const PLATFORM_PERMISSIONS = [
  'dashboard.view',
  'tenants.view',
  'tenants.manage', // extend subscription, add notes
  'tenants.suspend', // suspend / reactivate a company
  'tenants.license', // edit licence, modules and seat limits
  'tenants.users', // see a company's staff accounts and devices
  'tenants.security', // lock accounts, revoke sessions, force logout
  'billing.view',
  'billing.manage', // issue billing credits
  'team.view',
  'team.manage',
  'security.view',
  'security.manage',
  'audit.view',
] as const;
export type PlatformPermission = (typeof PLATFORM_PERMISSIONS)[number];

const ALL: readonly PlatformPermission[] = PLATFORM_PERMISSIONS;

export const ROLE_PERMISSIONS: Record<PlatformRole, readonly PlatformPermission[]> = {
  OWNER: ALL,
  ADMIN: ALL,
  SECURITY: [
    'dashboard.view',
    'tenants.view',
    'tenants.suspend',
    'tenants.users',
    'tenants.security',
    'team.view',
    'security.view',
    'security.manage',
    'audit.view',
  ],
  FINANCE: ['dashboard.view', 'tenants.view', 'billing.view', 'billing.manage', 'audit.view'],
  SUPPORT: [
    'dashboard.view',
    'tenants.view',
    'tenants.manage',
    'tenants.users',
    'billing.view',
  ],
  VIEWER: ['dashboard.view', 'tenants.view', 'billing.view'],
};

/** Higher rank = more authority. Used to decide who may manage whom. */
export const ROLE_RANK: Record<PlatformRole, number> = {
  OWNER: 100,
  ADMIN: 80,
  SECURITY: 60,
  FINANCE: 50,
  SUPPORT: 40,
  VIEWER: 10,
};

export const ROLE_DESCRIPTIONS: Record<PlatformRole, string> = {
  OWNER: 'Full control of Counterbase, including the team and ownership.',
  ADMIN: 'Runs day-to-day operations and manages non-admin staff.',
  SECURITY: 'Monitors sign-ins, audits activity and locks down accounts and devices.',
  FINANCE: 'Handles invoices, payments and credits.',
  SUPPORT: 'Helps clients: subscription extensions, notes and staff look-ups.',
  VIEWER: 'Read-only access to dashboards, clients and billing.',
};

export function isPlatformRole(value: unknown): value is PlatformRole {
  return typeof value === 'string' && (PLATFORM_ROLES as readonly string[]).includes(value);
}

export function permissionsForRole(role: string): PlatformPermission[] {
  return isPlatformRole(role) ? [...ROLE_PERMISSIONS[role]] : [];
}

export function roleHasPermission(role: string, permission: PlatformPermission): boolean {
  return permissionsForRole(role).includes(permission);
}

/**
 * Roles `actorRole` is allowed to hand out / manage.
 *  - OWNER manages everyone, including other owners.
 *  - ADMIN manages staff strictly below ADMIN (never owners or other admins).
 *  - Everyone else manages nobody.
 */
export function assignableRoles(actorRole: string): PlatformRole[] {
  if (actorRole === 'OWNER') return [...PLATFORM_ROLES];
  if (actorRole === 'ADMIN') {
    return PLATFORM_ROLES.filter((r) => ROLE_RANK[r] < ROLE_RANK.ADMIN);
  }
  return [];
}

export function canManageRole(actorRole: string, targetRole: string): boolean {
  return (assignableRoles(actorRole) as string[]).includes(targetRole);
}
