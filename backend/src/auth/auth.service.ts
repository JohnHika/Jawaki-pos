import {
  Injectable,
  Logger,
  UnauthorizedException,
  ConflictException,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
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
  GoogleLoginDto,
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
import { CreateEmailWorkspaceDto, CreateGoogleWorkspaceDto, RequestWorkspaceOtpDto } from './dto/workspace.dto';
import { GoogleIdentityService } from '../identity/google-identity.service';
import { EmailOtpService } from '../identity/email-otp.service';
import { WorkspaceService } from '../workspace/workspace.service';
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

export type StaffRegistrationActor = Pick<JwtPayload, 'sub' | 'tenantId' | 'role'> & {
  permissions?: string[];
};

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private prisma: PrismaService,
    private jwtService: JwtService,
    private configService: ConfigService,
    private redisService: RedisService,
    private auditService: AuditService,
    private permissionsService: PermissionsService,
    private googleIdentityService: GoogleIdentityService,
    private emailOtpService: EmailOtpService,
    private workspaceService: WorkspaceService,
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

    if (!user.passwordHash) {
      throw new UnauthorizedException('Invalid credentials');
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

  async loginWithGoogle(dto: GoogleLoginDto): Promise<AuthResponseDto> {
    // Keep the existing login contract: server-verified Google identity must
    // match an existing active user in the requested active tenant.
    const identity = await this.googleIdentityService.verify(dto.idToken);
    const email = identity.email;

    const tenantId = await this.resolveTenantId(undefined, dto.tenantSlug);
    const user = await this.prisma.user.findFirst({
      where: { email, tenantId },
      include: {
        tenant: true,
        branches: { include: { branch: true } },
      },
    });

    if (!user || !user.isActive || !user.tenant.isActive) {
      throw new UnauthorizedException('This Google account is not linked to this business');
    }

    const branchId = this.resolveLoginBranchId(user, dto.branchId);
    await this.prisma.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date(), identityProvider: 'GOOGLE', identityVerifiedAt: new Date() },
    });
    await this.auditService.record({
      userId: user.id,
      action: 'LOGIN',
      entityType: 'session',
    });

    return this.generateTokens(user, branchId, dto.deviceId);
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

  async requestWorkspaceEmailOtp(dto: RequestWorkspaceOtpDto) {
    return this.emailOtpService.request({ purpose: 'WORKSPACE_CREATION', email: dto.email });
  }

  async createWorkspaceWithGoogle(dto: CreateGoogleWorkspaceDto): Promise<AuthResponseDto> {
    const identity = await this.googleIdentityService.verify(dto.idToken);
    const user = await this.workspaceService.createFromVerifiedIdentity({
      ...dto, email: identity.email, provider: 'GOOGLE',
      firstName: dto.firstName || identity.firstName || 'Owner',
      lastName: dto.lastName || identity.lastName || 'Owner',
    });
    return this.generateTokens(user, user.branches[0]?.branchId, dto.deviceId);
  }

  async createWorkspaceWithEmailOtp(dto: CreateEmailWorkspaceDto): Promise<AuthResponseDto> {
    const proof = await this.emailOtpService.consume({
      challengeId: dto.challengeId, purpose: 'WORKSPACE_CREATION', email: dto.email, code: dto.code,
    });
    if (!proof.consumed) throw new UnauthorizedException('Invalid or expired verification code');
    const user = await this.workspaceService.createFromVerifiedIdentity({ ...dto, provider: 'EMAIL_OTP' });
    return this.generateTokens(user, user.branches[0]?.branchId, dto.deviceId);
  }

  async registerCompany(dto: RegisterCompanyDto): Promise<AuthResponseDto> {
    throw new ForbiddenException('Verified identity is required. Use the verified workspace creation endpoints.');
  }

  async register(
    registerDto: RegisterDto,
    actor: StaffRegistrationActor,
  ): Promise<AuthResponseDto> {
    if (!actor?.tenantId) {
      throw new ForbiddenException('Authenticated tenant context is required');
    }

    // The legacy request contract includes tenantId, but it is never an
    // authority source. Reject a conflicting value rather than silently
    // accepting a cross-tenant attempt.
    if (registerDto.tenantId && registerDto.tenantId !== actor.tenantId) {
      throw new ForbiddenException('Cannot register staff for another company');
    }

    const role = registerDto.role ?? LegacyUserRole.CASHIER;
    if (!this.canAssignLegacyRole(actor.role, role)) {
      throw new ForbiddenException(
        'Cannot assign an equal or higher legacy role. Use the tenant-scoped staff invitation flow for role-managed onboarding.',
      );
    }

    const branchIds = [...new Set(registerDto.branchIds ?? [])];
    if (branchIds.length) {
      const activeTenantBranches = await this.prisma.branch.findMany({
        where: {
          id: { in: branchIds },
          tenantId: actor.tenantId,
          isActive: true,
        },
        select: { id: true },
      });
      if (activeTenantBranches.length !== branchIds.length) {
        throw new ForbiddenException('Every assigned branch must be active and belong to this company');
      }
    }

    // Check if user already exists
    const existingUser = await this.prisma.user.findFirst({
      where: {
        tenantId: actor.tenantId,
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
        tenantId: actor.tenantId,
        email: registerDto.email,
        passwordHash,
        firstName: registerDto.firstName,
        lastName: registerDto.lastName,
        phone: registerDto.phone,
        role,
        branches: branchIds.length
          ? {
              create: branchIds.map((branchId, index) => ({
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

    if (!storedToken.user.isActive || !storedToken.user.tenant.isActive) {
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

    // Fails soft — a transient DB hiccup computing permissions must not
    // block login entirely. JwtStrategy re-derives permissions fresh on
    // every subsequent request anyway, so an empty array here just means
    // the very first screen after login is momentarily under-permissioned
    // until the next request succeeds, not a hard failure to log in.
    let permissions: string[] = [];
    try {
      permissions = await this.permissionsService.getEffectivePermissions(user.id);
    } catch (error) {
      this.logger.warn(
        `Failed to resolve permissions for user ${user.id} during login: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }

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
              activationStatus: user.tenant.activationStatus,
              activationAmount: user.tenant.activationAmount,
              activationPaidAt: user.tenant.activationPaidAt ?? undefined,
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

  private canAssignLegacyRole(actorRole: LegacyUserRole, requestedRole: LegacyUserRole): boolean {
    const rank: Record<LegacyUserRole, number> = {
      [LegacyUserRole.CASHIER]: 0,
      [LegacyUserRole.SUPERVISOR]: 1,
      [LegacyUserRole.MANAGER]: 2,
      [LegacyUserRole.ADMIN]: 3,
    };
    return rank[actorRole] > rank[requestedRole];
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
