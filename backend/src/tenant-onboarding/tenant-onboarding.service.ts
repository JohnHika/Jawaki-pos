import { ConflictException, ForbiddenException, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
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

  async acceptInvitation(invitationId: string, dto: { challengeId: string; code: string }) {
    const invite = await this.prisma.tenantStaffInvitation.findUnique({ where: { id: invitationId } });
    if (!invite || invite.status !== 'PENDING' || invite.expiresAt <= new Date() || invite.challengeId !== dto.challengeId) {
      throw new UnauthorizedException('Invalid or expired invitation');
    }
    const consumed = await this.otp.consume({
      challengeId: dto.challengeId, purpose: 'STAFF_INVITE', email: invite.email, tenantId: invite.tenantId, code: dto.code,
    });
    if (!consumed.consumed) throw new UnauthorizedException('Invalid or expired invitation');

    return this.prisma.$transaction(async (tx) => {
      const claimed = await tx.tenantStaffInvitation.updateMany({
        where: { id: invite.id, status: 'PENDING', acceptedAt: null }, data: { status: 'ACCEPTED', acceptedAt: new Date() },
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
      return { accepted: true };
    });
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
