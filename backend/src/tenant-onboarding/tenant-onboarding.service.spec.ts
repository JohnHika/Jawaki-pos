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
});
