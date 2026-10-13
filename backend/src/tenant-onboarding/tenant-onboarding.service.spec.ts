import { ForbiddenException } from '@nestjs/common';
import { TenantOnboardingService } from './tenant-onboarding.service';

describe('TenantOnboardingService staff invitations', () => {
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
