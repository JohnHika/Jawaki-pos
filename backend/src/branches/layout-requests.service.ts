import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  Optional,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';

export const LAYOUT_REQUEST_STATUSES = ['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'] as const;
export type LayoutRequestStatus = (typeof LAYOUT_REQUEST_STATUSES)[number];

const asList = (value: unknown): string[] =>
  Array.isArray(value)
    ? [...new Set(value.filter((v): v is string => typeof v === 'string' && v.length > 0))].sort()
    : [];

/**
 * Change requests for a paid shop's business type. The owner asks with a
 * reason; the Counterbase team approves or declines. Approval does not change
 * the layout by itself: it leaves a marker in the shop's settings that lets the
 * owner's own save through (see layout-lock.ts), so the owner picks when to
 * switch.
 */
@Injectable()
export class LayoutRequestsService {
  constructor(
    private readonly prisma: PrismaService,
    @Optional() private readonly notifications?: NotificationsService,
  ) {}

  async create(
    tenantId: string,
    userId: string | undefined,
    dto: { toProfileId: string; additionalProfileIds?: string[]; reason: string },
  ) {
    const tenant = await this.prisma.tenant.findUnique({ where: { id: tenantId } });
    if (!tenant) throw new NotFoundException('Company not found');

    const settings = (tenant.settings ?? {}) as Record<string, any>;
    const current = settings.businessLayout;
    const fromProfileId: string | null =
      current && typeof current.profileId === 'string' ? current.profileId : null;
    const toExtras = asList(dto.additionalProfileIds);

    if (
      fromProfileId === dto.toProfileId &&
      JSON.stringify(asList(current?.additionalProfileIds)) === JSON.stringify(toExtras)
    ) {
      throw new BadRequestException('That is already your shop’s business type.');
    }

    const pending = await this.prisma.layoutChangeRequest.findFirst({
      where: { tenantId, status: 'PENDING' },
    });
    if (pending) {
      throw new ConflictException(
        'You already have a change request waiting for review. Cancel it first to send a new one.',
      );
    }

    return this.prisma.layoutChangeRequest.create({
      data: {
        tenantId,
        requestedByUserId: userId ?? null,
        fromProfileId,
        toProfileId: dto.toProfileId,
        additionalProfileIds: toExtras,
        reason: dto.reason.trim(),
      },
    });
  }

  /** Newest first. The app reads this to show pending, approved and declined states. */
  listForTenant(tenantId: string) {
    return this.prisma.layoutChangeRequest.findMany({
      where: { tenantId },
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
  }

  async cancel(tenantId: string, id: string) {
    const request = await this.prisma.layoutChangeRequest.findFirst({ where: { id, tenantId } });
    if (!request) throw new NotFoundException('Change request not found');
    if (request.status !== 'PENDING') {
      throw new ConflictException('Only a request that is still waiting can be cancelled.');
    }
    return this.prisma.layoutChangeRequest.update({
      where: { id },
      data: { status: 'CANCELLED', decidedAt: new Date() },
    });
  }

  // ---- Counterbase team ----

  listForPlatform(status?: string, take = 100) {
    const where =
      status && (LAYOUT_REQUEST_STATUSES as readonly string[]).includes(status.toUpperCase())
        ? { status: status.toUpperCase() }
        : {};
    return this.prisma.layoutChangeRequest.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: Math.min(Math.max(take, 1), 200),
      include: { tenant: { select: { id: true, name: true, slug: true } } },
    });
  }

  async decide(
    actor: { id: string; email: string },
    id: string,
    approve: boolean,
    note?: string,
  ) {
    const request = await this.prisma.layoutChangeRequest.findUnique({ where: { id } });
    if (!request) throw new NotFoundException('Change request not found');
    if (request.status !== 'PENDING') {
      throw new ConflictException('This request has already been decided.');
    }

    const decided = await this.prisma.layoutChangeRequest.update({
      where: { id },
      data: {
        status: approve ? 'APPROVED' : 'REJECTED',
        decisionNote: note?.trim() || null,
        decidedBy: actor.email,
        decidedAt: new Date(),
      },
    });

    if (approve) {
      const tenant = await this.prisma.tenant.findUnique({ where: { id: request.tenantId } });
      const settings = ((tenant?.settings ?? {}) as Record<string, any>) || {};
      await this.prisma.tenant.update({
        where: { id: request.tenantId },
        data: {
          settings: {
            ...settings,
            approvedProfileChange: {
              requestId: request.id,
              profileId: request.toProfileId,
              additionalProfileIds: asList(request.additionalProfileIds),
            },
          },
        },
      });
    }

    await this.notifyOwner(decided, approve);
    return decided;
  }

  private async notifyOwner(request: any, approve: boolean) {
    if (!request.requestedByUserId || !this.notifications) return;
    try {
      await this.notifications.sendToUser(
        request.requestedByUserId,
        {
          title: approve ? 'Business type change approved' : 'Business type change declined',
          body: approve
            ? 'Open Layout actions and tap Apply to switch your shop.'
            : request.decisionNote || 'Open Layout actions to see the reply.',
          data: { type: 'layout_request_decision', requestId: request.id, status: request.status },
        },
        { tenantId: request.tenantId },
      );
    } catch {
      // The decision stands even if the notice cannot be delivered.
    }
  }
}
