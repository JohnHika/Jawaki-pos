import { PermissionsService } from './permissions.service';

describe('PermissionsService default role safeguards', () => {
  function serviceWith(role: any, overrides: any[] = []) {
    const prisma: any = {
      userRole: { findMany: jest.fn().mockResolvedValue([{ role }]) },
      userPermissionOverride: { findMany: jest.fn().mockResolvedValue(overrides) },
    };
    return new PermissionsService(prisma);
  }

  it('strips elevated historical grants from the system Cashier role', async () => {
    const service = serviceWith({
      name: 'Cashier',
      isSystem: true,
      permissions: [
        { permissionKey: 'sales.create' },
        { permissionKey: 'sales.view' },
        { permissionKey: 'sales.view_all' },
        { permissionKey: 'sales.void' },
        { permissionKey: 'products.view' },
        { permissionKey: 'products.delete' },
      ],
    });

    await expect(service.getEffectivePermissions('cashier-1')).resolves.toEqual([
      'sales.create',
      'sales.view',
      'products.view',
    ]);
  });

  it('preserves an explicit administrator grant on top of the default role', async () => {
    const service = serviceWith(
      {
        name: 'Cashier',
        isSystem: true,
        permissions: [{ permissionKey: 'sales.view' }],
      },
      [{ permissionKey: 'sales.view_all', grant: true }],
    );

    await expect(service.getEffectivePermissions('cashier-1')).resolves.toEqual([
      'sales.view',
      'sales.view_all',
    ]);
  });
});
