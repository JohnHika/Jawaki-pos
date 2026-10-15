import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreatePartnerRequestDto, SendPartnerMessageDto } from './dto/partners.dto';

export interface PartnerActor {
  sub: string;
  role: string;
  tenantId: string;
  email?: string;
}

const MANAGER_ROLES = ['ADMIN', 'MANAGER'];
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const TENANT_SELECT = { id: true, name: true, slug: true, logo: true } as const;
const PARTNERSHIP_INCLUDE = {
  requesterTenant: { select: TENANT_SELECT },
  addresseeTenant: { select: TENANT_SELECT },
} as const;

/**
 * Plain 404. NotFoundException is deliberately avoided: the global
 * TransformInterceptor rewrites NotFoundException to a 401 for any request
 * carrying a Bearer token, which would hide genuine "not found" results.
 */
function notFound(message: string): HttpException {
  return new HttpException({ statusCode: 404, message, error: 'Not Found' }, HttpStatus.NOT_FOUND);
}

@Injectable()
export class PartnersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
  ) {}

  // ---------------------------------------------------------------- helpers

  private assertManager(user: PartnerActor): void {
    if (!MANAGER_ROLES.includes(user.role)) {
      throw new ForbiddenException(
        'Only business owners (Admin) and managers can manage trade partners',
      );
    }
  }

  /** Loads a partnership the caller's tenant is part of, else 404. */
  private async loadOwn(user: PartnerActor, id: string) {
    const p = await this.prisma.tradePartnership.findUnique({
      where: { id },
      include: PARTNERSHIP_INCLUDE,
    });
    if (
      !p ||
      (p.requesterTenantId !== user.tenantId && p.addresseeTenantId !== user.tenantId)
    ) {
      throw notFound('Partnership not found');
    }
    return p;
  }

  private otherTenantId(
    p: { requesterTenantId: string; addresseeTenantId: string },
    me: string,
  ): string {
    return p.requesterTenantId === me ? p.addresseeTenantId : p.requesterTenantId;
  }

  private async tenantName(tenantId: string): Promise<string> {
    const t = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { name: true },
    });
    return t?.name ?? 'A business';
  }

  private format(
    p: any,
    me: string,
    lastMessage: { body: string; createdAt: Date; senderTenantId: string } | null = null,
    unreadCount = 0,
  ) {
    const outgoing = p.requesterTenantId === me;
    const other = outgoing ? p.addresseeTenant : p.requesterTenant;
    return {
      id: p.id,
      status: p.status,
      direction: outgoing ? 'outgoing' : 'incoming',
      partner: {
        tenantId: other.id,
        name: other.name,
        slug: other.slug,
        logo: other.logo ?? null,
      },
      message: p.message ?? null,
      createdAt: p.createdAt,
      respondedAt: p.respondedAt ?? null,
      lastMessage: lastMessage
        ? {
            body: lastMessage.body,
            createdAt: lastMessage.createdAt,
            fromMe: lastMessage.senderTenantId === me,
          }
        : null,
      unreadCount,
    };
  }

  // ------------------------------------------------------------------- list

  async list(user: PartnerActor) {
    this.assertManager(user);
    const me = user.tenantId;
    const rows = await this.prisma.tradePartnership.findMany({
      where: {
        status: { in: ['PENDING', 'ACCEPTED'] },
        OR: [{ requesterTenantId: me }, { addresseeTenantId: me }],
      },
      include: PARTNERSHIP_INCLUDE,
    });

    const items = await Promise.all(
      rows.map(async (p) => {
        if (p.status !== 'ACCEPTED') return { p, last: null as any, unread: 0 };
        const [last, unread] = await Promise.all([
          this.prisma.partnerMessage.findFirst({
            where: { partnershipId: p.id },
            orderBy: { createdAt: 'desc' },
            select: { body: true, createdAt: true, senderTenantId: true },
          }),
          this.prisma.partnerMessage.count({
            where: {
              partnershipId: p.id,
              senderTenantId: this.otherTenantId(p, me),
              readAt: null,
            },
          }),
        ]);
        return { p, last, unread };
      }),
    );

    // incoming PENDING first, then ACCEPTED by last activity, then our own
    // outgoing PENDING requests.
    const rank = (x: { p: any }) =>
      x.p.status === 'PENDING' ? (x.p.addresseeTenantId === me ? 0 : 2) : 1;
    const activity = (x: { p: any; last: any }) =>
      new Date(x.last?.createdAt ?? x.p.respondedAt ?? x.p.createdAt).getTime();
    items.sort((a, b) => rank(a) - rank(b) || activity(b) - activity(a));

    return { partners: items.map((x) => this.format(x.p, me, x.last, x.unread)) };
  }

  // --------------------------------------------------------------- requests

  async createRequest(user: PartnerActor, dto: CreatePartnerRequestDto) {
    this.assertManager(user);
    const me = user.tenantId;
    const code = (dto.companyCode ?? '').trim().toLowerCase();

    const target = await this.prisma.tenant.findUnique({
      where: { slug: code },
      select: { id: true, name: true, isActive: true },
    });
    if (!target || target.isActive === false) {
      throw notFound('No business found with that company code');
    }
    if (target.id === me) {
      throw new BadRequestException('You cannot connect to your own business');
    }

    const existing = await this.prisma.tradePartnership.findFirst({
      where: {
        OR: [
          { requesterTenantId: me, addresseeTenantId: target.id },
          { requesterTenantId: target.id, addresseeTenantId: me },
        ],
      },
    });

    const data = {
      requesterTenantId: me,
      addresseeTenantId: target.id,
      requestedById: user.sub,
      message: dto.message?.trim() || null,
      status: 'PENDING',
      respondedAt: null,
    };

    let saved: any;
    if (existing) {
      if (existing.status === 'ACCEPTED') {
        throw new ConflictException('You are already connected with this business');
      }
      if (existing.status === 'PENDING') {
        throw new ConflictException('A request between these businesses is already pending');
      }
      // DECLINED / REMOVED: re-open the same row (unique pair stays valid).
      saved = await this.prisma.tradePartnership.update({
        where: { id: existing.id },
        data,
        include: PARTNERSHIP_INCLUDE,
      });
    } else {
      try {
        saved = await this.prisma.tradePartnership.create({
          data,
          include: PARTNERSHIP_INCLUDE,
        });
      } catch (e) {
        if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
          throw new ConflictException('A request between these businesses is already pending');
        }
        throw e;
      }
    }

    const myName = saved.requesterTenant?.name ?? (await this.tenantName(me));
    void this.notifications.sendToTenantRoles(target.id, ['ADMIN', 'MANAGER'], {
      title: 'New trade partner request',
      body: `${myName} wants to connect with you`,
      data: { type: 'partner_request', partnershipId: saved.id },
    });

    return this.format(saved, me);
  }

  private async respond(user: PartnerActor, id: string, status: 'ACCEPTED' | 'DECLINED') {
    this.assertManager(user);
    const p = await this.loadOwn(user, id);
    if (p.addresseeTenantId !== user.tenantId) {
      throw new ForbiddenException('Only the business that received the request can respond to it');
    }
    if (p.status !== 'PENDING') {
      throw new ConflictException('This request is no longer pending');
    }
    const updated = await this.prisma.tradePartnership.update({
      where: { id: p.id },
      data: { status, respondedAt: new Date() },
      include: PARTNERSHIP_INCLUDE,
    });

    if (status === 'ACCEPTED') {
      void this.notifications.sendToTenantRoles(p.requesterTenantId, ['ADMIN', 'MANAGER'], {
        title: 'Trade partner request accepted',
        body: `${p.addresseeTenant?.name ?? 'A business'} accepted your request`,
        data: { type: 'partner_accepted', partnershipId: p.id },
      });
    }
    return this.format(updated, user.tenantId);
  }

  accept(user: PartnerActor, id: string) {
    return this.respond(user, id, 'ACCEPTED');
  }

  decline(user: PartnerActor, id: string) {
    return this.respond(user, id, 'DECLINED');
  }

  async remove(user: PartnerActor, id: string) {
    this.assertManager(user);
    const p = await this.loadOwn(user, id);
    if (p.status !== 'ACCEPTED' && p.status !== 'PENDING') {
      throw new ConflictException('This partnership is already closed');
    }
    await this.prisma.tradePartnership.update({
      where: { id: p.id },
      data: { status: 'REMOVED' },
    });
    return { id: p.id, status: 'REMOVED' };
  }

  // --------------------------------------------------------------- messages

  private async loadAccepted(user: PartnerActor, id: string) {
    const p = await this.loadOwn(user, id);
    if (p.status !== 'ACCEPTED') {
      throw new ForbiddenException('You are not connected with this business');
    }
    return p;
  }

  async getMessages(user: PartnerActor, id: string, after?: string, limit?: number) {
    this.assertManager(user);
    const p = await this.loadAccepted(user, id);
    const me = user.tenantId;
    const take = Math.min(Math.max(Math.trunc(limit ?? 50) || 50, 1), 100);
    const select = {
      id: true,
      body: true,
      createdAt: true,
      senderTenantId: true,
      senderName: true,
    };

    let rows: Array<{
      id: string;
      body: string;
      createdAt: Date;
      senderTenantId: string;
      senderName: string;
    }>;

    if (after) {
      let afterDate: Date;
      if (UUID_RE.test(after)) {
        const ref = await this.prisma.partnerMessage.findFirst({
          where: { id: after, partnershipId: p.id },
          select: { createdAt: true },
        });
        if (!ref) throw new BadRequestException('Unknown "after" message id');
        afterDate = ref.createdAt;
      } else {
        afterDate = new Date(after);
        if (Number.isNaN(afterDate.getTime())) {
          throw new BadRequestException('"after" must be an ISO date or a message id');
        }
      }
      rows = await this.prisma.partnerMessage.findMany({
        where: { partnershipId: p.id, createdAt: { gt: afterDate } },
        orderBy: { createdAt: 'asc' },
        take,
        select,
      });
    } else {
      const latest = await this.prisma.partnerMessage.findMany({
        where: { partnershipId: p.id },
        orderBy: { createdAt: 'desc' },
        take,
        select,
      });
      rows = latest.reverse();
    }

    await this.prisma.partnerMessage.updateMany({
      where: {
        partnershipId: p.id,
        senderTenantId: this.otherTenantId(p, me),
        readAt: null,
      },
      data: { readAt: new Date() },
    });

    return {
      messages: rows.map((m) => ({
        id: m.id,
        body: m.body,
        createdAt: m.createdAt,
        fromMe: m.senderTenantId === me,
        senderName: m.senderName,
      })),
    };
  }

  async sendMessage(user: PartnerActor, id: string, dto: SendPartnerMessageDto) {
    this.assertManager(user);
    const p = await this.loadAccepted(user, id);
    const me = user.tenantId;

    const sender = await this.prisma.user.findUnique({
      where: { id: user.sub },
      select: { firstName: true, lastName: true, email: true },
    });
    const senderName =
      `${sender?.firstName ?? ''} ${sender?.lastName ?? ''}`.trim() ||
      sender?.email ||
      user.email ||
      'Unknown';

    const body = (dto.body ?? '').trim();
    const msg = await this.prisma.partnerMessage.create({
      data: {
        partnershipId: p.id,
        senderTenantId: me,
        senderUserId: user.sub,
        senderName,
        body,
      },
    });

    const myName =
      (p.requesterTenantId === me ? p.requesterTenant : p.addresseeTenant)?.name ??
      (await this.tenantName(me));
    void this.notifications.sendToTenantRoles(this.otherTenantId(p, me), ['ADMIN', 'MANAGER'], {
      title: myName,
      body: body.slice(0, 120),
      data: { type: 'partner_message', partnershipId: p.id },
    });

    return {
      id: msg.id,
      body: msg.body,
      createdAt: msg.createdAt,
      fromMe: true,
      senderName: msg.senderName,
    };
  }
}
