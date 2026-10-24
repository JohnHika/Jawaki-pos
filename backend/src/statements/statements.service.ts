import {
  BadRequestException,
  ConflictException,
  GoneException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma, StatementLink } from '@prisma/client';
import { randomBytes } from 'crypto';
import pdfMake = require('pdfmake');
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { NotificationsService } from '../notifications/notifications.service';
import { ReferralsService } from '../referrals/referrals.service';
import { DebtCollectionService, DebtTarget } from './debt-collection.service';
import {
  ClaimsQueryDto,
  CreateStatementLinkDto,
  DecideClaimDto,
  PublicClaimDto,
  UpdateStatementSettingsDto,
} from './dto/statements.dto';
import { buildStatementPdf, formatKes, shareMessage } from './statements.render';
import { Lang, StatementItem, StatementPayment, StatementView } from './statements.types';
import { LegacyUserRole } from '@prisma/client';

const DAY_MS = 86_400_000;
const DEFAULT_LINK_DAYS = 14;
const MAX_OPEN_CLAIMS_PER_LINK = 10;
const MANAGER_ROLES = [LegacyUserRole.ADMIN, LegacyUserRole.MANAGER];

/** Link-preview fetchers (WhatsApp, Telegram...) must not count as the customer reading it. */
const BOT_AGENT = /bot|crawler|spider|preview|whatsapp|facebookexternalhit|slack|embedly|curl|wget|python-requests/i;

function notFound(message: string): HttpException {
  return new HttpException({ statusCode: 404, message, error: 'Not Found' }, HttpStatus.NOT_FOUND);
}

export function overdueDaysFor(dueDate: Date | null, now: Date): number {
  if (!dueDate || dueDate.getTime() >= now.getTime()) return 0;
  return Math.max(1, Math.floor((now.getTime() - dueDate.getTime()) / DAY_MS));
}

@Injectable()
export class StatementsService {
  private readonly logger = new Logger(StatementsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
    private readonly referrals: ReferralsService,
    private readonly collections: DebtCollectionService,
  ) {
    // Same built-in fonts as the report exports: nothing to ship or host.
    pdfMake.setFonts({
      Helvetica: {
        normal: 'Helvetica',
        bold: 'Helvetica-Bold',
        italics: 'Helvetica-Oblique',
        bolditalics: 'Helvetica-BoldOblique',
      },
    });
    pdfMake.setUrlAccessPolicy(() => false);
  }

  // ------------------------------------------------------------ settings

  async getSettings(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({ where: { id: tenantId }, select: { settings: true } });
    const stored = ((tenant?.settings as any)?.statements ?? {}) as Record<string, unknown>;
    return {
      payInstructions: typeof stored.payInstructions === 'string' ? stored.payInstructions : '',
      phone: typeof stored.phone === 'string' ? stored.phone : '',
    };
  }

  async updateSettings(userId: string, tenantId: string, dto: UpdateStatementSettingsDto) {
    const tenant = await this.prisma.tenant.findUnique({ where: { id: tenantId }, select: { settings: true } });
    if (!tenant) throw notFound('Company not found');
    const settings = ((tenant.settings as Record<string, unknown>) ?? {}) as Record<string, unknown>;
    const current = await this.getSettings(tenantId);
    const next = {
      payInstructions: (dto.payInstructions ?? current.payInstructions).trim(),
      phone: (dto.phone ?? current.phone).trim(),
    };
    await this.prisma.tenant.update({
      where: { id: tenantId },
      data: { settings: { ...settings, statements: next } as unknown as Prisma.InputJsonValue },
    });
    await this.audit.record({
      userId,
      action: 'STATEMENT_SETTINGS_UPDATED',
      entityType: 'Tenant',
      entityId: tenantId,
      oldValues: current,
      newValues: next,
    });
    return next;
  }

  // ------------------------------------------------------------- the view

  private async targetName(tenantId: string, target: DebtTarget) {
    if (target.customerId) {
      const customer = await this.prisma.customer.findFirst({
        where: { id: target.customerId, tenantId },
        select: { name: true },
      });
      if (!customer) throw notFound('Customer not found');
      return { name: customer.name, kind: 'CUSTOMER' as const };
    }
    if (target.debtorId) {
      const debtor = await this.prisma.peerDebtor.findFirst({
        where: { id: target.debtorId, tenantId },
        select: { name: true },
      });
      if (!debtor) throw notFound('Shop not found');
      return { name: debtor.name, kind: 'SHOP' as const };
    }
    throw new BadRequestException('Name a customer or a shop');
  }

  /** Current state of what one customer or shop owes, built fresh every time it is read. */
  async buildView(
    tenantId: string,
    target: DebtTarget,
    extras: { message?: string | null; expiresAt?: Date | null } = {},
  ): Promise<StatementView> {
    const now = new Date();
    const who = await this.targetName(tenantId, target);

    let items: StatementItem[] = [];
    let payments: StatementPayment[] = [];

    if (target.customerId) {
      const [rows, paid] = await Promise.all([
        this.prisma.retailReceivable.findMany({
          where: { tenantId, customerId: target.customerId, status: { in: ['OPEN', 'PARTIAL'] } },
          orderBy: { createdAt: 'asc' },
          take: 100,
          include: {
            sale: {
              select: {
                receiptNumber: true,
                createdAt: true,
                items: { select: { productName: true, quantity: true }, take: 4 },
              },
            },
          },
        }),
        this.prisma.retailReceivablePayment.findMany({
          where: { tenantId, receivable: { customerId: target.customerId } },
          orderBy: { paidAt: 'desc' },
          take: 8,
        }),
      ]);
      items = rows.map((row) => {
        const original = Number(row.originalAmount);
        const outstanding = Number(row.outstandingAmount);
        const lines = row.sale.items.map((i) => `${i.productName} x${Number(i.quantity)}`);
        return {
          date: row.sale.createdAt,
          reference: row.sale.receiptNumber,
          description: lines.join(', '),
          original,
          paid: Math.round((original - outstanding) * 100) / 100,
          outstanding,
          dueDate: row.dueDate,
          overdueDays: overdueDaysFor(row.dueDate, now),
        };
      });
      payments = paid.map((p) => ({
        date: p.paidAt,
        amount: Number(p.amount),
        method: p.method,
        reference: p.reference,
      }));
    } else {
      const [rows, paid] = await Promise.all([
        this.prisma.peerReceivable.findMany({
          where: { tenantId, debtorId: target.debtorId, status: { in: ['OPEN', 'PARTIAL'] } },
          orderBy: { createdAt: 'asc' },
          take: 100,
        }),
        this.prisma.peerReceivablePayment.findMany({
          where: { tenantId, receivable: { debtorId: target.debtorId } },
          orderBy: { paidAt: 'desc' },
          take: 8,
        }),
      ]);
      items = rows.map((row) => {
        const original = Number(row.originalAmount);
        const outstanding = Number(row.outstandingAmount);
        return {
          date: row.createdAt,
          reference: row.reference || 'Invoice',
          description: row.description,
          original,
          paid: Math.round((original - outstanding) * 100) / 100,
          outstanding,
          dueDate: row.dueDate,
          overdueDays: overdueDaysFor(row.dueDate, now),
        };
      });
      payments = paid.map((p) => ({
        date: p.paidAt,
        amount: Number(p.amount),
        method: p.method,
        reference: p.reference,
      }));
    }

    const outstanding = Math.round(items.reduce((s, i) => s + i.outstanding, 0) * 100) / 100;
    const overdue = Math.round(items.filter((i) => i.overdueDays > 0).reduce((s, i) => s + i.outstanding, 0) * 100) / 100;

    const [tenant, branch, settings, inviteCode] = await Promise.all([
      this.prisma.tenant.findUnique({ where: { id: tenantId }, select: { name: true, logo: true } }),
      this.prisma.branch.findFirst({
        where: { tenantId, phone: { not: null } },
        select: { phone: true },
        orderBy: { createdAt: 'asc' },
      }),
      this.getSettings(tenantId),
      this.referrals.getOrCreateCode(tenantId).catch(() => null),
    ]);

    return {
      business: {
        name: tenant?.name ?? 'Your supplier',
        phone: settings.phone || branch?.phone || null,
        logo: tenant?.logo && tenant.logo.startsWith('https://') ? tenant.logo : null,
        payInstructions: settings.payInstructions || null,
      },
      debtor: who,
      asOf: now,
      outstanding,
      overdue,
      oldestOverdueDays: items.reduce((max, i) => Math.max(max, i.overdueDays), 0),
      items,
      payments,
      message: extras.message ?? null,
      expiresAt: extras.expiresAt ?? null,
      inviteCode,
    };
  }

  async preview(tenantId: string, target: DebtTarget) {
    return this.buildView(tenantId, target);
  }

  // ---------------------------------------------------------------- links

  /** Where the page lives, e.g. https://api.example.com. Null when no public address is configured. */
  publicOrigin(): string | null {
    const base = [
      this.config.get<string>('PUBLIC_API_URL'),
      this.config.get<string>('API_PUBLIC_URL'),
      this.config.get<string>('RENDER_EXTERNAL_URL'),
    ].find((value) => value?.trim());
    if (!base) return null;
    return base.trim().replace(/\/+$/, '').replace(/\/api\/v\d+$/, '');
  }

  private linkUrl(token: string): { path: string; url: string | null } {
    const path = `/s/${token}`;
    const origin = this.publicOrigin();
    return { path, url: origin ? `${origin}${path}` : null };
  }

  async createLink(userId: string, tenantId: string, dto: CreateStatementLinkDto) {
    if (!dto.customerId === !dto.debtorId) {
      throw new BadRequestException('Name either a customer or a shop');
    }
    const target: DebtTarget = { customerId: dto.customerId, debtorId: dto.debtorId };
    const message = dto.message?.trim() || null;
    const days = dto.days ?? DEFAULT_LINK_DAYS;
    const expiresAt = new Date(Date.now() + days * DAY_MS);

    const view = await this.buildView(tenantId, target, { message, expiresAt });
    if (view.outstanding <= 0) {
      throw new BadRequestException(`${view.debtor.name} does not owe anything right now`);
    }

    const token = randomBytes(24).toString('base64url');
    const link = await this.prisma.statementLink.create({
      data: {
        tenantId,
        token,
        kind: dto.customerId ? 'CUSTOMER' : 'SHOP',
        customerId: dto.customerId ?? null,
        debtorId: dto.debtorId ?? null,
        message,
        createdById: userId,
        expiresAt,
      },
    });
    await this.audit.record({
      userId,
      action: 'STATEMENT_LINK_CREATED',
      entityType: 'StatementLink',
      entityId: link.id,
      newValues: { kind: link.kind, debtor: view.debtor.name, outstanding: view.outstanding, expiresAt },
    });

    const where = this.linkUrl(token);
    const shareUrl = where.url ?? where.path;
    return {
      id: link.id,
      token,
      ...where,
      expiresAt,
      outstanding: view.outstanding,
      debtorName: view.debtor.name,
      // Ready-to-send WhatsApp text in both languages; the app picks one.
      shareText: {
        en: shareMessage(view, shareUrl, 'en'),
        sw: shareMessage(view, shareUrl, 'sw'),
      },
    };
  }

  async listLinks(tenantId: string, target: DebtTarget) {
    const links = await this.prisma.statementLink.findMany({
      where: {
        tenantId,
        ...(target.customerId ? { customerId: target.customerId } : {}),
        ...(target.debtorId ? { debtorId: target.debtorId } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: 30,
      include: { _count: { select: { claims: true } } },
    });
    const now = Date.now();
    return links.map((link) => ({
      id: link.id,
      ...this.linkUrl(link.token),
      createdAt: link.createdAt,
      expiresAt: link.expiresAt,
      revoked: !!link.revokedAt,
      expired: link.expiresAt.getTime() < now,
      viewCount: link.viewCount,
      firstViewedAt: link.firstViewedAt,
      lastViewedAt: link.lastViewedAt,
      claims: link._count.claims,
    }));
  }

  async revoke(userId: string, tenantId: string, id: string) {
    const link = await this.prisma.statementLink.findFirst({ where: { id, tenantId } });
    if (!link) throw notFound('Link not found');
    await this.prisma.statementLink.update({ where: { id }, data: { revokedAt: link.revokedAt ?? new Date() } });
    await this.audit.record({ userId, action: 'STATEMENT_LINK_REVOKED', entityType: 'StatementLink', entityId: id });
    return { id, revoked: true };
  }

  // --------------------------------------------------------------- public

  /** The link, only if it can still be opened. Callers show one neutral "expired" page for all failures. */
  async findUsableLink(token: string): Promise<StatementLink | null> {
    if (!token || token.length < 20 || token.length > 64) return null;
    const link = await this.prisma.statementLink.findUnique({ where: { token } });
    if (!link || link.revokedAt || link.expiresAt.getTime() < Date.now()) return null;
    return link;
  }

  /**
   * Builds the page data. A visit is only counted (and the owner told) when a
   * real browser asks for the page: not a link-preview robot, and not the
   * owner's own phone downloading the PDF to send it.
   */
  async openLink(token: string, userAgent?: string, track = true): Promise<StatementView | null> {
    const link = await this.findUsableLink(token);
    if (!link) return null;
    const view = await this.buildView(
      link.tenantId,
      { customerId: link.customerId, debtorId: link.debtorId },
      { message: link.message, expiresAt: link.expiresAt },
    );
    if (track && userAgent && !BOT_AGENT.test(userAgent)) {
      void this.recordView(link, view).catch((error) => this.logger.error(`View tracking failed: ${error}`));
    }
    return view;
  }

  private async recordView(link: StatementLink, view: StatementView): Promise<void> {
    const first = !link.firstViewedAt;
    await this.prisma.statementLink.update({
      where: { id: link.id },
      data: {
        viewCount: { increment: 1 },
        lastViewedAt: new Date(),
        ...(first ? { firstViewedAt: new Date() } : {}),
      },
    });
    if (first) {
      await this.notifications.sendToUser(
        link.createdById,
        {
          title: 'Statement opened',
          body: `${view.debtor.name} opened the statement you sent (${formatKes(view.outstanding)}).`,
          data: { type: 'statement_viewed', linkId: link.id },
        },
        { tenantId: link.tenantId },
      );
    }
  }

  async renderPdfForToken(token: string, lang: Lang): Promise<{ buffer: Buffer; filename: string } | null> {
    const view = await this.openLink(token, undefined, false);
    if (!view) return null;
    const buffer = await pdfMake.createPdf(buildStatementPdf(view, lang) as any).getBuffer();
    const slug = view.debtor.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'statement';
    return { buffer, filename: `statement-${slug}.pdf` };
  }

  /** "I have paid" or "I will pay on", sent from the public page. */
  async submitClaim(token: string, dto: PublicClaimDto) {
    const link = await this.findUsableLink(token);
    if (!link) throw new GoneException('This link has expired.');
    const target: DebtTarget = { customerId: link.customerId, debtorId: link.debtorId };
    const outstanding = await this.collections.outstandingFor(link.tenantId, target);
    if (outstanding <= 0) {
      return { received: true, message: 'You do not owe anything right now. Thank you!' };
    }

    const pending = await this.prisma.statementClaim.count({
      where: { linkId: link.id, status: 'PENDING' },
    });
    if (pending >= MAX_OPEN_CLAIMS_PER_LINK) {
      throw new HttpException('Too many replies are waiting. Please call the shop.', HttpStatus.TOO_MANY_REQUESTS);
    }

    let data: Prisma.StatementClaimUncheckedCreateInput;
    if (dto.kind === 'PAID') {
      if (!dto.mpesaCode) throw new BadRequestException('Enter the M-Pesa code from your message.');
      if (!dto.amount) throw new BadRequestException('Enter the amount you paid.');
      const code = dto.mpesaCode.toUpperCase();
      const duplicate = await this.prisma.statementClaim.findFirst({
        where: { tenantId: link.tenantId, mpesaCode: code, status: { not: 'REJECTED' } },
        select: { id: true },
      });
      if (duplicate) throw new ConflictException('That M-Pesa code has already been sent. Thank you.');
      data = {
        linkId: link.id,
        tenantId: link.tenantId,
        kind: 'PAID',
        amount: Math.min(dto.amount, outstanding),
        mpesaCode: code,
        payerName: dto.payerName?.trim() || null,
        note: dto.note?.trim() || null,
      };
    } else {
      if (!dto.promisedFor) throw new BadRequestException('Choose the date you will pay.');
      const when = new Date(dto.promisedFor);
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      if (Number.isNaN(when.getTime()) || when.getTime() < today.getTime() || when.getTime() > today.getTime() + 60 * DAY_MS) {
        throw new BadRequestException('Choose a date within the next 60 days.');
      }
      data = {
        linkId: link.id,
        tenantId: link.tenantId,
        kind: 'PROMISE',
        promisedFor: when,
        payerName: dto.payerName?.trim() || null,
        note: dto.note?.trim() || null,
      };
    }

    const claim = await this.prisma.statementClaim.create({ data });
    await this.notifyClaim(link, claim);
    const shop = (await this.prisma.tenant.findUnique({ where: { id: link.tenantId }, select: { name: true } }))?.name;
    return { received: true, message: `Thank you. ${shop ?? 'The shop'} has been told.` };
  }

  private async notifyClaim(link: StatementLink, claim: { id: string; kind: string; amount: Prisma.Decimal | null; payerName: string | null; promisedFor: Date | null }) {
    try {
      const name = await this.targetName(link.tenantId, {
        customerId: link.customerId,
        debtorId: link.debtorId,
      }).then((w) => w.name);
      const body =
        claim.kind === 'PAID'
          ? `${name} says they paid ${formatKes(Number(claim.amount))} by M-Pesa. Open Statements to confirm.`
          : `${name} promised to pay on ${claim.promisedFor?.toISOString().slice(0, 10)}.`;
      const managers = await this.prisma.user.findMany({
        where: { tenantId: link.tenantId, isActive: true, role: { in: MANAGER_ROLES } },
        select: { id: true },
      });
      const ids = new Set([link.createdById, ...managers.map((m) => m.id)]);
      await Promise.all(
        [...ids].map((id) =>
          this.notifications.sendToUser(
            id,
            {
              title: claim.kind === 'PAID' ? 'A customer says they paid' : 'A customer promised to pay',
              body,
              data: { type: 'statement_claim', claimId: claim.id },
            },
            { tenantId: link.tenantId },
          ),
        ),
      );
    } catch (error) {
      this.logger.error(`Claim notification failed: ${error}`);
    }
  }

  // --------------------------------------------------------------- claims

  async listClaims(tenantId: string, query: ClaimsQueryDto) {
    const claims = await this.prisma.statementClaim.findMany({
      where: { tenantId, ...(query.status ? { status: query.status } : {}) },
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: { link: { select: { customerId: true, debtorId: true, kind: true } } },
    });
    const customerIds = [...new Set(claims.map((c) => c.link.customerId).filter(Boolean))] as string[];
    const debtorIds = [...new Set(claims.map((c) => c.link.debtorId).filter(Boolean))] as string[];
    const [customers, debtors] = await Promise.all([
      this.prisma.customer.findMany({ where: { id: { in: customerIds }, tenantId }, select: { id: true, name: true, phone: true } }),
      this.prisma.peerDebtor.findMany({ where: { id: { in: debtorIds }, tenantId }, select: { id: true, name: true, phone: true } }),
    ]);
    const customerOf = new Map(customers.map((c) => [c.id, c]));
    const debtorOf = new Map(debtors.map((d) => [d.id, d]));

    return Promise.all(
      claims.map(async (claim) => {
        const customer = claim.link.customerId ? customerOf.get(claim.link.customerId) : undefined;
        const debtor = claim.link.debtorId ? debtorOf.get(claim.link.debtorId) : undefined;
        const outstanding = await this.collections.outstandingFor(tenantId, {
          customerId: claim.link.customerId,
          debtorId: claim.link.debtorId,
        });
        return {
          id: claim.id,
          kind: claim.kind,
          status: claim.status,
          amount: claim.amount != null ? Number(claim.amount) : null,
          mpesaCode: claim.mpesaCode,
          promisedFor: claim.promisedFor,
          payerName: claim.payerName,
          note: claim.note,
          createdAt: claim.createdAt,
          decidedAt: claim.decidedAt,
          debtorKind: claim.link.kind,
          debtorName: customer?.name ?? debtor?.name ?? 'Unknown',
          debtorPhone: customer?.phone ?? debtor?.phone ?? null,
          customerId: claim.link.customerId,
          debtorId: claim.link.debtorId,
          outstanding,
        };
      }),
    );
  }

  async decideClaim(userId: string, tenantId: string, claimId: string, dto: DecideClaimDto) {
    const claim = await this.prisma.statementClaim.findFirst({
      where: { id: claimId, tenantId },
      include: { link: true },
    });
    if (!claim) throw notFound('Reply not found');
    if (claim.status !== 'PENDING') throw new ConflictException('This reply was already handled');

    if (dto.action === 'REJECT') {
      await this.prisma.statementClaim.update({
        where: { id: claimId },
        data: { status: 'REJECTED', decidedAt: new Date(), decidedById: userId },
      });
      await this.audit.record({ userId, action: 'STATEMENT_CLAIM_REJECTED', entityType: 'StatementClaim', entityId: claimId });
      return { id: claimId, status: 'REJECTED', applied: 0, unallocated: 0 };
    }

    // A promise is only acknowledged; nothing is paid yet.
    if (claim.kind === 'PROMISE') {
      await this.prisma.statementClaim.update({
        where: { id: claimId },
        data: { status: 'CONFIRMED', decidedAt: new Date(), decidedById: userId },
      });
      return { id: claimId, status: 'CONFIRMED', applied: 0, unallocated: 0 };
    }

    throw new BadRequestException(
      'A customer-reported M-Pesa code is not proof of payment. Verify it in Paystack or match it against a trusted M-Pesa statement before recording money.',
    );
  }
}
