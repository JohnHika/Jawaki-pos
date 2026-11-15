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
        tenant: { select: { activationStatus: true } },
      },
    });

    if (!user || !user.isActive) {
      throw new UnauthorizedException('User not found or inactive');
    }

    // A computer the owner signed out from the phone stops working at its next
    // request, not when its 15-minute access token runs out.
    if (payload.sid) await this.assertComputerStillLinked(payload.sid, payload.sub);

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
      role: user.role,
      tenantId: user.tenantId,
      branchId: payload.branchId,
      deviceId: payload.deviceId,
      sid: payload.sid,
      permissions,
      activationStatus: user.tenant.activationStatus,
    };
  }

  private async assertComputerStillLinked(id: string, userId: string): Promise<void> {
    const computer = await this.prisma.linkedComputer.findUnique({
      where: { id },
      select: { userId: true, revokedAt: true, lastActiveAt: true },
    });
    if (!computer || computer.userId !== userId || computer.revokedAt) {
      throw new UnauthorizedException('This computer was signed out from your phone');
    }
    // "Last active" on the phone's list; once in a while, not on every request.
    if (Date.now() - computer.lastActiveAt.getTime() > LAST_ACTIVE_EVERY_MS) {
      this.prisma.linkedComputer
        .updateMany({ where: { id, revokedAt: null }, data: { lastActiveAt: new Date() } })
        .catch(() => undefined);
    }
  }
}

const LAST_ACTIVE_EVERY_MS = 5 * 60 * 1000;
