import { ExecutionContext, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { PlatformAdminGuard } from './platform-admin.guard';

describe('PlatformAdminGuard', () => {
  const buildGuard = () => {
    const jwtService = { verify: jest.fn() } as unknown as JwtService;
    const configService = { get: jest.fn().mockReturnValue('test-secret') } as any;
    const reflector = { getAllAndOverride: jest.fn().mockReturnValue(false) } as any;
    return { guard: new PlatformAdminGuard(jwtService, configService, reflector), jwtService, reflector };
  };

  const buildContext = (authorization?: string) => {
    const request: any = { headers: {} };
    if (authorization !== undefined) request.headers.authorization = authorization;
    return {
      switchToHttp: () => ({ getRequest: () => request }),
      getHandler: () => undefined,
      getClass: () => undefined,
    } as unknown as ExecutionContext;
  };

  it('accepts a valid platform JWT and exposes the platform admin actor', async () => {
    const { guard, jwtService } = buildGuard();
    const payload = { sub: 'admin-1', email: 'a@b.co', role: 'PLATFORM_ADMIN', type: 'platform' };
    jwtService.verify = jest.fn().mockReturnValue(payload);

    const context = buildContext('Bearer platform-token');
    const result = await guard.canActivate(context);

    expect(result).toBe(true);
    expect(jwtService.verify).toHaveBeenCalledWith(
      'platform-token',
      expect.objectContaining({ secret: 'test-secret' }),
    );
    const request = context.switchToHttp().getRequest();
    expect(request.platformAdmin).toEqual({ id: 'admin-1', email: 'a@b.co' });
  });

  it('rejects a tenant JWT (no type discriminator) with ForbiddenException', async () => {
    const { guard, jwtService } = buildGuard();
    // A valid tenant token signed with the same secret: verifies fine, but
    // has no type field, so the guard must still reject it.
    jwtService.verify = jest.fn().mockReturnValue({
      sub: 'user-1',
      email: 'cashier@tenant.co',
      role: 'ADMIN',
      tenantId: 'tenant-1',
    });

    await expect(guard.canActivate(buildContext('Bearer tenant-token'))).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('rejects a JWT with a non-platform type', async () => {
    const { guard, jwtService } = buildGuard();
    jwtService.verify = jest.fn().mockReturnValue({ sub: 'x', type: 'tenant' });

    await expect(guard.canActivate(buildContext('Bearer other-token'))).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('rejects an invalid/expired token with UnauthorizedException', async () => {
    const { guard, jwtService } = buildGuard();
    jwtService.verify = jest.fn().mockImplementation(() => {
      throw new Error('jwt expired');
    });

    await expect(guard.canActivate(buildContext('Bearer bad-token'))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects a request with no Authorization header', async () => {
    const { guard } = buildGuard();
    await expect(guard.canActivate(buildContext(undefined))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects a non-Bearer Authorization header', async () => {
    const { guard } = buildGuard();
    await expect(guard.canActivate(buildContext('Basic abc'))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('allows public routes (login) without a token', async () => {
    const { guard, reflector } = buildGuard();
    reflector.getAllAndOverride = jest.fn().mockReturnValue(true);

    await expect(guard.canActivate(buildContext(undefined))).resolves.toBe(true);
  });
});