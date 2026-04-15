import {
  Injectable,
  UnauthorizedException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import {
  LoginDto,
  PinLoginDto,
  RegisterDto,
  RefreshTokenDto,
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
}

@Injectable()
export class AuthService {
  constructor(
    private prisma: PrismaService,
    private jwtService: JwtService,
    private configService: ConfigService,
    private redisService: RedisService,
  ) {}

  async validateUser(email: string, password: string, tenantId?: string) {
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
      throw new UnauthorizedException('Invalid credentials');
    }

    if (!user.isActive) {
      throw new UnauthorizedException('Account is disabled');
    }

    const isPasswordValid = await bcrypt.compare(password, user.passwordHash);
    if (!isPasswordValid) {
      throw new UnauthorizedException('Invalid credentials');
    }

    return user;
  }

  async login(loginDto: LoginDto): Promise<AuthResponseDto> {
    const user = await this.validateUser(loginDto.email, loginDto.password);

    // Update last login
    await this.prisma.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });

    return this.generateTokens(user, loginDto.branchId, loginDto.deviceId);
  }

  async loginWithPin(pinLoginDto: PinLoginDto): Promise<AuthResponseDto> {
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
          await this.prisma.user.update({
            where: { id: ub.user.id },
            data: { lastLoginAt: new Date() },
          });
          return this.generateTokens(ub.user, pinLoginDto.branchId, pinLoginDto.deviceId);
        }
      }
    }

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

    // Hash password
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

  async refreshToken(refreshTokenDto: RefreshTokenDto): Promise<AuthResponseDto> {
    const tokenHash = require('crypto').createHash('sha256').update(refreshTokenDto.refreshToken).digest('hex');

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

    if (new Date() > storedToken.expiresAt) {
      await this.prisma.refreshToken.delete({ where: { id: storedToken.id } });
      throw new UnauthorizedException('Refresh token expired');
    }

    if (!storedToken.user.isActive) {
      throw new UnauthorizedException('Account is disabled');
    }

    // Delete old token and issue new ones
    await this.prisma.refreshToken.delete({ where: { id: storedToken.id } });

    return this.generateTokens(storedToken.user, undefined, storedToken.deviceId || undefined);
  }

  async logout(userId: string, refreshToken?: string): Promise<void> {
    if (refreshToken) {
      const tokenHash = require('crypto').createHash('sha256').update(refreshToken).digest('hex');
      await this.prisma.refreshToken.deleteMany({
        where: { userId, tokenHash },
      });
    } else {
      // Logout from all devices
      await this.prisma.refreshToken.deleteMany({
        where: { userId },
      });
    }

    // Invalidate cached user data
    await this.redisService.del(`user:${userId}`);
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

    const newPasswordHash = await bcrypt.hash(dto.newPassword, 12);
    await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash: newPasswordHash },
    });

    // Invalidate all refresh tokens
    await this.prisma.refreshToken.deleteMany({
      where: { userId },
    });
  }

  async setPin(userId: string, dto: SetPinDto): Promise<void> {
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

  private async generateTokens(
    user: any,
    branchId?: string,
    deviceId?: string,
  ): Promise<AuthResponseDto> {
    const payload: JwtPayload = {
      sub: user.id,
      email: user.email,
      role: user.role,
      tenantId: user.tenantId,
      branchId,
      deviceId,
    };

    const accessToken = this.jwtService.sign(payload);
    const refreshToken = uuidv4();
    const tokenHash = require('crypto').createHash('sha256').update(refreshToken).digest('hex');

    // Parse JWT expiry
    const expiresIn = this.parseExpiry(this.configService.get<string>('JWT_EXPIRES_IN', '15m'));
    const refreshExpiresIn = this.parseExpiry(
      this.configService.get<string>('JWT_REFRESH_EXPIRES_IN', '7d'),
    );

    // Store hashed refresh token
    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash,
        deviceId,
        expiresAt: new Date(Date.now() + refreshExpiresIn * 1000),
      },
    });

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
