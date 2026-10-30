import {
  BadRequestException,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { JwtService } from '@nestjs/jwt';
import { DesktopLinkService } from './desktop-link.service';

/**
 * Unit tests for the desktop sign-in (QR / approval) challenge service.
 * An in-memory store stands in for Prisma so no database is needed.
 */
describe('DesktopLinkService', () => {
  const buildService = () => {
    const store = new Map<string, any>();

    const prisma: any = {
      desktopLinkChallenge: {
        create: jest.fn(async ({ data }: any) => {
          const row = {
            id: data.id,
            code: data.code,
            claimSecretHash: data.claimSecretHash,
            status: 'pending',
            mode: data.mode,
            desktopName: data.desktopName,
            userId: null,
            branchId: null,
            accessTokenHash: null,
            refreshTokenHash: null,
            attempts: 0,
            expiresAt: data.expiresAt,
            approvedAt: null,
            claimedAt: null,
            createdAt: new Date(),
            user: null,
          };
          store.set(data.id, row);
          return row;
        }),
        findUnique: jest.fn(async ({ where }: any) => store.get(where.id) ?? null),
        findFirst: jest.fn(async ({ where }: any) => {
          if (where.id) return store.get(where.id) ?? null;
          for (const row of store.values()) {
            const statusOk = where.status ? row.status === where.status : true;
            const expiryOk = where.expiresAt?.gt
              ? row.expiresAt > where.expiresAt.gt
              : true;
            if (row.code === where.code && statusOk && expiryOk) return row;
          }
          return null;
        }),
        update: jest.fn(async ({ where, data: patch }: any) => {
          const row = store.get(where.id);
          if (!row) throw new Error('row missing');
          const applied = { ...patch };
          if (applied.attempts && typeof applied.attempts === 'object') {
            row.attempts = (row.attempts ?? 0) + (applied.attempts.increment ?? 1);
            delete applied.attempts;
          }
          Object.assign(row, applied);
          // Emulate Prisma's relation include: populate the approver.
          if (row.userId) {
            row.user = {
              id: row.userId,
              email: 'owner@shop.com',
              firstName: 'Ada',
              lastName: 'Obi',
              role: 'ADMIN',
              tenantId: 'tenant-1',
              pin: await bcrypt.hash('4321', 4),
              isActive: true,
              tenant: { slug: 'ada-shop' },
              branches: [{ branchId: 'branch-1', isPrimary: true }],
            };
          }
          return row;
        }),
        updateMany: jest.fn(async ({ where, data }: any) => {
          const row = store.get(where.id);
          if (!row || row.status !== where.status) return { count: 0 };
          Object.assign(row, data);
          return { count: 1 };
        }),
      },
      user: {
        findUnique: jest.fn(async ({ where }: any) => ({
          id: where.id,
          pin: await bcrypt.hash('4321', 4),
          isActive: true,
        })),
      },
      refreshToken: {
        create: jest.fn(async ({ data }: any) => data),
      },
    };

    const jwtService = {
      sign: jest.fn().mockReturnValue('access.jwt'),
    } as unknown as JwtService;
    const config = { get: jest.fn((_key: string, def?: string) => def) };
    const notifications = { sendToUser: jest.fn().mockResolvedValue(undefined) };
    const permissionsService = {
      getEffectivePermissions: jest.fn().mockResolvedValue(['sales.view']),
    };

    const service = new DesktopLinkService(
      prisma,
      jwtService,
      config as any,
      notifications as any,
      permissionsService as any,
    );
    return { service, prisma, store, notifications };
  };

  it('start returns a 6-digit code and a QR payload holding the claim secret', async () => {
    const { service } = buildService();
    const s = await service.start('Shop PC');
    expect(s.code).toMatch(/^\d{6}$/);
    const parsed = JSON.parse(s.qr);
    expect(parsed).toMatchObject({ v: 1, id: s.linkId, code: s.code });
    expect(typeof parsed.s).toBe('string');
  });

  it('scanApprove then claim returns tokens and marks the challenge claimed', async () => {
    const { service, prisma } = buildService();
    const s = await service.start('Shop PC');

    await service.scanApprove('user-1', {
      payload: s.qr,
      mode: 'approval',
      deviceName: 'Pixel 8',
    });

    const status = await service.status(s.linkId);
    expect(status.status).toBe('approved');

    const secret = JSON.parse(s.qr).s;
    const claimed = await service.claim(s.linkId, secret);
    expect(claimed.accessToken).toBe('access.jwt');
    expect(claimed.refreshToken).toBeTruthy();
    expect(claimed.user.tenantId).toBe('tenant-1');
    expect(claimed.user.permissions).toEqual(['sales.view']);
    expect(prisma.refreshToken.create).toHaveBeenCalledTimes(1);

    // One challenge, one session: re-claiming must fail.
    await expect(service.claim(s.linkId, secret)).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect((await service.status(s.linkId)).status).toBe('claimed');
  });

  it('claim with the wrong secret is rejected and burns an attempt', async () => {
    const { service, store } = buildService();
    const s = await service.start('Shop PC');
    await service.scanApprove('user-1', { payload: s.qr, mode: 'approval' });

    await expect(service.claim(s.linkId, 'wrong-secret')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(store.get(s.linkId).attempts).toBe(1);
    // The challenge is still redeemable with the true secret.
    await expect(
      service.claim(s.linkId, JSON.parse(s.qr).s),
    ).resolves.toBeTruthy();
  });

  it('claim before approval fails with a clear error', async () => {
    const { service } = buildService();
    const s = await service.start('Shop PC');
    await expect(
      service.claim(s.linkId, JSON.parse(s.qr).s),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('claim on an unknown link id is not found', async () => {
    const { service } = buildService();
    await expect(service.claim('nope', 'secret')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('codeApprove resolves a pending challenge by short code', async () => {
    const { service } = buildService();
    const s = await service.start('Shop PC');
    await service.codeApprove('user-1', {
      code: s.code,
      mode: 'approval',
      deviceName: 'Pixel 8',
    });
    expect((await service.status(s.linkId)).status).toBe('approved');
  });

  it('codeApprove with an unknown code is not found', async () => {
    const { service } = buildService();
    await expect(
      service.codeApprove('user-1', { code: '000000', mode: 'approval' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('deny marks the challenge denied so the desktop poll sees it', async () => {
    const { service } = buildService();
    const s = await service.start('Shop PC');
    await service.codeApprove('user-1', {
      code: s.code,
      decision: 'deny',
    });
    expect((await service.status(s.linkId)).status).toBe('denied');
  });

  it('pin mode requires the approver PIN and rejects a wrong one', async () => {
    const { service } = buildService();
    const s = await service.start('Shop PC');

    await expect(
      service.codeApprove('user-1', { code: s.code, mode: 'pin' }),
    ).rejects.toBeInstanceOf(BadRequestException);

    await expect(
      service.codeApprove('user-1', { code: s.code, mode: 'pin', pin: '0000' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);

    // Challenge survives wrong-PIN attempts while it is still pending.
    await service.codeApprove('user-1', { code: s.code, mode: 'pin', pin: '4321' });
    expect((await service.status(s.linkId)).status).toBe('approved');
  });

  it('expired challenges cannot be approved', async () => {
    const { service, store } = buildService();
    const s = await service.start('Shop PC');
    const row = store.get(s.linkId);
    row.expiresAt = new Date(Date.now() - 1000);

    // findFirst filters on expiresAt gt now, so a stale row reads as missing.
    await expect(
      service.codeApprove('user-1', { code: s.code, mode: 'approval' }),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(row.status).toBe('pending');
  });
});
