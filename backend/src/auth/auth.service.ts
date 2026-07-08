import {
  Injectable,
  UnauthorizedException,
  ConflictException,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcryptjs';
import { createHash, randomBytes } from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { AuditService } from '../audit/audit.service';
import { PermissionsService } from '../permissions/permissions.service';
import {
  LoginDto,
  PinLoginDto,
  RegisterCompanyDto,
  RegisterDto,
  RefreshTokenDto,
  LogoutDto,
  ChangePasswordDto,
  SetPinDto,
  SetOfflineAccessPinDto,
  AuthResponseDto,
  CompanyInfoResponseDto,
} from './dto/auth.dto';
import { LegacyUserRole } from '@prisma/client';

export interface JwtPayload {
  sub: string;
  email: string;
  role: LegacyUserRole;
  tenantId: string;
  branchId?: string;
  deviceId?: string;
  permissions?: string[];
}

@Injectable()
export class AuthService {
  constructor(
    private prisma: PrismaService,
    private jwtService: JwtService,
    private configService: ConfigService,
    private redisService: RedisService,
    private auditService: AuditService,
    private permissionsService: PermissionsService,
  ) {}

  async validateUser(email: string, password: string, tenantId?: string) {
    const users = await this.prisma.user.findMany({
      where: tenantId ? { email, tenantId } : { email },
      include: {
        tenant: true,
        branches: {
          include: {
            branch: true,
          },
        },
      },
      take: 2,
    });

    if (!tenantId && users.length > 1) {
      throw new BadRequestException('Company is required for this email');
    }

    const user = users[0];

    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    if (!user.isActive || !user.tenant.isActive) {
      throw new UnauthorizedException('Account is disabled');
    }

    const isPasswordValid = await bcrypt.compare(password, user.passwordHash);
    if (!isPasswordValid) {
      throw new UnauthorizedException('Invalid credentials');
    }

    return user;
  }

  async login(loginDto: LoginDto): Promise<AuthResponseDto> {
    const tenantId = await this.resolveTenantId(loginDto.tenantId, loginDto.tenantSlug);
    const user = await this.validateUser(loginDto.email, loginDto.password, tenantId);
    const branchId = this.resolveLoginBranchId(user, loginDto.branchId);

    // Update last login
    await this.prisma.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });
    await this.auditService.record({
      userId: user.id,
      action: 'LOGIN',
      entityType: 'session',
    });

    return this.generateTokens(user, branchId, loginDto.deviceId);
  }

  async loginWithPin(pinLoginDto: PinLoginDto): Promise<AuthResponseDto> {
    const branchId = await this.resolvePinLoginBranchId(pinLoginDto);

    // Find users in the specified branch
    const userBranches = await this.prisma.userBranch.findMany({
      where: { branchId },
      include: {
        user: {
          include: {
            tenant: true,
            branches: {
              include: { branch: true },
            },
          },
        },
      },
    });

    // Find user with matching PIN
    for (const ub of userBranches) {
      if (ub.user.pin && ub.user.isActive && ub.user.tenant.isActive) {
        const isPinValid = await bcrypt.compare(pinLoginDto.pin, ub.user.pin);
        if (isPinValid) {
          await this.prisma.user.update({
            where: { id: ub.user.id },
            data: { lastLoginAt: new Date() },
          });
          await this.auditService.record({
            userId: ub.user.id,
            action: 'LOGIN',
            entityType: 'session',
          });
          return this.generateTokens(ub.user, branchId, pinLoginDto.deviceId);
        }
      }
    }

    throw new UnauthorizedException('Invalid PIN');
  }

  async registerCompany(dto: RegisterCompanyDto): Promise<AuthResponseDto> {
    try {
      // Validate required fields at the top level
      if (!dto || !dto.companyName) {
        throw new BadRequestException('Company information is required');
      }

      // Validate admin information
      if (!dto.admin) {
        throw new BadRequestException('Admin information is required');
      }

      if (!dto.admin.email || !dto.admin.password || !dto.admin.firstName || !dto.admin.lastName) {
        throw new BadRequestException('Admin information is incomplete');
      }

      // Validate branch information
      if (!dto.branch) {
        throw new BadRequestException('Branch information is required');
      }

      if (!dto.branch.name) {
        throw new BadRequestException('Branch name is required');
      }

      // Validate company name format
      if (typeof dto.companyName !== 'string' || dto.companyName.trim().length < 2) {
        throw new BadRequestException('Company name must be at least 2 characters');
      }

      // Generate slug and check for existing company
      const slug = dto.companySlug || this.slugify(dto.companyName);
      const existingTenantBySlug = await this.prisma.tenant.findUnique({
        where: { slug },
      });

      if (existingTenantBySlug) {
        throw new BadRequestException('Company with this slug already exists');
      }

      // Check if company name already exists (case-insensitive)
      try {
        const existingTenantByName = await this.prisma.tenant.findFirst({
          where: {
            name: {
              equals: dto.companyName.trim(),
              mode: 'insensitive',
            },
          },
        });

        if (existingTenantByName) {
          throw new BadRequestException('Company name already exists');
        }
      } catch (error) {
        // Log the error but continue
        console.warn('Failed to check company name uniqueness: ' + error.message);
      }

      // Validate phone numbers if provided
      const validatePhoneNumber = (phone) => {
        if (!phone) return true; // Optional
        const phoneRegex = /^\+?[\d\s\-\(\)]+$/;
        if (!phoneRegex.test(phone)) {
          throw new BadRequestException('Invalid phone number format');
        }
        return true;
      };

      // Validate branch phone if provided
      if (dto.branch.phone && !validatePhoneNumber(dto.branch.phone)) {
        throw new BadRequestException('Invalid branch phone number format');
      }

      // Validate admin phone if provided
      if (dto.admin.phone && !validatePhoneNumber(dto.admin.phone)) {
        throw new BadRequestException('Invalid admin phone number format');
      }

      // Validate email formats
      const validateEmail = (email) => {
        if (!email) return true; // Should not happen due to DTO validation
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
          throw new BadRequestException('Invalid email format');
        }
        return true;
      };

      if (!validateEmail(dto.admin.email)) {
        throw new BadRequestException('Invalid admin email format');
      }

      if (dto.branch.email && !validateEmail(dto.branch.email)) {
        throw new BadRequestException('Invalid branch email format');
      }

      // Validate password strength for admin
      const password = dto.admin.password;
      if (password.length < 8) {
        throw new BadRequestException('Password must be at least 8 characters');
      }
      if (!/[A-Z]/.test(password)) {
        throw new BadRequestException('Password must contain at least one uppercase letter');
      }
      if (!/[a-z]/.test(password)) {
        throw new BadRequestException('Password must contain at least one lowercase letter');
      }
      if (!/\d/.test(password)) {
        throw new BadRequestException('Password must contain at least one number');
      }

      const passwordHash = await bcrypt.hash(dto.admin.password, 12);
      const branchCode = dto.branch.code || 'MAIN';

      // Process registration in transaction
      try {
        const user = await this.prisma.$transaction(async (tx) => {
          const tenant = await tx.tenant.create({
            data: {
              name: dto.companyName.trim(),
              slug,
              logo: dto.logo,
              logoPublicId: dto.logoPublicId,
              settings: dto.settings || {},
            },
          });

          const branch = await tx.branch.create({
            data: {
              tenantId: tenant.id,
              name: dto.branch.name.trim(),
              code: branchCode,
              address: dto.branch.address?.trim() || null,
              phone: dto.branch.phone?.trim() || null,
              email: dto.branch.email?.trim() || null,
            },
          });

          return tx.user.create({
            data: {
              tenantId: tenant.id,
              email: dto.admin.email.trim().toLowerCase(),
              passwordHash,
              firstName: dto.admin.firstName.trim(),
              lastName: dto.admin.lastName.trim(),
              phone: dto.admin.phone?.trim() || null,
              role: LegacyUserRole.ADMIN,
              lastLoginAt: new Date(),
              branches: {
                create: {
                  branchId: branch.id,
                  isPrimary: true,
                },
              },
            },
            include: {
              tenant: true,
              branches: {
                include: { branch: true },
              },
            },
          });
        });

        return this.generateTokens(user, user.branches[0]?.branchId, dto.deviceId);
      } catch (error) {
        // Handle specific database errors
        if (error.code === 'P2002') {
          // Unique constraint violation
          if (error.meta?.target?.includes('slug')) {
            throw new BadRequestException('Company with this slug already exists');
          }
          if (error.meta?.target?.includes('email')) {
            throw new BadRequestException('Admin email already exists');
          }
          if (error.meta?.target?.includes('phone')) {
            throw new BadRequestException('Admin phone number already exists');
          }
          throw new BadRequestException('Company registration failed due to duplicate data');
        } else if (error.code === 'P2003') {
          // Foreign key constraint violation
          throw new BadRequestException('Invalid branch or tenant reference');
        } else if (error.code === 'P2025') {
          // Record not found
          throw new NotFoundException('Database operation failed');
        } else {
          // Log the error for debugging
          console.error('Register company error:', error);
          throw new BadRequestException(`Company registration failed: ${error.message || 'Unknown error'}`);
        }
      }
    } catch (error) {
      // Handle validation errors at the top level
      console.error('Register company validation error:', error);
      throw error;
    }
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
        role: registerDto.role || LegacyUserRole.CASHIER,
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
        tenant: true,
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
            tenant: true,
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

    const branchId = this.resolveLoginBranchId(storedToken.user);
    return this.generateTokens(storedToken.user, branchId, storedToken.deviceId || undefined);
  }

  async logout(userId: string, logoutDto?: LogoutDto): Promise<void> {
    const refreshToken = logoutDto?.refreshToken;
    const allDevices = logoutDto?.allDevices ?? false;

    if (!allDevices && refreshToken) {
      const tokenHash = require('crypto').createHash('sha256').update(refreshToken).digest('hex');
      await this.prisma.refreshToken.deleteMany({
        where: { userId, tokenHash },
      });
    } else {
      // Backward compatibility: missing refresh token still means all devices.
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
    await this.auditService.record({
      userId,
      action: 'UPDATE',
      entityType: 'pin',
      entityId: userId,
    });
  }

  // Sets this user's offline-access PIN — authorizes logging into any
  // phone acting as a local server as this user, entirely without
  // network access. Must be set while online; the hash then travels to
  // phone-server devices via the offline directory sync.
  //
  // Deliberately NOT bcrypt: bcrypt can only be verified by re-running the
  // same native, CPU-heavy algorithm, which the mobile app doesn't ship
  // (it has no bcrypt dependency, unlike this backend). Any phone-server
  // device receiving this hash needs to verify it standalone, fully
  // offline, using only what Dart's `crypto` package already provides —
  // so this uses the exact salted-SHA-256 scheme StorageService already
  // uses for the on-device unlock PIN (storage_service.dart `_hashPin`),
  // with the salt persisted alongside the hash (`salt:hash`) instead of
  // in per-device secure storage, since this hash must be portable to
  // any device that pulls the offline directory, not just the owner's own.
  async setOfflineAccessPin(userId: string, dto: SetOfflineAccessPinDto): Promise<void> {
    const salt = randomBytes(16).toString('base64url');
    const hash = createHash('sha256').update(`${salt}:${dto.pin}`).digest('hex');
    await this.prisma.user.update({
      where: { id: userId },
      data: { offlineAccessPinHash: `${salt}:${hash}` },
    });
    await this.auditService.record({
      userId,
      action: 'UPDATE',
      entityType: 'offline_access_pin',
      entityId: userId,
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
        tenant: {
          select: {
            id: true,
            name: true,
            slug: true,
            logo: true,
            logoPublicId: true,
            settings: true,
            isActive: true,
          },
        },
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

    const branches = user.branches.map((ub) => ({
      ...ub.branch,
      isPrimary: ub.isPrimary,
    }));
    const primaryBranch = branches.find((branch) => branch.isPrimary) || branches[0];

    const profile = {
      ...user,
      branchId: primaryBranch?.id,
      branchName: primaryBranch?.name,
      branches,
    };

    await this.redisService.setJson(`user:${userId}`, profile, 3600);
    return profile;
  }

  async getTenantUsers(tenantId: string) {
    const users = await this.prisma.user.findMany({
      where: { tenantId },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        phone: true,
        role: true,
        avatar: true,
        isActive: true,
        lastLoginAt: true,
        createdAt: true,
        updatedAt: true,
        branches: {
          select: {
            isPrimary: true,
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
      orderBy: [
        { firstName: 'asc' },
        { lastName: 'asc' },
      ],
    });

    return users.map((user) => ({
      ...user,
      branches: user.branches.map((ub) => ({
        ...ub.branch,
        isPrimary: ub.isPrimary,
      })),
    }));
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

    const branches = user.branches?.map((ub: any) => ({
      id: ub.branch?.id || ub.branchId,
      name: ub.branch?.name || '',
      isPrimary: ub.isPrimary,
    })) || [];
    const activeBranch = branches.find((item: any) => item.id === branchId)
      || branches.find((item: any) => item.isPrimary)
      || branches[0];

    const permissions = await this.permissionsService.getEffectivePermissions(user.id);

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
        tenantSlug: user.tenant?.slug,
        branchId: activeBranch?.id,
        branchName: activeBranch?.name,
        hasPinSet: Boolean(user.pin),
        permissions,
        tenant: user.tenant
          ? {
              id: user.tenant.id,
              name: user.tenant.name,
              slug: user.tenant.slug,
              logo: user.tenant.logo ?? undefined,
              logoPublicId: user.tenant.logoPublicId ?? undefined,
              settings: user.tenant.settings ?? {},
              isActive: user.tenant.isActive,
            }
          : undefined,
        branches,
      },
    };
  }

  private async resolvePinLoginBranchId(pinLoginDto: PinLoginDto): Promise<string> {
    if (pinLoginDto.branchId) {
      return pinLoginDto.branchId;
    }

    const device = await this.prisma.device.findFirst({
      where: {
        deviceUuid: pinLoginDto.deviceId,
        isActive: true,
      },
      select: { branchId: true },
    });

    if (!device?.branchId) {
      throw new BadRequestException('Branch context is required for PIN login');
    }

    return device.branchId;
  }

  private async resolveTenantId(tenantId?: string, tenantSlug?: string): Promise<string | undefined> {
    if (!tenantId && !tenantSlug) {
      return undefined;
    }

    if (tenantId && !tenantSlug) {
      return tenantId;
    }

    const tenant = await this.prisma.tenant.findUnique({
      where: { slug: tenantSlug },
      select: { id: true, isActive: true },
    });

    if (!tenant || !tenant.isActive) {
      throw new UnauthorizedException('Invalid credentials');
    }

    if (tenantId && tenant.id !== tenantId) {
      throw new BadRequestException('Tenant ID and slug do not match');
    }

    return tenant.id;
  }

  private resolveLoginBranchId(user: any, requestedBranchId?: string): string | undefined {
    if (!user.branches?.length) {
      return undefined;
    }

    if (requestedBranchId) {
      const assignedBranch = user.branches.find((ub: any) => ub.branchId === requestedBranchId);
      if (!assignedBranch) {
        throw new UnauthorizedException('User is not assigned to this branch');
      }
      return requestedBranchId;
    }

    const primaryBranch = user.branches.find((ub: any) => ub.isPrimary);
    return primaryBranch?.branchId || user.branches[0].branchId;
  }

  async getCompanyInfo(slug: string): Promise<CompanyInfoResponseDto> {
    const tenant = await this.prisma.tenant.findUnique({
      where: { slug },
      select: { name: true, logo: true, logoPublicId: true, isActive: true },
    });

    if (!tenant) {
      throw new NotFoundException(`No company found with slug: ${slug}`);
    }

    return {
      name: tenant.name,
      logoUrl: tenant.logo || undefined,
      logoPublicId: tenant.logoPublicId || undefined,
      isActive: tenant.isActive,
    };
  }

  private slugify(value: string): string {
    const slug = value
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');

    if (slug.length < 2) {
      throw new BadRequestException('Company name cannot be converted to a valid slug');
    }

    return slug.slice(0, 50).replace(/-+$/g, '');
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
