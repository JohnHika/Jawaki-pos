import {
  BadRequestException,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { createHash } from 'crypto';
import {
  CHALLENGE_TTL_MS,
  CLAIM_WINDOW_MS,
  DesktopLinkService,
  originFromRequest,
} from './desktop-link.service';

const sha256 = (text: string) => createHash('sha256').update(text).digest('hex');

/**
 * Computer sign-in approved on a phone. An in-memory store stands in for
 * Prisma so no database is needed.
 */
describe('DesktopLinkService', () => {
  const VERIFIER = 'v'.repeat(20) + '-computer-only-verifier-0123456789';
  const SHOP_WIFI = { ip: '41.90.10.20', city: 'Nairobi', country: 'KE' };
  const MOBILE_DATA = { ip: '105.160.1.2' };

  const build = async (opts: { pin?: string; recentPrompts?: number } = {}) => {
    const store = new Map<string, any>();
    const computers = new Map<string, any>();
    const pinHash = opts.pin ? await bcrypt.hash(opts.pin, 4) : null;

    const matches = (row: any, where: any): boolean =>
      Object.entries(where).every(([key, cond]: [string, any]) => {
        if (cond && typeof cond === 'object' && 'gt' in cond) {
          return row[key] > cond.gt;
        }
        return row[key] === cond;
      });

    const prisma: any = {
      desktopLinkChallenge: {
        create: jest.fn(async ({ data }: any) => {
          const row = {
            status: 'pending',
            userId: null,
            branchId: null,
            approverIp: null,
            attempts: 0,
            approvedAt: null,
            claimedAt: null,
            createdAt: new Date(),
            ...data,
          };
          store.set(data.id, row);
          return row;
        }),
        findUnique: jest.fn(async ({ where, select }: any) => {
          const row = store.get(where.id);
          if (!row) return null;
          if (select?.user) {
            return { ...row, user: row.userId ? { firstName: 'Ada' } : null };
          }
          return row;
        }),
        findFirst: jest.fn(async ({ where }: any) => {
          for (const row of store.values()) {
            if (matches(row, where)) return row;
          }
          return null;
        }),
        update: jest.fn(async ({ where, data }: any) => {
          const row = store.get(where.id);
          if (data.attempts?.increment) {
            row.attempts += data.attempts.increment;
          }
          return row;
        }),
        updateMany: jest.fn(async ({ where, data }: any) => {
          let count = 0;
          for (const row of store.values()) {
            if (matches(row, where)) {
              Object.assign(row, data);
              count++;
            }
          }
          return { count };
        }),
      },
      user: {
        findUnique: jest.fn(async () => ({ pin: pinHash, isActive: true })),
        findMany: jest.fn(async ({ where }: any) =>
          where.email === 'ada@shop.co' ? [{ id: 'owner-1', tenantId: 'tenant-1' }] : [],
        ),
      },
      appNotification: {
        count: jest.fn(async () => opts.recentPrompts ?? 0),
      },
      linkedComputer: {
        findMany: jest.fn(async ({ where }: any) =>
          [...computers.values()].filter(
            (row) =>
              (!where.userId || row.userId === where.userId) &&
              (!where.id || row.id === where.id) &&
              row.revokedAt === null,
          ),
        ),
        findFirst: jest.fn(async ({ where }: any) => {
          const row = computers.get(where.id);
          return row && row.userId === where.userId && row.revokedAt === null ? row : null;
        }),
        updateMany: jest.fn(async ({ where, data }: any) => {
          let count = 0;
          for (const id of where.id.in as string[]) {
            Object.assign(computers.get(id), data);
            count++;
          }
          return { count };
        }),
      },
    };

    const authService: any = {
      issueLinkedSession: jest.fn(async (userId: string, options: any) => ({
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresIn: 900,
        user: { id: userId, branchId: options.branchId },
      })),
    };
    const notifications: any = {
      sendToUser: jest.fn(async () => undefined),
    };

    const service = new DesktopLinkService(prisma, authService, notifications);
    return { service, store, authService, notifications, computers };
  };

  const linked = (id: string, userId: string, over: Record<string, any> = {}) => ({
    id,
    userId,
    desktopName: 'FRONT-DESK',
    platform: 'windows',
    place: 'Nairobi, KE',
    linkedAt: new Date('2026-11-10T08:00:00Z'),
    lastActiveAt: new Date('2026-11-15T09:30:00Z'),
    revokedAt: null,
    ...over,
  });

  const approver = { userId: 'owner-1', branchId: 'branch-main' };

  it('keeps the secret on the computer: the QR only names the request', async () => {
    const { service } = await build();
    const start = await service.start(
      { desktopName: 'FRONT-DESK', platform: 'windows', claimChallenge: sha256(VERIFIER) },
      SHOP_WIFI,
    );

    const qr = JSON.parse(start.qr);
    expect(qr).toEqual({ v: 2, app: 'counterbase', id: start.linkId, code: start.code });
    expect(start.qr).not.toContain(VERIFIER);
    expect(start.code).toMatch(/^\d{6}$/);
    expect(new Date(start.expiresAt).getTime() - Date.now()).toBeLessThanOrEqual(
      CHALLENGE_TTL_MS,
    );
  });

  describe('asking the persons phone', () => {
    it('sends a tap-to-review prompt to that person when the computer says who is signing in', async () => {
      const { service, notifications } = await build();
      const start = await service.start(
        { desktopName: 'FRONT-DESK', claimChallenge: sha256(VERIFIER), hint: 'Ada@Shop.co' },
        SHOP_WIFI,
      );
      expect(notifications.sendToUser).toHaveBeenCalledWith(
        'owner-1',
        expect.objectContaining({
          data: { type: 'desktop_link_request', linkId: start.linkId, payload: start.qr },
        }),
        { tenantId: 'tenant-1' },
      );
    });

    it('answers the computer the same way when nobody has that email', async () => {
      const { service, notifications } = await build();
      const start = await service.start(
        { claimChallenge: sha256(VERIFIER), hint: 'nobody@shop.co' },
        SHOP_WIFI,
      );
      expect(notifications.sendToUser).not.toHaveBeenCalled();
      expect(start.code).toMatch(/^\d{6}$/);
    });

    it('stops prompting a person who was already asked three times in ten minutes', async () => {
      const { service, notifications } = await build({ recentPrompts: 3 });
      const start = await service.start(
        { claimChallenge: sha256(VERIFIER), hint: 'ada@shop.co' },
        SHOP_WIFI,
      );
      expect(notifications.sendToUser).not.toHaveBeenCalled();
      expect(start.linkId).toBeTruthy();
    });

    it('still gives the computer its code when sending the prompt fails', async () => {
      const { service, notifications } = await build();
      notifications.sendToUser.mockRejectedValue(new Error('push down'));
      const start = await service.start(
        { claimChallenge: sha256(VERIFIER), hint: 'ada@shop.co' },
        SHOP_WIFI,
      );
      expect(start.code).toMatch(/^\d{6}$/);
    });
  });

  it('refuses to start without a claim challenge', async () => {
    const { service } = await build();
    await expect(service.start({ desktopName: 'PC' }, SHOP_WIFI)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('on the same connection: scan, approve, and the computer gets the approver session', async () => {
    const { service, authService, notifications } = await build({ pin: '2468' });
    const start = await service.start(
      { desktopName: 'FRONT-DESK', platform: 'windows', claimChallenge: sha256(VERIFIER) },
      SHOP_WIFI,
    );

    const preview = await service.preview(approver.userId, { payload: start.qr }, SHOP_WIFI);
    expect(preview).toMatchObject({
      linkId: start.linkId,
      desktopName: 'FRONT-DESK',
      platform: 'windows',
      place: 'Nairobi, KE',
      sameNetwork: true,
      pinRequired: false,
    });

    expect((await service.status(start.linkId)).status).toBe('pending');
    const decided = await service.decide(approver, { linkId: start.linkId }, SHOP_WIFI);
    expect(decided).toMatchObject({ status: 'approved', approvedBy: 'Ada' });

    const session = await service.claim({
      linkId: start.linkId,
      verifier: VERIFIER,
      deviceId: 'pc-device-1',
    });
    expect(session.accessToken).toBe('access');
    expect(authService.issueLinkedSession).toHaveBeenCalledWith('owner-1', {
      branchId: 'branch-main',
      deviceId: 'pc-device-1',
      // What the phone approved is kept, so the phone can list and revoke it.
      computer: {
        desktopName: 'FRONT-DESK',
        platform: 'windows',
        place: 'Nairobi, KE',
        ip: SHOP_WIFI.ip,
      },
    });
    expect(notifications.sendToUser).toHaveBeenCalledWith(
      'owner-1',
      expect.objectContaining({ title: 'Computer signed in' }),
    );
    expect((await service.status(start.linkId)).status).toBe('claimed');

    await expect(
      service.claim({ linkId: start.linkId, verifier: VERIFIER }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('a photo of the QR is not enough to take the sign-in', async () => {
    const { service, store } = await build();
    const start = await service.start({ claimChallenge: sha256(VERIFIER) }, SHOP_WIFI);
    await service.decide(approver, { linkId: start.linkId }, SHOP_WIFI);

    for (let i = 0; i < 5; i++) {
      await expect(
        service.claim({ linkId: start.linkId, verifier: `${start.qr}-guess-${i}-padding-padding` }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    }
    expect(store.get(start.linkId).attempts).toBe(5);
    await expect(
      service.claim({ linkId: start.linkId, verifier: VERIFIER }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('asks for the PIN when the computer is on another connection', async () => {
    const { service } = await build({ pin: '2468' });
    const start = await service.start({ claimChallenge: sha256(VERIFIER) }, SHOP_WIFI);

    const preview = await service.preview(approver.userId, { code: start.code }, MOBILE_DATA);
    expect(preview).toMatchObject({ sameNetwork: false, pinRequired: true });

    await expect(
      service.decide(approver, { linkId: start.linkId }, MOBILE_DATA),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.decide(approver, { linkId: start.linkId, pin: '1111' }, MOBILE_DATA),
    ).rejects.toThrow('Wrong PIN');
    const decided = await service.decide(
      approver,
      { linkId: start.linkId, pin: '2468' },
      MOBILE_DATA,
    );
    expect(decided.status).toBe('approved');
  });

  it('a refused request cannot be claimed', async () => {
    const { service, authService } = await build();
    const start = await service.start({ claimChallenge: sha256(VERIFIER) }, SHOP_WIFI);
    await expect(
      service.claim({ linkId: start.linkId, verifier: VERIFIER }),
    ).rejects.toThrow('The phone has not approved this sign-in yet');

    await service.decide(approver, { linkId: start.linkId, decision: 'deny' }, SHOP_WIFI);
    expect((await service.status(start.linkId)).status).toBe('denied');
    await expect(
      service.claim({ linkId: start.linkId, verifier: VERIFIER }),
    ).rejects.toThrow('The sign-in was refused on the phone');
    await expect(
      service.decide(approver, { linkId: start.linkId }, SHOP_WIFI),
    ).rejects.toThrow('already answered');
    expect(authService.issueLinkedSession).not.toHaveBeenCalled();
  });

  it('an expired request is gone for the phone and the computer', async () => {
    const { service, store } = await build();
    const start = await service.start({ claimChallenge: sha256(VERIFIER) }, SHOP_WIFI);
    store.get(start.linkId).expiresAt = new Date(Date.now() - 1000);

    expect((await service.status(start.linkId)).status).toBe('expired');
    await expect(
      service.preview(approver.userId, { code: start.code }, SHOP_WIFI),
    ).rejects.toThrow('No computer is waiting with that code');
    await expect(
      service.preview(approver.userId, { payload: start.qr }, SHOP_WIFI),
    ).rejects.toThrow('This code has expired');
    await expect(
      service.decide(approver, { linkId: start.linkId }, SHOP_WIFI),
    ).rejects.toThrow('expired');
  });

  // A 404 on the phone's signed-in route reaches it as a 401 (dead session),
  // so a request that is no longer waiting must answer with a plain message.
  it('scanning again after approving says so, and is never a not-found', async () => {
    const { service } = await build();
    const start = await service.start({ claimChallenge: sha256(VERIFIER) }, SHOP_WIFI);
    await service.decide(approver, { linkId: start.linkId }, SHOP_WIFI);

    const again = service.preview(approver.userId, { payload: start.qr }, SHOP_WIFI);
    await expect(again).rejects.toBeInstanceOf(BadRequestException);
    await expect(again).rejects.toThrow('You approved this computer');

    // Someone else typing the same code learns nothing about it.
    await expect(
      service.preview('someone-else', { code: start.code }, SHOP_WIFI),
    ).rejects.toThrow('No computer is waiting with that code');

    await service.claim({ linkId: start.linkId, verifier: VERIFIER });
    await expect(
      service.preview(approver.userId, { payload: start.qr }, SHOP_WIFI),
    ).rejects.toThrow('already signed in');
  });

  it('approving in the last seconds of a code still signs the computer in', async () => {
    const { service, store } = await build();
    const start = await service.start({ claimChallenge: sha256(VERIFIER) }, SHOP_WIFI);
    const row = store.get(start.linkId);
    row.expiresAt = new Date(Date.now() + 1000);

    await service.decide(approver, { linkId: start.linkId }, SHOP_WIFI);
    expect(row.expiresAt.getTime()).toBeGreaterThan(Date.now() + CLAIM_WINDOW_MS - 5000);
    expect((await service.status(start.linkId)).status).toBe('approved');
    await expect(
      service.claim({ linkId: start.linkId, verifier: VERIFIER }),
    ).resolves.toMatchObject({ accessToken: 'access' });
  });

  it('an approval the computer did not collect in time reads as expired', async () => {
    const { service, store } = await build();
    const start = await service.start({ claimChallenge: sha256(VERIFIER) }, SHOP_WIFI);
    await service.decide(approver, { linkId: start.linkId }, SHOP_WIFI);
    store.get(start.linkId).expiresAt = new Date(Date.now() - 1000);

    expect((await service.status(start.linkId)).status).toBe('expired');
  });

  it('rejects QR codes that are not a Counterbase sign-in', async () => {
    const { service } = await build();
    const oldDraft = JSON.stringify({ v: 1, id: 'x', code: '123456', s: 'secret' });
    await expect(
      service.preview(approver.userId, { payload: oldDraft }, SHOP_WIFI),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.preview(approver.userId, { payload: 'https://example.com/pay' }, SHOP_WIFI),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  describe('linked computers', () => {
    it('lists only this person\'s computers, newest activity first, marking the asking one', async () => {
      const { service, computers } = await build();
      computers.set('c1', linked('c1', 'owner-1'));
      computers.set(
        'c2',
        linked('c2', 'owner-1', { desktopName: 'BACK-OFFICE', lastActiveAt: new Date('2026-11-16T10:00:00Z') }),
      );
      computers.set('c3', linked('c3', 'someone-else'));
      computers.set('c4', linked('c4', 'owner-1', { revokedAt: new Date() }));

      const list = await service.listComputers('owner-1', 'c1');

      expect(list.map((c) => c.id).sort()).toEqual(['c1', 'c2']);
      expect(list.find((c) => c.id === 'c1')).toMatchObject({
        name: 'FRONT-DESK',
        platform: 'windows',
        place: 'Nairobi, KE',
        isThisDevice: true,
      });
      expect(list.find((c) => c.id === 'c2')?.isThisDevice).toBe(false);
    });

    it('revoking ends that computer and no other', async () => {
      const { service, computers } = await build();
      computers.set('c1', linked('c1', 'owner-1'));
      computers.set('c2', linked('c2', 'owner-1'));

      expect(await service.revokeComputer('owner-1', 'c1')).toEqual({ revoked: 1 });

      expect(computers.get('c1').revokedAt).toBeInstanceOf(Date);
      expect(computers.get('c2').revokedAt).toBeNull();
      // It leaves the list at once.
      expect((await service.listComputers('owner-1')).map((c) => c.id)).toEqual(['c2']);
    });

    it('cannot revoke a computer that belongs to someone else or is already gone', async () => {
      const { service, computers } = await build();
      computers.set('c3', linked('c3', 'someone-else'));
      computers.set('c4', linked('c4', 'owner-1', { revokedAt: new Date() }));

      await expect(service.revokeComputer('owner-1', 'c3')).rejects.toBeInstanceOf(BadRequestException);
      await expect(service.revokeComputer('owner-1', 'c4')).rejects.toBeInstanceOf(BadRequestException);
      await expect(service.revokeComputer('owner-1', 'nope')).rejects.toBeInstanceOf(BadRequestException);
      expect(computers.get('c3').revokedAt).toBeNull();
    });

    it('sign out all ends every computer of this person and nobody else\'s', async () => {
      const { service, computers } = await build();
      computers.set('c1', linked('c1', 'owner-1'));
      computers.set('c2', linked('c2', 'owner-1'));
      computers.set('c3', linked('c3', 'someone-else'));

      expect(await service.revokeAllComputers('owner-1')).toEqual({ revoked: 2 });

      expect(computers.get('c1').revokedAt).toBeInstanceOf(Date);
      expect(computers.get('c2').revokedAt).toBeInstanceOf(Date);
      expect(computers.get('c3').revokedAt).toBeNull();
      expect(await service.revokeAllComputers('owner-1')).toEqual({ revoked: 0 });
    });
  });

  it('reads the caller address and place from the proxy headers', () => {
    expect(
      originFromRequest({
        headers: {
          'x-forwarded-for': '41.90.10.20, 10.0.0.1',
          'x-vercel-ip-city': 'Nairobi%20West',
          'x-vercel-ip-country': 'KE',
        },
      }),
    ).toEqual({ ip: '41.90.10.20', city: 'Nairobi West', country: 'KE' });
  });
});
