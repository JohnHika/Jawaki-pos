import { WorkspaceService } from './workspace.service';

describe('WorkspaceService', () => {
  it('creates a pending workspace only from a verified identity and persists owner onboarding', async () => {
    const tx: any = {
      tenant: { create: jest.fn().mockResolvedValue({ id: 'tenant-1', slug: 'acme' }) },
      branch: { create: jest.fn().mockResolvedValue({ id: 'branch-1' }) },
      permission: { findMany: jest.fn().mockResolvedValue([
        'users.create', 'sales.create', 'sales.view', 'sales.view_all',
        'sales.void', 'products.view', 'products.delete', 'customers.view',
      ].map((key) => ({ key }))) },
      user: { create: jest.fn().mockResolvedValue({ id: 'owner-1', tenantId: 'tenant-1', email: 'owner@example.test', role: 'ADMIN', branches: [{ branchId: 'branch-1', isPrimary: true, branch: { id: 'branch-1', name: 'Main' } }] }) },
      policyAcceptance: { createMany: jest.fn() },
      role: { create: jest.fn().mockResolvedValue({ id: 'admin-role' }) },
      userRole: { create: jest.fn() },
      tenantOnboarding: { create: jest.fn() },
    };
    const prisma: any = {
      tenant: { findUnique: jest.fn().mockResolvedValue(null), findFirst: jest.fn().mockResolvedValue(null) },
      $transaction: jest.fn((operation: any) => operation(tx)),
    };
    const service = new WorkspaceService(prisma);

    await service.createFromVerifiedIdentity({
      email: 'Owner@Example.test', provider: 'GOOGLE', firstName: 'Owner', lastName: 'Example',
      companyName: 'Acme Stores', companySlug: 'acme', branch: { name: 'Main', code: 'MAIN' },
      acceptedPolicyTypes: ['TERMS_OF_SERVICE', 'PRIVACY_NOTICE', 'DATA_PROCESSING_ADDENDUM'],
    });

    expect(tx.user.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({
      email: 'owner@example.test', passwordHash: null, identityProvider: 'GOOGLE', identityVerifiedAt: expect.any(Date),
    }) }));
    expect(tx.tenantOnboarding.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({
      ownerUserId: 'owner-1', steps: { create: expect.arrayContaining([expect.objectContaining({ key: 'invite_staff', position: 3 })]) },
    }) }));
    const cashier = tx.role.create.mock.calls
      .map(([call]: any[]) => call.data)
      .find((role: any) => role.name === 'Cashier');
    const cashierKeys = cashier.permissions.create.map((item: any) => item.permissionKey);
    expect(cashierKeys).toContain('sales.create');
    expect(cashierKeys).toContain('sales.view');
    expect(cashierKeys).toContain('products.view');
    expect(cashierKeys).not.toContain('sales.view_all');
    expect(cashierKeys).not.toContain('sales.void');
    expect(cashierKeys).not.toContain('products.delete');
  });
});
