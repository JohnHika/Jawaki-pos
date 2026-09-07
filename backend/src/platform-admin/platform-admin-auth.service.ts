import { Injectable, Logger, OnModuleInit, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../common/prisma/prisma.service';
import { PlatformAdminJwtPayload } from './guards/platform-admin.guard';

const BCRYPT_ROUNDS = 10;

/**
 * Seeds the first platform admin from PLATFORM_ADMIN_EMAIL /
 * PLATFORM_ADMIN_PASSWORD on boot when the table is empty. The password is
 * read from env, hashed, and never logged or returned.
 */
@Injectable()
export class PlatformAdminBootstrapService implements OnModuleInit {
  private readonly logger = new Logger(PlatformAdminBootstrapService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

  async onModuleInit(): Promise<void> {
    try {
      const email = this.configService.get<string>('PLATFORM_ADMIN_EMAIL');
      const password = this.configService.get<string>('PLATFORM_ADMIN_PASSWORD');

      if (!email || !password) {
        this.logger.warn(
          'PLATFORM_ADMIN_EMAIL/PLATFORM_ADMIN_PASSWORD not set — no platform admin seeded',
        );
        return;
      }

      const existing = await this.prisma.platformAdmin.findFirst({ select: { id: true } });
      if (existing) {
        return; // Table already has admins; nothing to do.
      }

      const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);
      await this.prisma.platformAdmin.create({
        data: { email, passwordHash, name: 'Platform Owner' },
        select: { id: true },
      });
      this.logger.log(`Seeded platform admin account ${email}`);
    } catch (error) {
      // Never block app boot on seeding; log and continue.
      this.logger.error(
        `Platform admin bootstrap failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
}

@Injectable()
export class PlatformAdminAuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  async login(email: string, password: string) {
    const admin = await this.prisma.platformAdmin.findUnique({
      where: { email: email.toLowerCase() },
    });
    const passwordValid =
      admin?.passwordHash != null && (await bcrypt.compare(password, admin.passwordHash));
    if (!admin || !passwordValid) {
      // Same generic error for unknown email and wrong password.
      throw new UnauthorizedException('Invalid email or password');
    }

    const payload: PlatformAdminJwtPayload = {
      sub: admin.id,
      email: admin.email,
      role: 'PLATFORM_ADMIN',
      type: 'platform',
    };
    const accessToken = this.jwtService.sign(payload, {
      secret: this.configService.get<string>('JWT_SECRET'),
      expiresIn: this.configService.get<string>('JWT_EXPIRES_IN', '15m'),
    });

    return {
      accessToken,
      admin: { id: admin.id, email: admin.email, name: admin.name },
    };
  }

  async findById(id: string) {
    return this.prisma.platformAdmin.findUnique({
      where: { id },
      select: { id: true, email: true, name: true, createdAt: true },
    });
  }
}