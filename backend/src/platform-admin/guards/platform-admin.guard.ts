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
import { PLATFORM_ADMIN_PUBLIC_KEY } from '../decorators/platform-admin-public.decorator';

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
}

export interface PlatformAdminActor {
  id: string;
  email: string;
}

/**
 * Accepts ONLY platform-admin tokens (type='platform'). Tenant-user JWTs —
 * even valid ones signed with the same secret — are rejected here, because
 * the platform control plane is for Jawaki staff, never merchants.
 */
@Injectable()
export class PlatformAdminGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(PLATFORM_ADMIN_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
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

    request.platformAdmin = { id: payload.sub, email: payload.email };
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