import { ConflictException, ForbiddenException, Injectable, NotFoundException, Optional, UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { createHash, randomBytes, timingSafeEqual } from 'crypto';
import { LegacyUserRole } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { EmailOtpService } from '../identity/email-otp.service';
import { LicenseService } from '../license/license.service';

interface Actor { sub: string; tenantId: string; permissions?: string[] }

@Injectable()
export class TenantOnboardingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly otp: EmailOtpService,
    @Optional() private readonly license?: LicenseService,
  ) {}

  async get(actor: Actor) {
    const onboarding = await this.prisma.tenantOnboarding.findUnique({
      where: { tenantId: actor.tenantId }, include: { steps: { orderBy: { position: 'asc' } } },
    });
    // Companies created before the onboarding checklist existed have no row.
    // A 404 here is read by the app as an expired session, so answer with an
    // empty checklist instead.
    if (!onboarding) return { id: null, tenantId: actor.tenantId, steps: [] };
    const payout = await this.prisma.merchantPaymentAccount.findUnique({
      where: { tenantId: actor.tenantId }, select: { status: true },
    });
    return {
      ...onboarding,
      steps: onboarding.steps.map((step) =>
        step.key === 'activate_payment' && step.status === 'COMPLETED' && payout?.status !== 'ACTIVE'
          ? { ...step, status: 'PENDING', completedAt: null }
          : step,
      ),
    };
  }

  async updateStep(actor: Actor, key: string, status: 'PENDING' | 'DEFERRED' | 'COMPLETED') {
    const onboarding = await this.assertOwnerOrPermission(actor, 'users.create');
    const supportedSteps = new Set([
      'confirm_business',
      'configure_branch',
      'invite_staff',
      'add_catalog',
      'activate_payment',
    ]);
    if (!supportedSteps.has(key)) throw new NotFoundException('Onboarding step was not found');

    if (status === 'COMPLETED') {
      switch (key) {
        case 'confirm_business': {
          const [tenant, owner] = await Promise.all([
            this.prisma.tenant.findUnique({
              where: { id: actor.tenantId }, select: { name: true },
            }),
            this.prisma.user.findUnique({
              where: { id: onboarding.ownerUserId },
              select: { email: true },
            }),
          ]);
          if (!tenant?.name?.trim() || !owner?.email?.trim()) {
            throw new ConflictException('Add the business name and owner email before confirming business details');
          }
          break;
        }
        case 'configure_branch': {
          const branch = await this.prisma.branch.findFirst({
            where: { tenantId: actor.tenantId, isActive: true },
            select: { id: true },
          });
          if (!branch) throw new ConflictException('Create or activate a branch before completing branch setup');
          break;
        }
        case 'invite_staff': {
          const invitation = await this.prisma.tenantStaffInvitation.findFirst({
            where: {
              tenantId: actor.tenantId,
              OR: [
                { status: 'ACCEPTED' },
                { status: 'PENDING', expiresAt: { gt: new Date() } },
              ],
            },
            select: { id: true },
          });
          if (!invitation) throw new ConflictException('Send a valid staff invitation before completing this step');
          break;
        }
        case 'add_catalog': {
          const product = await this.prisma.product.findFirst({
            where: { tenantId: actor.tenantId, isActive: true },
            select: { id: true },
          });
          if (!product) throw new ConflictException('Add an active product before completing catalog setup');
          break;
        }
        case 'activate_payment': {
          const payout = await this.prisma.merchantPaymentAccount.findUnique({
            where: { tenantId: actor.tenantId }, select: { status: true },
          });
          if (payout?.status !== 'ACTIVE') {
            throw new ConflictException('Connect a business payout account to complete payment setup');
          }
          break;
        }
      }
    }
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
    const isOwner = await this.assertCanInviteStaff(actor);
    // Plan limit on staff seats (402 only when the licence is enforced).
    await this.license?.assertWithinLimit(actor.tenantId, 'users');
    const branch = await this.prisma.branch.findFirst({ where: { id: dto.branchId, tenantId: actor.tenantId, isActive: true } });
    if (!branch) throw new ForbiddenException('Branch is not available in this company');
    const role = await this.prisma.role.findFirst({
      where: { id: dto.roleId, tenantId: actor.tenantId },
      include: { permissions: { select: { permissionKey: true } } },
    });
    if (!role) throw new ForbiddenException('Role is not available in this company');
    this.assertMayAssignRole(actor, role.permissions.map((item) => item.permissionKey), isOwner);
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

  async getStaffInvitationOptions(actor: Actor) {
    const isOwner = await this.assertCanInviteStaff(actor);
    const roles = await this.prisma.role.findMany({
      where: { tenantId: actor.tenantId },
      include: { permissions: { select: { permissionKey: true } } },
      orderBy: { name: 'asc' },
    });
    const mayAssignAnyRole = isOwner || actor.permissions?.includes('permissions.assign_role');
    const actorPermissions = new Set(actor.permissions ?? []);

    return roles
      .filter((role) => mayAssignAnyRole ||
        role.permissions.every((item) => actorPermissions.has(item.permissionKey)))
      .map(({ id, name }) => ({ id, name }));
  }

  async listInvitations(actor: Actor) {
    await this.assertCanInviteStaff(actor);
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

  /**
   * Inviting staff must work for companies that predate the onboarding checklist
   * (no TenantOnboarding row): those fall back to the permission check alone
   * instead of failing with a 404 that the client reads as a lost session.
   */
  private async assertCanInviteStaff(actor: Actor): Promise<boolean> {
    const onboarding = await this.prisma.tenantOnboarding.findUnique({
      where: { tenantId: actor.tenantId },
      select: { ownerUserId: true },
    });
    const isOwner = onboarding?.ownerUserId === actor.sub;
    if (!isOwner && !actor.permissions?.includes('users.create')) {
      throw new ForbiddenException('Not authorized to manage onboarding');
    }
    return isOwner;
  }

  private assertMayAssignRole(actor: Actor, rolePermissions: string[], isOwner: boolean) {
    if (isOwner || actor.permissions?.includes('permissions.assign_role')) return;
    const actorPermissions = new Set(actor.permissions ?? []);
    if (rolePermissions.some((permission) => !actorPermissions.has(permission))) {
      throw new ForbiddenException('You cannot invite staff with permissions beyond your own');
    }
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
