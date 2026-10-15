import { NotificationsService } from './notifications.service';

describe('NotificationsService inbox', () => {
  let prisma: any;
  let service: NotificationsService;

  beforeEach(() => {
    prisma = {
      appNotification: {
        create: jest.fn().mockResolvedValue({ id: 'n1' }),
        findMany: jest.fn().mockResolvedValue([]),
        count: jest.fn().mockResolvedValue(0),
        findFirst: jest.fn(),
        update: jest.fn(),
        updateMany: jest.fn(),
      },
      pushToken: { findMany: jest.fn().mockResolvedValue([]) },
      user: { findMany: jest.fn() },
    };
    // No FIREBASE_* config -> Firebase disabled.
    const config = { get: jest.fn().mockReturnValue(undefined) };
    service = new NotificationsService(prisma, config as any);
  });

  it('persists the notification even when Firebase is not configured', async () => {
    expect(service.isConfigured).toBe(false);
    await service.sendToUser('u1', {
      title: 'T',
      body: 'B',
      data: { type: 'partner_message', partnershipId: 'p1' },
    });
    expect(prisma.appNotification.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          userId: 'u1',
          type: 'partner_message',
          title: 'T',
          body: 'B',
          data: { partnershipId: 'p1' },
        }),
      }),
    );
    expect(prisma.pushToken.findMany).not.toHaveBeenCalled();
  });

  it('defaults the type to general and never throws when persistence fails', async () => {
    prisma.appNotification.create.mockRejectedValueOnce(new Error('db down'));
    await expect(service.sendToUser('u1', { title: 'T', body: 'B' })).resolves.toBeUndefined();

    await service.sendToUser('u1', { title: 'T', body: 'B' });
    expect(prisma.appNotification.create).toHaveBeenLastCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ type: 'general', data: undefined }),
      }),
    );
  });

  it('sendToTenantRoles notifies each active user with those roles', async () => {
    prisma.user.findMany.mockResolvedValue([{ id: 'a' }, { id: 'b' }]);
    await service.sendToTenantRoles('t1', ['ADMIN', 'MANAGER'], { title: 'T', body: 'B' });
    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { tenantId: 't1', isActive: true, role: { in: ['ADMIN', 'MANAGER'] } },
      }),
    );
    expect(prisma.appNotification.create).toHaveBeenCalledTimes(2);
  });

  it('markRead returns 404 for a notification the user does not own', async () => {
    prisma.appNotification.findFirst.mockResolvedValue(null);
    const err: any = await service.markRead('u1', 'nope').catch((e) => e);
    expect(err.getStatus()).toBe(404);
    expect(prisma.appNotification.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'nope', userId: 'u1' } }),
    );
  });

  it('list clamps the limit to 1..100', async () => {
    await service.list('u1', 5000);
    expect(prisma.appNotification.findMany).toHaveBeenLastCalledWith(
      expect.objectContaining({ take: 100 }),
    );
    await service.list('u1', -3);
    expect(prisma.appNotification.findMany).toHaveBeenLastCalledWith(
      expect.objectContaining({ take: 1 }),
    );
  });
});
