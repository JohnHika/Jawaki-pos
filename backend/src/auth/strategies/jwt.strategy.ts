import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import { JwtPayload } from '../auth.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { PermissionsService } from '../../permissions/permissions.service';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  private readonly logger = new Logger(JwtStrategy.name);

  constructor(
    private configService: ConfigService,
    private prisma: PrismaService,
    private permissionsService: PermissionsService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: configService.get<string>('JWT_SECRET'),
    });
  }

  async validate(payload: JwtPayload) {
    const user = await this.prisma.user.findUnique({
      where: { id: payload.sub },
      select: {
        id: true,
        isActive: true,
        role: true,
        tenantId: true,
      },
    });

    if (!user || !user.isActive) {
      throw new UnauthorizedException('User not found or inactive');
    }

    // Re-derived fresh on every request, same as role/tenantId above —
    // an admin editing a role or a user's overrides takes effect on the
    // user's very next request, no re-login required.
    //
    // Fails soft: a transient DB hiccup here must not turn into a 401 on
    // every single authenticated endpoint in the app (this runs on EVERY
    // request). PermissionsGuard-protected routes still correctly deny
    // access with an empty permission set; unguarded routes (most of the
    // app, e.g. product/category reads) keep working exactly as before
    // this field existed.
    let permissions: string[] = [];
    try {
      permissions = await this.permissionsService.getEffectivePermissions(payload.sub);
    } catch (error) {
      this.logger.warn(
        `Failed to resolve permissions for user ${payload.sub}, continuing with no permissions for this request: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }

    return {
      sub: payload.sub,
      email: payload.email,
      role: payload.role,
      tenantId: payload.tenantId,
      branchId: payload.branchId,
      deviceId: payload.deviceId,
      permissions,
    };
  }
}
