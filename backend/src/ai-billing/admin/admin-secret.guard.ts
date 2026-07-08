import { Injectable, CanActivate, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * This admin panel spans ALL tenants (lists/approves AI billing payments
 * platform-wide), so it can't use the per-tenant PermissionsGuard — there
 * is no tenant to scope it to. Gated instead by a shared secret the
 * operator passes as a header, checked against ADMIN_API_SECRET.
 */
@Injectable()
export class AdminSecretGuard implements CanActivate {
  constructor(private configService: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const expected = this.configService.get<string>('ADMIN_API_SECRET');
    if (!expected) {
      throw new UnauthorizedException('Admin panel is not configured');
    }

    const request = context.switchToHttp().getRequest();
    const provided = request.headers['x-admin-secret'];

    if (provided !== expected) {
      throw new UnauthorizedException('Invalid admin secret');
    }

    return true;
  }
}
