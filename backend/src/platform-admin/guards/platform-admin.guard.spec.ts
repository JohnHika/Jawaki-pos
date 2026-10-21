import { ExecutionContext, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  PLATFORM_ADMIN_PUBLIC_KEY,
} from '../decorators/platform-admin-public.decorator';
import {
  PLATFORM_ALLOW_PASSWORD_CHANGE_KEY,
  PLATFORM_AUTHENTICATED_KEY,
  PLATFORM_PERMISSIONS_KEY,
} from '../decorators/platform-permission.decorator';
import { PlatformAdminGuard } from './platform-admin.guard';

type Meta = Partial<Record<string, any>>;

describe('PlatformAdminGuard', () => {
  const future = () => new Date(Date.now() + 3_600_000);

  const buildSession = (overrides: Record<string, any> = {}, adminOverrides: Record<string, any> = {}) => ({
    id: 'sess-1',
    adminId: 'admin-1',
    revokedAt: null,
    expiresAt: future(),
    admin: {
      id: 'admin-1',
      email: 'a@b.co',
      name: 'Alice',
      role: 'FINANCE',
      status: 'ACTIVE',
      lockedUntil: null,
      mustChangePassword: false,
      ...adminOverrides,
    },
    ...overrides,
  });

  const buildGuard = (meta: Meta = {}, session: any = buildSession()) => {
    const jwtService = { verify: jest.fn() } as unknown as JwtService;
    const configService = { get: jest.fn().mockReturnValue('test-secret') } as any;
    const reflector = {
      getAllAndOverride: jest.fn((key: string) => meta[key]),
    } as any;
    const prisma = {
      platformAdminSession: { findUnique: jest.fn().mockResolvedValue(session) },
    } as any;
    return {
      guard: new PlatformAdminGuard(jwtService, configService, reflector, prisma),
      jwtService,
      prisma,
    };
  };

  const buildContext = (authorization?: string) => {
    const request: any = { headers: {} };
    if (authorization !== undefined) request.headers.authorization = authorization;
    return {
      ctx: {
        switchToHttp: () => ({ getRequest: () => request }),
        getHandler: () => undefined,
        getClass: () => undefined,
      } as unknown as ExecutionContext,
      request,
    };
  };

  const goodPayload = {
    sub: 'admin-1',
    email: 'a@b.co',
    role: 'PLATFORM_ADMIN',
    type: 'platform',
    sid: 'sess-1',
  };

  it('accepts a valid token + live session and exposes role and permissions', async () => {
    const { guard, jwtService } = buildGuard({ [PLATFORM_PERMISSIONS_KEY]: ['billing.manage'] });
    jwtService.verify = jest.fn().mockReturnValue(goodPayload);
    const { ctx, request } = buildContext('Bearer platform-token');

    await expect(guard.canActivate(ctx)).resolves.toBe(true);
    expect(jwtService.verify).toHaveBeenCalledWith(
      'platform-token',
      expect.objectContaining({ secret: 'test-secret' }),
    );
    expect(request.platformAdmin).toMatchObject({
      id: 'admin-1',
      email: 'a@b.co',
      role: 'FINANCE',
      sessionId: 'sess-1',
    });
    expect(request.platformAdmin.permissions).toContain('billing.manage');
  });

  it('rejects a tenant JWT (no type discriminator) with ForbiddenException', async () => {
    const { guard, jwtService } = buildGuard({ [PLATFORM_PERMISSIONS_KEY]: ['dashboard.view'] });
    jwtService.verify = jest.fn().mockReturnValue({
      sub: 'user-1',
      email: 'cashier@tenant.co',
      role: 'ADMIN',
      tenantId: 'tenant-1',
    });
    await expect(guard.canActivate(buildContext('Bearer t').ctx)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('rejects a JWT with a non-platform type', async () => {
    const { guard, jwtService } = buildGuard();
    jwtService.verify = jest.fn().mockReturnValue({ sub: 'x', type: 'tenant' });
    await expect(guard.canActivate(buildContext('Bearer t').ctx)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('rejects an invalid/expired token with UnauthorizedException', async () => {
    const { guard, jwtService } = buildGuard();
    jwtService.verify = jest.fn().mockImplementation(() => {
      throw new Error('jwt expired');
    });
    await expect(guard.canActivate(buildContext('Bearer bad').ctx)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects requests with no or non-Bearer Authorization', async () => {
    const { guard } = buildGuard();
    await expect(guard.canActivate(buildContext(undefined).ctx)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    await expect(guard.canActivate(buildContext('Basic abc').ctx)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('allows public routes (login) without a token', async () => {
    const { guard } = buildGuard({ [PLATFORM_ADMIN_PUBLIC_KEY]: true });
    await expect(guard.canActivate(buildContext(undefined).ctx)).resolves.toBe(true);
  });

  it('rejects a token with no session id (pre-session tokens are retired)', async () => {
    const { guard, jwtService } = buildGuard({ [PLATFORM_AUTHENTICATED_KEY]: true });
    jwtService.verify = jest.fn().mockReturnValue({ ...goodPayload, sid: undefined });
    await expect(guard.canActivate(buildContext('Bearer t').ctx)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it.each([
    ['revoked session', { revokedAt: new Date() }, {}],
    ['expired session', { expiresAt: new Date(Date.now() - 1000) }, {}],
    ['disabled staff member', {}, { status: 'DISABLED' }],
    ['locked staff member', {}, { lockedUntil: future() }],
    ['session of another admin', { adminId: 'someone-else' }, {}],
  ])('cuts access immediately for a %s', async (_label, sessionOverrides, adminOverrides) => {
    const { guard, jwtService } = buildGuard(
      { [PLATFORM_AUTHENTICATED_KEY]: true },
      buildSession(sessionOverrides, adminOverrides),
    );
    jwtService.verify = jest.fn().mockReturnValue(goodPayload);
    await expect(guard.canActivate(buildContext('Bearer t').ctx)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects a deleted session', async () => {
    const { guard, jwtService } = buildGuard({ [PLATFORM_AUTHENTICATED_KEY]: true }, null);
    jwtService.verify = jest.fn().mockReturnValue(goodPayload);
    await expect(guard.canActivate(buildContext('Bearer t').ctx)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('forbids a role that lacks the required permission, naming what is missing', async () => {
    const { guard, jwtService } = buildGuard({ [PLATFORM_PERMISSIONS_KEY]: ['team.manage'] });
    jwtService.verify = jest.fn().mockReturnValue(goodPayload); // FINANCE
    await expect(guard.canActivate(buildContext('Bearer t').ctx)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'MISSING_PERMISSION', missing: ['team.manage'] }),
    });
  });

  it('fails closed on a route with no access policy', async () => {
    const { guard, jwtService } = buildGuard({});
    jwtService.verify = jest.fn().mockReturnValue(goodPayload);
    await expect(guard.canActivate(buildContext('Bearer t').ctx)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('blocks everything except password change while a password change is forced', async () => {
    const forced = buildSession({}, { mustChangePassword: true });

    const blocked = buildGuard({ [PLATFORM_PERMISSIONS_KEY]: ['dashboard.view'] }, forced);
    blocked.jwtService.verify = jest.fn().mockReturnValue(goodPayload);
    await expect(blocked.guard.canActivate(buildContext('Bearer t').ctx)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'PASSWORD_CHANGE_REQUIRED' }),
    });

    const allowed = buildGuard(
      { [PLATFORM_AUTHENTICATED_KEY]: true, [PLATFORM_ALLOW_PASSWORD_CHANGE_KEY]: true },
      forced,
    );
    allowed.jwtService.verify = jest.fn().mockReturnValue(goodPayload);
    await expect(allowed.guard.canActivate(buildContext('Bearer t').ctx)).resolves.toBe(true);
  });
});
