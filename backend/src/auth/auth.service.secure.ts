import {
  Injectable,
  UnauthorizedException,
  ConflictException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcryptjs';
import * as crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import {
  LoginDto,
  PinLoginDto,
  RegisterDto,
  RefreshTokenDto,
  LogoutDto,
  ChangePasswordDto,
  SetPinDto,
  AuthResponseDto,
} from './dto/auth.dto';
import { UserRole } from '@prisma/client';

export interface JwtPayload {
  sub: string;
  email: string;
  role: UserRole;
  tenantId: string;
  branchId?: string;
  deviceId?: string;
  jti: string; // JWT ID for token revocation
  iat: number;
  exp: number;
}

export interface DeviceFingerprint {
  userAgent: string;
  ipAddress: string;
  deviceId?: string;
}

@Injectable()
export class AuthService {
  private readonly MAX_LOGIN_ATTEMPTS = 5;
  private readonly LOCKOUT_DURATION_MINUTES = 30;
  private readonly REFRESH_TOKEN_BYTES = 64;

  constructor(
    private prisma: PrismaService,
    private jwtService: JwtService,
    private configService: ConfigService,
    private redisService: RedisService,
  ) {}

  /**
   * Check if user is locked out due to failed login attempts
   */
  private async isUserLockedOut(identifier: string): Promise<boolean> {
    const lockoutKey = `lockout:${identifier}`;
    const attempts = await this.redisService.get(lockoutKey);
    return attempts !== null && parseInt(attempts, 10) >= this.MAX_LOGIN_ATTEMPTS;
  }

  /**
   * Record failed login attempt
   */
  private async recordFailedAttempt(identifier: string): Promise<void> {
    const lockoutKey = `lockout:${identifier}`;
    const attempts = await this.redisService.get(lockoutKey);
    const newAttempts = attempts ? parseInt(attempts, 10) + 1 : 1;

    await this.redisService.set(
      lockoutKey,
      newAttempts.toString(),
      this.LOCKOUT_DURATION_MINUTES * 60,
    );

    if (newAttempts >= this.MAX_LOGIN_ATTEMPTS) {
      // Log security event
      console.warn(`[SECURITY] Account locked: ${identifier} after ${newAttempts} failed attempts`);
    }
  }

  /**
   * Clear failed login attempts on successful login
   */
  private async clearFailedAttempts(identifier: string): Promise<void> {
    await this.redisService.del(`lockout:${identifier}`);
  }

  /**
   * Generate cryptographically secure refresh token
   */
  private generateSecureRefreshToken(): string {
    return crypto.randomBytes(this.REFRESH_TOKEN_BYTES).toString('base64url');
  }

  /**
   * Hash refresh token for storage (prevents DB leak from compromising tokens)
   */
  private hashToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  /**
   * Generate device fingerprint for binding
   */
  private generateDeviceFingerprint(deviceInfo: DeviceFingerprint): string {
    const data = `${deviceInfo.userAgent}:${deviceInfo.ipAddress}:${deviceInfo.deviceId || ''}`;
    return crypto.createHash('sha256').update(data).digest('hex');
  }

  async validateUser(email: string, password: string, tenantId?: string, deviceInfo?: DeviceFingerprint) {
    const identifier = deviceInfo ? `${email}:${deviceInfo.ipAddress}` : email;

    // Check lockout
    if (await this.isUserLockedOut(identifier)) {
      throw new ForbiddenException(`Account temporarily locked. Try again in ${this.LOCKOUT_DURATION_MINUTES} minutes.`);
    }

    const whereClause: any = { email };
    if (tenantId) {
      whereClause.tenantId = tenantId;
    }

    const user = await this.prisma.user.findFirst({
      where: whereClause,
      include: {
        branches: {
          include: {
            branch: true,
          },
        },
      },
    });

    if (!user) {
      await this.recordFailedAttempt(identifier);
      throw new UnauthorizedException('Invalid credentials');
    }

    if (!user.isActive) {
      throw new UnauthorizedException('Account is disabled');
    }

    const isPasswordValid = await bcrypt.compare(password, user.passwordHash);
    if (!isPasswordValid) {
      await this.recordFailedAttempt(identifier);
      throw new UnauthorizedException('Invalid credentials');
    }

    // Clear failed attempts on success
    await this.clearFailedAttempts(identifier);

    return user;
  }

  async login(loginDto: LoginDto, deviceInfo?: DeviceFingerprint): Promise<AuthResponseDto> {
    const user = await this.validateUser(
      loginDto.email,
      loginDto.password,
      undefined,
      deviceInfo,
    );

    // Update last login
    await this.prisma.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });

    return this.generateTokens(user, loginDto.branchId, loginDto.deviceId, deviceInfo);
  }

  async loginWithPin(pinLoginDto: PinLoginDto, deviceInfo?: DeviceFingerprint): Promise<AuthResponseDto> {
    const identifier = deviceInfo ? `pin:${pinLoginDto.branchId}:${deviceInfo.ipAddress}` : `pin:${pinLoginDto.branchId}`;

    // Check lockout
    if (await this.isUserLockedOut(identifier)) {
      throw new ForbiddenException(`Too many failed PIN attempts. Try again in ${this.LOCKOUT_DURATION_MINUTES} minutes.`);
    }

    // Find users in the specified branch
    const userBranches = await this.prisma.userBranch.findMany({
      where: { branchId: pinLoginDto.branchId },
      include: {
        user: {
          include: {
            branches: {
              include: { branch: true },
            },
          },
        },
      },
    });

    // Find user with matching PIN
    for (const ub of userBranches) {
      if (ub.user.pin && ub.user.isActive) {
        const isPinValid = await bcrypt.compare(pinLoginDto.pin, ub.user.pin);
        if (isPinValid) {
          await this.clearFailedAttempts(identifier);
          await this.prisma.user.update({
            where: { id: ub.user.id },
            data: { lastLoginAt: new Date() },
          });
          return this.generateTokens(ub.user, pinLoginDto.branchId, pinLoginDto.deviceId, deviceInfo);
        }
      }
    }

    await this.recordFailedAttempt(identifier);
    throw new UnauthorizedException('Invalid PIN');
  }

  async register(registerDto: RegisterDto): Promise<AuthResponseDto> {
    // Check if user already exists
    const existingUser = await this.prisma.user.findFirst({
      where: {
        tenantId: registerDto.tenantId,
        email: registerDto.email,
      },
    });

    if (existingUser) {
      throw new ConflictException('User with this email already exists');
    }

    // Hash password with high cost factor
    const passwordHash = await bcrypt.hash(registerDto.password, 12);

    // Create user with branch assignments
    const user = await this.prisma.user.create({
      data: {
        tenantId: registerDto.tenantId,
        email: registerDto.email,
        passwordHash,
        firstName: registerDto.firstName,
        lastName: registerDto.lastName,
        phone: registerDto.phone,
        role: registerDto.role || UserRole.CASHIER,
        branches: registerDto.branchIds
          ? {
              create: registerDto.branchIds.map((branchId, index) => ({
                branchId,
                isPrimary: index === 0,
              })),
            }
          : undefined,
      },
      include: {
        branches: {
          include: { branch: true },
        },
      },
    });

    return this.generateTokens(user);
  }

  async refreshToken(refreshTokenDto: RefreshTokenDto, deviceInfo?: DeviceFingerprint): Promise<AuthResponseDto> {
    const tokenHash = this.hashToken(refreshTokenDto.refreshToken);

    const storedToken = await this.prisma.refreshToken.findFirst({
      where: { tokenHash },
      include: {
        user: {
          include: {
            branches: {
              include: { branch: true },
            },
          },
        },
      },
    });

    if (!storedToken) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    // Check device binding if enabled
    if (storedToken.deviceFingerprint && deviceInfo) {
      const currentFingerprint = this.generateDeviceFingerprint(deviceInfo);
      if (storedToken.deviceFingerprint !== currentFingerprint) {
        // Possible token theft - revoke all tokens for this user
        await this.revokeAllUserTokens(storedToken.userId);
        throw new UnauthorizedException('Token reuse detected. All sessions revoked.');
      }
    }

    if (new Date() > storedToken.expiresAt) {
      await this.prisma.refreshToken.delete({ where: { id: storedToken.id } });
      throw new UnauthorizedException('Refresh token expired');
    }

    if (!storedToken.user.isActive) {
      throw new UnauthorizedException('Account is disabled');
    }

    // Delete old token and issue new ones (token rotation)
    await this.prisma.refreshToken.delete({ where: { id: storedToken.id } });

    return this.generateTokens(
      storedToken.user,
      undefined,
      storedToken.deviceId || undefined,
      deviceInfo,
    );
  }

  async logout(userId: string, logoutDto?: LogoutDto): Promise<void> {
    const refreshToken = logoutDto?.refreshToken;
    const allDevices = logoutDto?.allDevices ?? false;

    if (!allDevices && refreshToken) {
      const tokenHash = this.hashToken(refreshToken);
      await this.prisma.refreshToken.deleteMany({
        where: { userId, tokenHash },
      });
    } else {
      // Backward compatibility: missing refresh token still means all devices.
      await this.revokeAllUserTokens(userId);
    }

    // Invalidate cached user data
    await this.redisService.del(`user:${userId}`);
  }

  /**
   * Revoke all tokens for a user (security breach response)
   */
  async revokeAllUserTokens(userId: string): Promise<void> {
    await this.prisma.refreshToken.deleteMany({
      where: { userId },
    });

    // Also revoke all active JWTs by adding to blacklist
    await this.redisService.set(`user:revoked:${userId}`, Date.now().toString(), 86400 * 7); // 7 days
  }

  async changePassword(userId: string, dto: ChangePasswordDto): Promise<void> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    const isCurrentPasswordValid = await bcrypt.compare(dto.currentPassword, user.passwordHash);
    if (!isCurrentPasswordValid) {
      throw new UnauthorizedException('Current password is incorrect');
    }

    // Validate new password strength
    if (dto.newPassword.length < 8) {
      throw new ConflictException('Password must be at least 8 characters');
    }

    const newPasswordHash = await bcrypt.hash(dto.newPassword, 12);
    await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash: newPasswordHash },
    });

    // Invalidate all refresh tokens (force re-login)
    await this.revokeAllUserTokens(userId);
  }

  async setPin(userId: string, dto: SetPinDto): Promise<void> {
    // Validate PIN format (4-6 digits)
    if (!/^\d{4,6}$/.test(dto.pin)) {
      throw new ConflictException('PIN must be 4-6 digits');
    }

    const pinHash = await bcrypt.hash(dto.pin, 12);
    await this.prisma.user.update({
      where: { id: userId },
      data: { pin: pinHash },
    });
  }

  async getProfile(userId: string) {
    const cached = await this.redisService.getJson<any>(`user:${userId}`);
    if (cached) return cached;

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        phone: true,
        role: true,
        avatar: true,
        tenantId: true,
        lastLoginAt: true,
        createdAt: true,
        branches: {
          include: {
            branch: {
              select: {
                id: true,
                name: true,
                code: true,
              },
            },
          },
        },
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    const profile = {
      ...user,
      branches: user.branches.map((ub) => ({
        ...ub.branch,
        isPrimary: ub.isPrimary,
      })),
    };

    await this.redisService.setJson(`user:${userId}`, profile, 3600);
    return profile;
  }

  /**
   * Validate JWT and check revocation
   */
  async validateAccessToken(jti: string, userId: string): Promise<boolean> {
    // Check if token is revoked
    const isRevoked = await this.redisService.get(`jwt:revoked:${jti}`);
    if (isRevoked) return false;

    // Check if user's tokens were globally revoked
    const globalRevoke = await this.redisService.get(`user:revoked:${userId}`);
    if (globalRevoke) {
      const revokedAt = parseInt(globalRevoke, 10);
      // Token issued before global revoke is invalid
      // This requires storing iat in the token and checking
      return false;
    }

    return true;
  }

  private async generateTokens(
    user: any,
    branchId?: string,
    deviceId?: string,
    deviceInfo?: DeviceFingerprint,
  ): Promise<AuthResponseDto> {
    const jti = uuidv4(); // Unique token ID
    const now = Math.floor(Date.now() / 1000);

    const payload: Omit<JwtPayload, 'iat' | 'exp'> = {
      sub: user.id,
      email: user.email,
      role: user.role,
      tenantId: user.tenantId,
      branchId,
      deviceId,
      jti,
    };

    const expiresIn = this.parseExpiry(this.configService.get<string>('JWT_EXPIRES_IN', '15m'));
    const refreshExpiresIn = this.parseExpiry(
      this.configService.get<string>('JWT_REFRESH_EXPIRES_IN', '7d'),
    );

    const accessToken = this.jwtService.sign({
      ...payload,
      iat: now,
      exp: now + expiresIn,
    });

    // Generate cryptographically secure refresh token
    const refreshToken = this.generateSecureRefreshToken();
    const tokenHash = this.hashToken(refreshToken);

    // Generate device fingerprint for binding
    const deviceFingerprint = deviceInfo ? this.generateDeviceFingerprint(deviceInfo) : null;

    // Store hashed refresh token with device binding
    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash, // Store hash, not plaintext
        deviceId,
        deviceFingerprint,
        expiresAt: new Date(Date.now() + refreshExpiresIn * 1000),
      },
    });

    // Cache active token info
    await this.redisService.set(
      `jwt:active:${jti}`,
      user.id,
      expiresIn,
    );

    return {
      accessToken,
      refreshToken,
      expiresIn,
      user: {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role,
        tenantId: user.tenantId,
        hasPinSet: Boolean(user.pin),
        branches: user.branches?.map((ub: any) => ({
          id: ub.branch?.id || ub.branchId,
          name: ub.branch?.name || '',
          isPrimary: ub.isPrimary,
        })) || [],
      },
    };
  }

  private parseExpiry(expiry: string): number {
    const match = expiry.match(/^(\d+)([smhd])$/);
    if (!match) return 900; // Default 15 minutes

    const value = parseInt(match[1], 10);
    const unit = match[2];

    switch (unit) {
      case 's':
        return value;
      case 'm':
        return value * 60;
      case 'h':
        return value * 3600;
      case 'd':
        return value * 86400;
      default:
        return 900;
    }
  }
}
