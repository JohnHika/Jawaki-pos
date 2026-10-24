import { PERMISSIONS_KEY } from '../auth/decorators/require-permissions.decorator';
import { SalesController } from './sales.controller';

describe('SalesController read access', () => {
  let service: any;
  let controller: SalesController;

  beforeEach(() => {
    service = {
      getSales: jest.fn().mockResolvedValue({ items: [] }),
      getDailySummary: jest.fn().mockResolvedValue({ totalSales: 0 }),
    };
    controller = new SalesController(service);
  });

  it('limits a sales.view user to their own sales even if they request another user', async () => {
    await controller.getSales(
      { user: { sub: 'cashier-1', tenantId: 'tenant-1', permissions: ['sales.view'] } } as any,
      { userId: 'cashier-2', page: 1 } as any,
    );

    expect(service.getSales).toHaveBeenCalledWith('tenant-1', {
      userId: 'cashier-1',
      page: 1,
    });
  });

  it('lets sales.view_all users keep their requested sales filters', async () => {
    const query = { userId: 'cashier-2', page: 1 } as any;
    await controller.getSales(
      {
        user: {
          sub: 'manager-1',
          tenantId: 'tenant-1',
          permissions: ['sales.view', 'sales.view_all'],
        },
      } as any,
      query,
    );

    expect(service.getSales).toHaveBeenCalledWith('tenant-1', query);
  });

  it('requires the sales summary capability for daily shop totals', () => {
    expect(
      Reflect.getMetadata(PERMISSIONS_KEY, SalesController.prototype.getDailySummary),
    ).toEqual(['reporting.sales_summary']);
  });

  it('requires sync permission to reconcile queued offline sales', () => {
    expect(
      Reflect.getMetadata(PERMISSIONS_KEY, SalesController.prototype.reconcileOfflineSales),
    ).toEqual(['sync.push']);
  });
});
