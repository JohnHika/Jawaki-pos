import { ConflictException, ForbiddenException, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { createHash, randomBytes, timingSafeEqual } from 'crypto';
import { LegacyUserRole } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { EmailOtpService } from '../identity/email-otp.service';

interface Actor { sub: string; tenantId: string; permissions?: string[] }

@Injectable()
export class TenantOnboardingService {
  constructor(private readonly prisma: PrismaService, private readonly otp: EmailOtpService) {}

  async get(actor: Actor) {
    const onboarding = await this.prisma.tenantOnboarding.findUnique({
      where: { tenantId: actor.tenantId }, include: { steps: { orderBy: { position: 'asc' } } },
    });
    if (!onboarding) throw new NotFoundException('Onboarding was not found');
    return onboarding;
  }

  async updateStep(actor: Actor, key: string, status: 'PENDING' | 'DEFERRED' | 'COMPLETED') {
    const onboarding = await this.assertOwnerOrPermission(actor, 'users.create');
    const step = await this.prisma.tenantOnboardingStep.updateMany({
      where: { onboardingId: onboarding.id, key },
      data: {
        status,
        completedAt: status === 'COMPLETED' ? new Date() : null,
        deferredAt: status === 'DEFERRED' ? new Date() : null,
      },
    });
    if (!step.count) throw new NotFoundException('Onboarding step was not found');
    return this.get(actor);
  }

  async createInvitation(actor: Actor, dto: { email: string; firstName: string; lastName: string; roleId: string; branchId: string }) {
    await this.assertOwnerOrPermission(actor, 'users.create');
    const branch = await this.prisma.branch.findFirst({ where: { id: dto.branchId, tenantId: actor.tenantId, isActive: true } });
    if (!branch) throw new ForbiddenException('Branch is not available in this company');
    const role = await this.prisma.role.findFirst({ where: { id: dto.roleId, tenantId: actor.tenantId } });
    if (!role) throw new ForbiddenException('Role is not available in this company');
    const email = dto.email.trim().toLowerCase();
    const existing = await this.prisma.user.findFirst({ where: { tenantId: actor.tenantId, email }, select: { id: true } });
    if (existing) throw new ConflictException('A user with this email already belongs to this company');

    const invite = await this.prisma.tenantStaffInvitation.create({
      data: {
        tenantId: actor.tenantId, email, firstName: dto.firstName.trim(), lastName: dto.lastName.trim(),
        roleId: role.id, branchId: branch.id, createdById: actor.sub,
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      },
    });
    const challenge = await this.otp.request({ purpose: 'STAFF_INVITE', email, tenantId: actor.tenantId });
    await this.prisma.tenantStaffInvitation.update({ where: { id: invite.id }, data: { challengeId: challenge.challengeId } });
    return { accepted: true, invitationId: invite.id, challengeId: challenge.challengeId };
  }

  async listInvitations(actor: Actor) {
    await this.assertOwnerOrPermission(actor, 'users.create');
    const invitations = await this.prisma.tenantStaffInvitation.findMany({
      where: { tenantId: actor.tenantId },
      orderBy: { createdAt: 'desc' },
      include: {
        role: { select: { id: true, name: true } },
        branch: { select: { id: true, name: true } },
        createdBy: { select: { id: true, firstName: true, lastName: true, email: true } },
      },
    });
    return invitations.map((inv) => ({
      id: inv.id,
      email: inv.email,
      firstName: inv.firstName,
      lastName: inv.lastName,
      status: inv.expiresAt <= new Date() && inv.status === 'PENDING' ? 'EXPIRED' : inv.status,
      role: inv.role,
      branch: inv.branch,
      createdBy: inv.createdBy,
      expiresAt: inv.expiresAt,
      acceptedAt: inv.acceptedAt,
      createdAt: inv.createdAt,
    }));
  }

  async acceptInvitation(invitationId: string, dto: { challengeId: string; code: string }) {
    const invite = await this.prisma.tenantStaffInvitation.findUnique({ where: { id: invitationId } });
    if (!invite || invite.status !== 'PENDING' || invite.expiresAt <= new Date() || invite.challengeId !== dto.challengeId) {
      throw new UnauthorizedException('Invalid or expired invitation');
    }
    const consumed = await this.otp.consume({
      challengeId: dto.challengeId, purpose: 'STAFF_INVITE', email: invite.email, tenantId: invite.tenantId, code: dto.code,
    });
    if (!consumed.consumed) throw new UnauthorizedException('Invalid or expired invitation');

    const setupToken = randomBytes(32).toString('base64url');
    const credentialSetupTokenHash = createHash('sha256')
      .update(setupToken)
      .digest('hex');
    const credentialSetupExpiresAt = new Date(Date.now() + 15 * 60 * 1000);

    return this.prisma.$transaction(async (tx) => {
      const claimed = await tx.tenantStaffInvitation.updateMany({
        where: { id: invite.id, status: 'PENDING', acceptedAt: null },
        data: {
          status: 'ACCEPTED',
          acceptedAt: new Date(),
          credentialSetupTokenHash,
          credentialSetupExpiresAt,
        },
      });
      if (!claimed.count) throw new UnauthorizedException('Invalid or expired invitation');
      const existing = await tx.user.findFirst({ where: { tenantId: invite.tenantId, email: invite.email }, select: { id: true } });
      if (existing) throw new ConflictException('A user with this email already belongs to this company');
      const user = await tx.user.create({
        data: {
          tenantId: invite.tenantId, email: invite.email, firstName: invite.firstName, lastName: invite.lastName,
          passwordHash: null, role: LegacyUserRole.CASHIER, identityProvider: 'EMAIL_OTP', identityVerifiedAt: new Date(),
          branches: { create: { branchId: invite.branchId, isPrimary: true } },
        },
      });
      await tx.userRole.create({ data: { userId: user.id, roleId: invite.roleId } });
      return { accepted: true, setupToken, credentialSetupExpiresAt };
    });
  }

  async completeInvitationCredentials(
    invitationId: string,
    dto: { setupToken: string; password: string; pin: string },
  ) {
    const invite = await this.prisma.tenantStaffInvitation.findUnique({
      where: { id: invitationId },
      select: {
        id: true,
        tenantId: true,
        email: true,
        status: true,
        credentialSetupTokenHash: true,
        credentialSetupExpiresAt: true,
      },
    });
    const suppliedHash = createHash('sha256').update(dto.setupToken).digest('hex');
    const storedHash = invite?.credentialSetupTokenHash;
    const tokenMatches = storedHash != null &&
        timingSafeEqual(Buffer.from(storedHash), Buffer.from(suppliedHash));
    if (
      !invite ||
      invite.status !== 'ACCEPTED' ||
      !invite.credentialSetupExpiresAt ||
      invite.credentialSetupExpiresAt <= new Date() ||
      !tokenMatches
    ) {
      throw new UnauthorizedException('This account setup link is invalid or has expired');
    }

    const [passwordHash, pinHash] = await Promise.all([
      bcrypt.hash(dto.password, 12),
      bcrypt.hash(dto.pin, 12),
    ]);

    const completed = await this.prisma.$transaction(async (tx) => {
      const consumed = await tx.tenantStaffInvitation.updateMany({
        where: {
          id: invite.id,
          status: 'ACCEPTED',
          credentialSetupTokenHash: suppliedHash,
          credentialSetupExpiresAt: { gt: new Date() },
        },
        data: {
          credentialSetupTokenHash: null,
          credentialSetupExpiresAt: null,
        },
      });
      if (!consumed.count) {
        throw new UnauthorizedException('This account setup link is invalid or has expired');
      }

      const user = await tx.user.findFirst({
        where: { tenantId: invite.tenantId, email: invite.email, passwordHash: null },
        select: { id: true },
      });
      if (!user) {
        throw new ConflictException('This staff account has already been completed');
      }
      await tx.user.update({
        where: { id: user.id },
        data: { passwordHash, pin: pinHash },
      });
      return { completed: true, email: invite.email };
    });

    return completed;
  }

  private async assertOwnerOrPermission(actor: Actor, requiredPermission: string) {
    const onboarding = await this.prisma.tenantOnboarding.findUnique({ where: { tenantId: actor.tenantId } });
    if (!onboarding) throw new NotFoundException('Onboarding was not found');
    if (onboarding.ownerUserId !== actor.sub && !actor.permissions?.includes(requiredPermission)) {
      throw new ForbiddenException('Not authorized to manage onboarding');
    }
    return onboarding;
  }
}
