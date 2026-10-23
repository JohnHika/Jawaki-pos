import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { LegacyUserRole, Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PermissionsService } from '../permissions/permissions.service';
import {
  AccountabilitySettings,
  resolveAccountabilitySettings,
} from './accountability.settings';
import {
  assessCredit,
  assessSalePricing,
  SaleLineInput,
  Severity,
  Violation,
} from './accountability.rules';

export interface RaiseAlertParams {
  tenantId: string;
  branchId?: string | null;
  type: string;
  severity: Severity;
  title: string;
  body: string;
  actorUserId?: string | null;
  entityType?: string;
  entityId?: string | null;
  data?: Record<string, unknown>;
}

export interface AssessSaleParams {
  userId: string;
  tenantId: string;
  branchId: string;
  customerId?: string | null;
  lines: SaleLineInput[];
  overallDiscount: number;
  /** The portion of the sale that goes on credit (KES). */
  creditAmount: number;
  /**
   * True when the till is waiting on this answer (a live sale). Sales that
   * arrive from the offline queue have already happened at the counter, so
   * they are flagged but never refused — refusing would silently lose a sale
   * the customer already paid for.
   */
  enforce: boolean;
}

export interface SaleAssessment {
  violations: Violation[];
  blocked: boolean;
}

export const OWNER_ROLES: LegacyUserRole[] = [LegacyUserRole.ADMIN];
export const MANAGER_ROLES: LegacyUserRole[] = [LegacyUserRole.ADMIN, LegacyUserRole.MANAGER];

@Injectable()
export class AccountabilityService {
  private readonly logger = new Logger(AccountabilityService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
    private readonly permissions: PermissionsService,
  ) {}

  // ------------------------------------------------------------------ settings

  async getSettings(tenantId: string): Promise<AccountabilitySettings> {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { settings: true },
    });
    return resolveAccountabilitySettings(
      (tenant?.settings as Record<string, unknown> | null)?.accountability,
    );
  }

  async updateSettings(
    tenantId: string,
    userId: string,
    patch: Record<string, any>,
  ): Promise<AccountabilitySettings> {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { settings: true },
    });
    const all = ((tenant?.settings as Record<string, any> | null) ?? {}) as Record<string, any>;
    const before = resolveAccountabilitySettings(all.accountability);

    // Section-wise merge so a client can send only the part it changed.
    const merged = resolveAccountabilitySettings({
      priceGuard: { ...before.priceGuard, ...(patch.priceGuard ?? {}) },
      credit: { ...before.credit, ...(patch.credit ?? {}) },
      alerts: { ...before.alerts, ...(patch.alerts ?? {}) },
      dailySummary: { ...before.dailySummary, ...(patch.dailySummary ?? {}) },
      stocktake: { ...before.stocktake, ...(patch.stocktake ?? {}) },
    });

    await this.prisma.tenant.update({
      where: { id: tenantId },
      data: { settings: { ...all, accountability: merged } as unknown as Prisma.InputJsonValue },
    });

    await this.audit.record({
      userId,
      action: 'ACCOUNTABILITY_SETTINGS_UPDATED',
      entityType: 'Tenant',
      entityId: tenantId,
      oldValues: before as unknown as Record<string, unknown>,
      newValues: merged as unknown as Record<string, unknown>,
    });
    return merged;
  }

  // ------------------------------------------------------------------ the till

  /**
   * Everything a phone needs to apply the price, discount and credit rules
   * itself while offline: the rules, what this user is allowed to override,
   * and the lowest acceptable price for each product. The server cannot stop
   * a sale rung up with no signal, so the till has to carry the rules.
   */
  async tillRules(tenantId: string, userId: string) {
    const settings = await this.getSettings(tenantId);
    const [canDiscount, canOverridePrice, canOverrideCredit] = await Promise.all([
      this.userHas(userId, 'sales.discount'),
      this.userHas(userId, 'sales.price_override'),
      this.userHas(userId, 'sales.credit_override'),
    ]);

    const margin = settings.priceGuard.minMarginPercent / 100;
    const products = await this.prisma.product.findMany({
      where: {
        tenantId,
        isActive: true,
        OR: [{ costPrice: { gt: 0 } }, { minPrice: { gt: 0 } }],
      },
      select: { id: true, costPrice: true, minPrice: true },
    });

    const floors = products
      .map((p) => {
        const cost = p.costPrice === null ? 0 : Number(p.costPrice);
        const min = p.minPrice === null ? 0 : Number(p.minPrice);
        const floor = Math.max(min, cost > 0 ? cost * (1 + margin) : 0);
        return {
          productId: p.id,
          cost: Math.round(cost * 100) / 100,
          floor: Math.round(floor * 100) / 100,
        };
      })
      .filter((f) => f.floor > 0 || f.cost > 0);

    return {
      priceGuard: settings.priceGuard,
      credit: settings.credit,
      can: { discount: canDiscount, overridePrice: canOverridePrice, overrideCredit: canOverrideCredit },
      floors,
      generatedAt: new Date().toISOString(),
    };
  }

  // --------------------------------------------------------------- permissions

  async userHas(userId: string, permission: string): Promise<boolean> {
    try {
      const granted = await this.permissions.getEffectivePermissions(userId);
      return granted.includes(permission);
    } catch (error) {
      this.logger.warn(`Permission lookup failed for ${userId}: ${error}`);
      return false;
    }
  }

  // ------------------------------------------------------------------ the sale

  /**
   * Checks a sale against the company's price, discount and credit rules.
   * Returns the violations and whether this sale must be refused. Never
   * throws for a lookup failure: if the check itself breaks, the sale goes
   * through — the till must not stop because the guard did.
   */
  async assessSale(params: AssessSaleParams): Promise<SaleAssessment> {
    try {
      const settings = await this.getSettings(params.tenantId);
      const priceOn = settings.priceGuard.mode !== 'OFF';
      const creditOn = settings.credit.mode !== 'OFF' && params.creditAmount > 0;
      if (!priceOn && !creditOn) return { violations: [], blocked: false };

      const [canDiscount, canOverridePrice, canOverrideCredit] = await Promise.all([
        this.userHas(params.userId, 'sales.discount'),
        this.userHas(params.userId, 'sales.price_override'),
        creditOn ? this.userHas(params.userId, 'sales.credit_override') : Promise.resolve(false),
      ]);

      const priceViolations = priceOn
        ? assessSalePricing({
            lines: params.lines,
            overallDiscount: params.overallDiscount,
            settings,
            canDiscount,
            canOverridePrice,
          })
        : [];

      let creditViolations: Violation[] = [];
      if (creditOn) {
        const standing = await this.customerStanding(params.tenantId, params.customerId);
        creditViolations = assessCredit({
          creditAmount: params.creditAmount,
          hasCustomer: !!params.customerId && !!standing.customer,
          customerName: standing.customer?.name,
          customerLimit: standing.customer?.creditLimit ?? null,
          outstanding: standing.outstanding,
          oldestOverdueDays: standing.oldestOverdueDays,
          settings,
        }).map((v) => ({ ...v, blockable: v.blockable && !canOverrideCredit }));
      }

      const violations = [...priceViolations, ...creditViolations];
      const priceBlocks =
        settings.priceGuard.mode === 'BLOCK' &&
        priceViolations.some((v) => v.blockable);
      const creditBlocks =
        settings.credit.mode === 'BLOCK' && creditViolations.some((v) => v.blockable);

      return { violations, blocked: params.enforce && (priceBlocks || creditBlocks) };
    } catch (error) {
      this.logger.error(`Sale assessment failed, allowing sale: ${error}`);
      return { violations: [], blocked: false };
    }
  }

  /** Throws the structured 403 the till shows as "needs a manager". */
  refuse(violations: Violation[]): never {
    const blocking = violations.filter((v) => v.blockable);
    throw new ForbiddenException({
      statusCode: 403,
      code: 'ACCOUNTABILITY_BLOCKED',
      message: blocking.map((v) => v.message).join('; ') || 'This sale needs a manager to approve it',
      violations: blocking,
    });
  }

  /** Records the violations of a sale that was allowed through. */
  async flagSale(
    params: { tenantId: string; branchId: string; userId: string; saleId: string; receiptNumber: string },
    violations: Violation[],
  ): Promise<void> {
    if (violations.length === 0) return;
    const actor = await this.actorName(params.userId);
    await Promise.all(
      violations.map((v) =>
        this.raise({
          tenantId: params.tenantId,
          branchId: params.branchId,
          type: v.code,
          severity: v.severity,
          title: this.titleFor(v.code),
          body: `${actor}: ${v.message} (receipt ${params.receiptNumber})`,
          actorUserId: params.userId,
          entityType: 'Sale',
          entityId: params.saleId,
          data: { ...(v.data ?? {}), productId: v.productId, receiptNumber: params.receiptNumber },
        }),
      ),
    );
  }

  private titleFor(code: Violation['code']): string {
    switch (code) {
      case 'BELOW_COST':
        return 'Sold below cost';
      case 'BELOW_FLOOR':
        return 'Sold under minimum price';
      case 'DISCOUNT_LIMIT':
        return 'Discount over limit';
      case 'CREDIT_NO_CUSTOMER':
        return 'Credit with no customer';
      case 'CREDIT_LIMIT_EXCEEDED':
        return 'Credit limit exceeded';
      case 'CREDIT_OVERDUE':
        return 'Credit to an overdue customer';
      default:
        return 'Needs review';
    }
  }

  /** What a customer owes, their limit, and how overdue their oldest balance is. */
  async customerStanding(tenantId: string, customerId?: string | null) {
    if (!customerId) return { customer: null, outstanding: 0, oldestOverdueDays: 0 };
    const customer = await this.prisma.customer.findFirst({
      where: { id: customerId, tenantId },
      select: { id: true, name: true, creditLimit: true },
    });
    if (!customer) return { customer: null, outstanding: 0, oldestOverdueDays: 0 };

    const open = await this.prisma.retailReceivable.findMany({
      where: { tenantId, customerId, status: { in: ['OPEN', 'PARTIAL'] } },
      select: { outstandingAmount: true, dueDate: true },
    });
    const now = Date.now();
    let outstanding = 0;
    let oldestOverdueDays = 0;
    for (const r of open) {
      outstanding += Number(r.outstandingAmount);
      if (r.dueDate && r.dueDate.getTime() < now) {
        oldestOverdueDays = Math.max(
          oldestOverdueDays,
          Math.floor((now - r.dueDate.getTime()) / 86_400_000),
        );
      }
    }
    return {
      customer: {
        name: customer.name,
        creditLimit: customer.creditLimit === null ? null : Number(customer.creditLimit),
      },
      outstanding,
      oldestOverdueDays,
    };
  }

  // -------------------------------------------------------------------- alerts

  /**
   * Stores an alert and, when it is HIGH, pushes it to the owner. Never
   * throws: an alert failing must not undo the sale/adjustment it describes.
   */
  async raise(params: RaiseAlertParams): Promise<void> {
    try {
      await this.prisma.accountabilityAlert.create({
        data: {
          tenantId: params.tenantId,
          branchId: params.branchId ?? null,
          type: params.type,
          severity: params.severity,
          title: params.title,
          body: params.body,
          actorUserId: params.actorUserId ?? null,
          entityType: params.entityType ?? null,
          entityId: params.entityId ?? null,
          data: (params.data ?? {}) as Prisma.InputJsonValue,
        },
      });

      if (params.severity === 'HIGH') {
        const settings = await this.getSettings(params.tenantId);
        if (settings.alerts.pushHigh) {
          await this.notifications.sendToTenantRoles(params.tenantId, OWNER_ROLES, {
            title: params.title,
            body: params.body,
            data: { type: 'accountability_alert', alertType: params.type },
          });
        }
      }
    } catch (error) {
      this.logger.error(`Failed to raise alert ${params.type}: ${error}`);
    }
  }

  async record(params: Parameters<AuditService['record']>[0]): Promise<void> {
    await this.audit.record(params);
  }

  async actorName(userId?: string | null): Promise<string> {
    if (!userId) return 'Someone';
    try {
      const user = await this.prisma.user.findUnique({
        where: { id: userId },
        select: { firstName: true, lastName: true },
      });
      const name = [user?.firstName, user?.lastName].filter(Boolean).join(' ').trim();
      return name || 'A staff member';
    } catch {
      return 'A staff member';
    }
  }

  async list(
    tenantId: string,
    query: {
      branchId?: string;
      severity?: string;
      type?: string;
      open?: boolean;
      page?: number;
      limit?: number;
    },
  ) {
    const page = Math.max(query.page ?? 1, 1);
    const limit = Math.min(Math.max(query.limit ?? 30, 1), 100);
    const where: Prisma.AccountabilityAlertWhereInput = { tenantId };
    if (query.branchId) where.branchId = query.branchId;
    if (query.severity) where.severity = query.severity;
    if (query.type) where.type = query.type;
    if (query.open) where.acknowledgedAt = null;

    const [items, total, openCount, openHigh] = await Promise.all([
      this.prisma.accountabilityAlert.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.accountabilityAlert.count({ where }),
      this.prisma.accountabilityAlert.count({ where: { tenantId, acknowledgedAt: null } }),
      this.prisma.accountabilityAlert.count({
        where: { tenantId, acknowledgedAt: null, severity: 'HIGH' },
      }),
    ]);

    const actorIds = [...new Set(items.map((i) => i.actorUserId).filter(Boolean) as string[])];
    const users = actorIds.length
      ? await this.prisma.user.findMany({
          where: { id: { in: actorIds }, tenantId },
          select: { id: true, firstName: true, lastName: true },
        })
      : [];
    const names = new Map(
      users.map((u) => [u.id, [u.firstName, u.lastName].filter(Boolean).join(' ').trim()]),
    );

    return {
      items: items.map((a) => ({
        id: a.id,
        type: a.type,
        severity: a.severity,
        title: a.title,
        body: a.body,
        branchId: a.branchId,
        actorUserId: a.actorUserId,
        actorName: a.actorUserId ? names.get(a.actorUserId) || null : null,
        entityType: a.entityType,
        entityId: a.entityId,
        data: a.data,
        acknowledged: !!a.acknowledgedAt,
        acknowledgedAt: a.acknowledgedAt,
        createdAt: a.createdAt,
      })),
      total,
      page,
      limit,
      openCount,
      openHigh,
    };
  }

  async acknowledge(tenantId: string, userId: string, ids: string[] | 'all') {
    const where: Prisma.AccountabilityAlertWhereInput = { tenantId, acknowledgedAt: null };
    if (ids !== 'all') where.id = { in: ids };
    const result = await this.prisma.accountabilityAlert.updateMany({
      where,
      data: { acknowledgedAt: new Date(), acknowledgedById: userId },
    });
    return { acknowledged: result.count };
  }
}
