import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../common/prisma/prisma.service';
import { PLATFORM_ADMIN_PUBLIC_KEY } from '../decorators/platform-admin-public.decorator';
import {
  PLATFORM_ALLOW_PASSWORD_CHANGE_KEY,
  PLATFORM_AUTHENTICATED_KEY,
  PLATFORM_PERMISSIONS_KEY,
} from '../decorators/platform-permission.decorator';
import { PlatformPermission, permissionsForRole } from '../rbac/platform-permissions';

/**
 * JWT payload shape for platform admins. Signed with the SAME JWT_SECRET as
 * tenant-user tokens but with a distinct `type: 'platform'` discriminator so
 * the two token families can never be confused.
 */
export interface PlatformAdminJwtPayload {
  sub: string;
  email: string;
  role: 'PLATFORM_ADMIN';
  type: 'platform';
  /** Session id: lets a revoke take effect immediately instead of at token expiry. */
  sid: string;
}

export interface PlatformAdminActor {
  id: string;
  email: string;
  name: string;
  role: string;
  permissions: string[];
  sessionId: string;
}

/**
 * Accepts ONLY platform-admin tokens (type='platform'). Tenant-user JWTs —
 * even valid ones signed with the same secret — are rejected here, because
 * the platform control plane is for Counterbase staff, never merchants.
 *
 * Every request re-checks the live session and staff record, so disabling a
 * staff member or revoking a session cuts access immediately. Routes with no
 * permission annotation are denied (fail closed).
 */
@Injectable()
export class PlatformAdminGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const targets = [context.getHandler(), context.getClass()];
    const isPublic = this.reflector.getAllAndOverride<boolean>(PLATFORM_ADMIN_PUBLIC_KEY, targets);
    if (isPublic) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const token = this.extractBearerToken(request);
    if (!token) {
      throw new UnauthorizedException('Platform admin authentication required');
    }

    let payload: PlatformAdminJwtPayload;
    try {
      payload = this.jwtService.verify<PlatformAdminJwtPayload>(token, {
        secret: this.configService.get<string>('JWT_SECRET'),
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired platform admin token');
    }

    // Hard discriminator: a tenant JWT (no `type`, or type !== 'platform')
    // must be rejected even though it verifies against the same secret.
    if (payload?.type !== 'platform' || payload?.role !== 'PLATFORM_ADMIN') {
      throw new ForbiddenException('Platform admin access only');
    }
    if (!payload.sid) {
      throw new UnauthorizedException('Session expired. Please sign in again.');
    }

    const session = await this.prisma.platformAdminSession.findUnique({
      where: { id: payload.sid },
      include: { admin: true },
    });
    const now = new Date();
    if (
      !session ||
      session.adminId !== payload.sub ||
      session.revokedAt ||
      session.expiresAt <= now ||
      session.admin.status !== 'ACTIVE'
    ) {
      throw new UnauthorizedException('Session expired. Please sign in again.');
    }
    if (session.admin.lockedUntil && session.admin.lockedUntil > now) {
      throw new UnauthorizedException('This account is temporarily locked.');
    }

    const admin = session.admin;
    const allowPasswordChange = this.reflector.getAllAndOverride<boolean>(
      PLATFORM_ALLOW_PASSWORD_CHANGE_KEY,
      targets,
    );
    if (admin.mustChangePassword && !allowPasswordChange) {
      throw new ForbiddenException({
        statusCode: 403,
        error: 'Forbidden',
        message: 'You must change your password before continuing.',
        code: 'PASSWORD_CHANGE_REQUIRED',
      });
    }

    const permissions = permissionsForRole(admin.role);
    const required = this.reflector.getAllAndOverride<PlatformPermission[]>(
      PLATFORM_PERMISSIONS_KEY,
      targets,
    );
    const authenticatedOnly = this.reflector.getAllAndOverride<boolean>(
      PLATFORM_AUTHENTICATED_KEY,
      targets,
    );

    if (required?.length) {
      const missing = required.filter((p) => !permissions.includes(p));
      if (missing.length) {
        throw new ForbiddenException({
          statusCode: 403,
          error: 'Forbidden',
          message: 'Your role does not allow this action.',
          code: 'MISSING_PERMISSION',
          missing,
        });
      }
    } else if (!authenticatedOnly) {
      // Fail closed: an unannotated route is never reachable.
      throw new ForbiddenException('This route has no access policy.');
    }

    request.platformAdmin = {
      id: admin.id,
      email: admin.email,
      name: admin.name,
      role: admin.role,
      permissions,
      sessionId: session.id,
    } as PlatformAdminActor;
    return true;
  }

  private extractBearerToken(request: any): string | undefined {
    const header = request?.headers?.authorization;
    if (!header || typeof header !== 'string') return undefined;
    const [scheme, token] = header.split(' ');
    if (scheme?.toLowerCase() !== 'bearer' || !token) return undefined;
    return token;
  }
}
