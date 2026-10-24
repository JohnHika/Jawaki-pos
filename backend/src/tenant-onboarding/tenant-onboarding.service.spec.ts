import { ForbiddenException, HttpException } from '@nestjs/common';
import { TenantOnboardingService } from './tenant-onboarding.service';

describe('TenantOnboardingService staff invitations', () => {
  it('shows a manager only roles within the manager’s own permissions', async () => {
    const prisma: any = {
      tenantOnboarding: { findUnique: jest.fn().mockResolvedValue({ ownerUserId: 'owner-1' }) },
      role: {
        findMany: jest.fn().mockResolvedValue([
          { id: 'cashier-role', name: 'Cashier', permissions: [{ permissionKey: 'sales.create' }] },
          { id: 'admin-role', name: 'Admin', permissions: [{ permissionKey: 'users.deactivate' }] },
        ]),
      },
    };
    const service = new TenantOnboardingService(prisma, { request: jest.fn() } as any);

    await expect(service.getStaffInvitationOptions({
      sub: 'manager-1',
      tenantId: 'tenant-1',
      permissions: ['users.create', 'sales.create'],
    })).resolves.toEqual([{ id: 'cashier-role', name: 'Cashier' }]);
  });

  it('prevents a staff manager from inviting someone into a more privileged role', async () => {
    const prisma: any = {
      tenantOnboarding: { findUnique: jest.fn().mockResolvedValue({ ownerUserId: 'owner-1' }) },
      branch: { findFirst: jest.fn().mockResolvedValue({ id: 'branch-1' }) },
      role: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'admin-role',
          permissions: [{ permissionKey: 'users.deactivate' }],
        }),
      },
      user: { findFirst: jest.fn() },
      tenantStaffInvitation: { create: jest.fn() },
    };
    const otp = { request: jest.fn() };
    const service = new TenantOnboardingService(prisma, otp as any);

    await expect(service.createInvitation(
      { sub: 'manager-1', tenantId: 'tenant-1', permissions: ['users.create'] },
      { email: 'staff@example.test', firstName: 'Staff', lastName: 'Member', roleId: 'admin-role', branchId: 'branch-1' },
    )).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.tenantStaffInvitation.create).not.toHaveBeenCalled();
    expect(otp.request).not.toHaveBeenCalled();
  });

  it('allows an authorized manager to invite a staff role within their permissions', async () => {
    const prisma: any = {
      tenantOnboarding: { findUnique: jest.fn().mockResolvedValue({ ownerUserId: 'owner-1' }) },
      branch: { findFirst: jest.fn().mockResolvedValue({ id: 'branch-1' }) },
      role: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'cashier-role',
          permissions: [{ permissionKey: 'sales.create' }],
        }),
      },
      user: { findFirst: jest.fn().mockResolvedValue(null) },
      tenantStaffInvitation: {
        create: jest.fn().mockResolvedValue({ id: 'invite-1' }),
        update: jest.fn().mockResolvedValue({}),
      },
    };
    const otp = { request: jest.fn().mockResolvedValue({ challengeId: 'challenge-1' }) };
    const service = new TenantOnboardingService(prisma, otp as any);

    await expect(service.createInvitation(
      { sub: 'manager-1', tenantId: 'tenant-1', permissions: ['users.create', 'sales.create'] },
      { email: 'staff@example.test', firstName: 'Staff', lastName: 'Member', roleId: 'cashier-role', branchId: 'branch-1' },
    )).resolves.toEqual({ accepted: true, invitationId: 'invite-1', challengeId: 'challenge-1' });
    expect(prisma.tenantStaffInvitation.create).toHaveBeenCalledTimes(1);
    expect(otp.request).toHaveBeenCalledTimes(1);
  });

  it('rejects a branch outside the caller tenant before creating an invitation', async () => {
    const prisma: any = {
      tenantOnboarding: { findUnique: jest.fn().mockResolvedValue({ ownerUserId: 'owner-1' }) },
      branch: { findFirst: jest.fn().mockResolvedValue(null) },
      role: { findFirst: jest.fn() },
      tenantStaffInvitation: { create: jest.fn() },
    };
    const otp = { request: jest.fn() };
    const service = new TenantOnboardingService(prisma, otp as any);

    await expect(service.createInvitation(
      { sub: 'owner-1', tenantId: 'tenant-1', permissions: ['users.create'] },
      { email: 'staff@example.test', firstName: 'Staff', lastName: 'Member', roleId: 'role-other', branchId: 'branch-other' },
    )).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.tenantStaffInvitation.create).not.toHaveBeenCalled();
    expect(otp.request).not.toHaveBeenCalled();
  });

  it('lists invitations for an admin of a company with no onboarding row', async () => {
    const prisma: any = {
      tenantOnboarding: { findUnique: jest.fn().mockResolvedValue(null) },
      tenantStaffInvitation: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = new TenantOnboardingService(prisma, { request: jest.fn() } as any);

    await expect(service.listInvitations(
      { sub: 'admin-1', tenantId: 'tenant-1', permissions: ['users.create'] },
    )).resolves.toEqual([]);
  });

  it('still refuses a caller without users.create when there is no onboarding row', async () => {
    const prisma: any = {
      tenantOnboarding: { findUnique: jest.fn().mockResolvedValue(null) },
      tenantStaffInvitation: { findMany: jest.fn() },
    };
    const service = new TenantOnboardingService(prisma, { request: jest.fn() } as any);

    await expect(service.listInvitations(
      { sub: 'cashier-1', tenantId: 'tenant-1', permissions: [] },
    )).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.tenantStaffInvitation.findMany).not.toHaveBeenCalled();
  });

  it('returns an empty checklist (not a 404) for a company with no onboarding row', async () => {
    const prisma: any = { tenantOnboarding: { findUnique: jest.fn().mockResolvedValue(null) } };
    const service = new TenantOnboardingService(prisma, { request: jest.fn() } as any);

    await expect(service.get({ sub: 'u1', tenantId: 't1' })).resolves.toEqual({
      id: null,
      tenantId: 't1',
      steps: [],
    });
  });
});

describe('TenantOnboardingService seat limits', () => {
  it('refuses a new invitation with 402 when the plan has no seats left', async () => {
    const prisma: any = {
      tenantOnboarding: { findUnique: jest.fn().mockResolvedValue({ ownerUserId: 'owner-1' }) },
      branch: { findFirst: jest.fn() },
      role: { findFirst: jest.fn() },
      tenantStaffInvitation: { create: jest.fn() },
    };
    const license = {
      assertWithinLimit: jest.fn().mockRejectedValue(
        new HttpException({ code: 'LICENSE_LIMIT_REACHED' }, 402),
      ),
    };
    const service = new TenantOnboardingService(prisma, { request: jest.fn() } as any, license as any);

    await expect(service.createInvitation(
      { sub: 'owner-1', tenantId: 'tenant-1', permissions: ['users.create'] },
      { email: 'staff@example.test', firstName: 'S', lastName: 'M', roleId: 'r', branchId: 'b' },
    )).rejects.toMatchObject({ status: 402 });
    expect(license.assertWithinLimit).toHaveBeenCalledWith('tenant-1', 'users');
    expect(prisma.tenantStaffInvitation.create).not.toHaveBeenCalled();
  });
});
