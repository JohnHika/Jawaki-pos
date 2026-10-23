import {
  BadRequestException,
  ConflictException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { randomInt } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { AccountabilityService } from '../accountability/accountability.service';
import {
  CouponDef,
  CouponLine,
  CouponVerdict,
  describeCoupon,
  evaluateCoupon,
  normaliseCouponCode,
  round2,
} from './coupons.rules';
import { CheckCouponDto, CreateCouponDto, UpdateCouponDto } from './dto/coupons.dto';

type CouponRow = Prisma.CouponGetPayload<Record<string, never>>;

// No 0/O/1/I so a code read out over the counter is not mistyped.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Plain 404 (the global interceptor turns NotFoundException into a 401 for signed-in callers). */
function notFound(message: string): HttpException {
  return new HttpException({ statusCode: 404, message, error: 'Not Found' }, HttpStatus.NOT_FOUND);
}

export interface SaleCouponAssessment {
  couponId: string | null;
  code: string;
  /** The products the coupon is limited to; empty means the whole sale. */
  productIds: string[];
  verdict: CouponVerdict;
}

export interface SaleCouponUse {
  couponId: string;
  code: string;
  amount: number;
  productIds: string[];
}

@Injectable()
export class CouponsService {
  private readonly logger = new Logger(CouponsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly accountability: AccountabilityService,
  ) {}

  // ------------------------------------------------------------- shaping

  toDef(row: CouponRow): CouponDef {
    return {
      code: row.code,
      kind: row.kind,
      value: Number(row.value),
      maxDiscount: row.maxDiscount != null ? Number(row.maxDiscount) : null,
      minSpend: row.minSpend != null ? Number(row.minSpend) : null,
      startsAt: row.startsAt,
      expiresAt: row.expiresAt,
      usageLimit: row.usageLimit,
      usedCount: row.usedCount,
      perCustomerLimit: row.perCustomerLimit,
      customerId: row.customerId,
      productIds: row.productIds ?? [],
      isActive: row.isActive,
    };
  }

  private statusOf(row: CouponRow, now = new Date()): string {
    if (!row.isActive) return 'OFF';
    if (row.startsAt && row.startsAt > now) return 'SCHEDULED';
    if (row.expiresAt && row.expiresAt < now) return 'EXPIRED';
    if (row.usageLimit != null && row.usedCount >= row.usageLimit) return 'USED_UP';
    return 'ACTIVE';
  }

  format(row: CouponRow) {
    const def = this.toDef(row);
    return {
      id: row.id,
      code: row.code,
      name: row.name,
      kind: row.kind,
      value: def.value,
      maxDiscount: def.maxDiscount,
      minSpend: def.minSpend,
      startsAt: row.startsAt,
      expiresAt: row.expiresAt,
      usageLimit: row.usageLimit,
      usedCount: row.usedCount,
      perCustomerLimit: row.perCustomerLimit,
      customerId: row.customerId,
      productIds: def.productIds,
      isActive: row.isActive,
      status: this.statusOf(row),
      description: describeCoupon(def),
      createdAt: row.createdAt,
    };
  }

  // ---------------------------------------------------------- management

  async list(tenantId: string) {
    const rows = await this.prisma.coupon.findMany({
      where: { tenantId },
      orderBy: [{ isActive: 'desc' }, { createdAt: 'desc' }],
      take: 300,
    });
    return rows.map((row) => this.format(row));
  }

  private async generateCode(tenantId: string): Promise<string> {
    for (let attempt = 0; attempt < 8; attempt++) {
      let suffix = '';
      for (let i = 0; i < 5; i++) suffix += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
      const code = `OFF${suffix}`;
      const taken = await this.prisma.coupon.findUnique({
        where: { tenantId_code: { tenantId, code } },
        select: { id: true },
      });
      if (!taken) return code;
    }
    throw new ConflictException('Could not generate a free coupon code. Type one instead.');
  }

  private parseDate(value: string | null | undefined, label: string): Date | null | undefined {
    if (value === undefined) return undefined;
    if (value === null) return null;
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) throw new BadRequestException(`${label} is not a valid date`);
    return date;
  }

  private assertShape(
    kind: 'PERCENT' | 'FIXED',
    value: number,
    startsAt?: Date | null,
    expiresAt?: Date | null,
  ) {
    if (kind === 'PERCENT' && (value <= 0 || value > 100)) {
      throw new BadRequestException('A percent coupon must be between 0 and 100');
    }
    if (startsAt && expiresAt && expiresAt <= startsAt) {
      throw new BadRequestException('The end date must be after the start date');
    }
  }

  async create(userId: string, tenantId: string, dto: CreateCouponDto) {
    const code = dto.code ? normaliseCouponCode(dto.code) : await this.generateCode(tenantId);
    const startsAt = this.parseDate(dto.startsAt, 'Start date') ?? null;
    const expiresAt = this.parseDate(dto.expiresAt, 'End date') ?? null;
    this.assertShape(dto.kind, dto.value, startsAt, expiresAt);

    if (dto.customerId) {
      const customer = await this.prisma.customer.findFirst({
        where: { id: dto.customerId, tenantId },
        select: { id: true },
      });
      if (!customer) throw new BadRequestException('That customer was not found');
    }
    const productIds = [...new Set(dto.productIds ?? [])];
    if (productIds.length) {
      const found = await this.prisma.product.count({ where: { tenantId, id: { in: productIds } } });
      if (found !== productIds.length) throw new BadRequestException('One or more products were not found');
    }

    try {
      const row = await this.prisma.coupon.create({
        data: {
          tenantId,
          code,
          name: dto.name?.trim() || null,
          kind: dto.kind,
          value: dto.value,
          maxDiscount: dto.kind === 'PERCENT' ? (dto.maxDiscount ?? null) : null,
          minSpend: dto.minSpend ?? null,
          startsAt,
          expiresAt,
          usageLimit: dto.usageLimit ?? null,
          perCustomerLimit: dto.perCustomerLimit ?? null,
          customerId: dto.customerId ?? null,
          productIds,
          isActive: dto.isActive ?? true,
          createdById: userId,
        },
      });
      await this.audit.record({
        userId,
        action: 'COUPON_CREATED',
        entityType: 'Coupon',
        entityId: row.id,
        newValues: this.format(row) as unknown as Record<string, unknown>,
      });
      return this.format(row);
    } catch (error: any) {
      if (error?.code === 'P2002') throw new ConflictException(`The code ${code} already exists`);
      throw error;
    }
  }

  async update(userId: string, tenantId: string, id: string, dto: UpdateCouponDto) {
    const existing = await this.prisma.coupon.findFirst({ where: { id, tenantId } });
    if (!existing) throw notFound('Coupon not found');

    const startsAt = this.parseDate(dto.startsAt, 'Start date');
    const expiresAt = this.parseDate(dto.expiresAt, 'End date');
    this.assertShape(
      existing.kind,
      Number(existing.value),
      startsAt === undefined ? existing.startsAt : startsAt,
      expiresAt === undefined ? existing.expiresAt : expiresAt,
    );

    const row = await this.prisma.coupon.update({
      where: { id },
      data: {
        ...(dto.name !== undefined ? { name: dto.name.trim() || null } : {}),
        ...(dto.maxDiscount !== undefined && existing.kind === 'PERCENT'
          ? { maxDiscount: dto.maxDiscount }
          : {}),
        ...(dto.minSpend !== undefined ? { minSpend: dto.minSpend } : {}),
        ...(startsAt !== undefined ? { startsAt } : {}),
        ...(expiresAt !== undefined ? { expiresAt } : {}),
        ...(dto.usageLimit !== undefined ? { usageLimit: dto.usageLimit } : {}),
        ...(dto.perCustomerLimit !== undefined ? { perCustomerLimit: dto.perCustomerLimit } : {}),
        ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
      },
    });
    await this.audit.record({
      userId,
      action: 'COUPON_UPDATED',
      entityType: 'Coupon',
      entityId: id,
      oldValues: this.format(existing) as unknown as Record<string, unknown>,
      newValues: this.format(row) as unknown as Record<string, unknown>,
    });
    return this.format(row);
  }

  /** A coupon that was never used is deleted; one with history is only switched off. */
  async remove(userId: string, tenantId: string, id: string) {
    const existing = await this.prisma.coupon.findFirst({ where: { id, tenantId } });
    if (!existing) throw notFound('Coupon not found');
    const used = await this.prisma.couponRedemption.count({ where: { couponId: id } });
    if (used === 0) {
      await this.prisma.coupon.delete({ where: { id } });
    } else {
      await this.prisma.coupon.update({ where: { id }, data: { isActive: false } });
    }
    await this.audit.record({
      userId,
      action: used === 0 ? 'COUPON_DELETED' : 'COUPON_DEACTIVATED',
      entityType: 'Coupon',
      entityId: id,
      oldValues: { code: existing.code },
    });
    return { id, deleted: used === 0, deactivated: used > 0 };
  }

  // ------------------------------------------------------------ the till

  /**
   * What the phone caches so it can apply coupons with no signal: every code
   * that could still be redeemed. Per-customer limits cannot be checked
   * offline; the server enforces them when the sale syncs.
   */
  async tillList(tenantId: string) {
    const now = new Date();
    const rows = await this.prisma.coupon.findMany({
      where: {
        tenantId,
        isActive: true,
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: { createdAt: 'desc' },
      take: 300,
    });
    return {
      fetchedAt: now,
      coupons: rows
        .filter((row) => row.usageLimit == null || row.usedCount < row.usageLimit)
        .map((row) => {
          const def = this.toDef(row);
          return {
            code: def.code,
            kind: def.kind,
            value: def.value,
            maxDiscount: def.maxDiscount,
            minSpend: def.minSpend,
            startsAt: def.startsAt,
            expiresAt: def.expiresAt,
            usageLimit: def.usageLimit,
            usedCount: def.usedCount,
            perCustomerLimit: def.perCustomerLimit,
            customerId: def.customerId,
            productIds: def.productIds,
            description: describeCoupon(def),
          };
        }),
    };
  }

  /** Looks a code up and runs the rules against a sale's lines. */
  async assessForSale(params: {
    tenantId: string;
    code: string;
    customerId?: string | null;
    lines: CouponLine[];
    now?: Date;
  }): Promise<SaleCouponAssessment> {
    const code = normaliseCouponCode(params.code);
    const row = await this.prisma.coupon.findUnique({
      where: { tenantId_code: { tenantId: params.tenantId, code } },
    });
    if (!row) {
      return {
        couponId: null,
        code,
        productIds: [],
        verdict: {
          ok: false,
          discount: 0,
          eligibleAmount: 0,
          reason: 'NOT_FOUND',
          message: 'That coupon code does not exist.',
        },
      };
    }
    const customerUses =
      params.customerId && row.perCustomerLimit != null
        ? await this.prisma.couponRedemption.count({
            where: { couponId: row.id, customerId: params.customerId },
          })
        : 0;
    const verdict = evaluateCoupon(this.toDef(row), {
      now: params.now ?? new Date(),
      customerId: params.customerId,
      customerUses,
      lines: params.lines,
    });
    return { couponId: row.id, code, productIds: row.productIds ?? [], verdict };
  }

  /** Online check from the till: "does this code work on this cart, and for how much?" */
  async check(tenantId: string, dto: CheckCouponDto) {
    const lines = dto.lines.map((line) => ({
      productId: line.productId,
      amount: round2(line.unitPrice * line.quantity - (line.discount ?? 0)),
    }));
    const result = await this.assessForSale({
      tenantId,
      code: dto.code,
      customerId: dto.customerId,
      lines,
    });
    return result.verdict.ok
      ? { valid: true, code: result.code, discount: result.verdict.discount }
      : { valid: false, code: result.code, reason: result.verdict.reason, message: result.verdict.message };
  }

  // ------------------------------------------------------------ the sale

  /** Runs inside the sale's transaction so the count and the receipt agree. */
  async redeemInTx(
    tx: Prisma.TransactionClient,
    params: {
      tenantId: string;
      branchId: string;
      saleId: string;
      userId: string;
      customerId?: string | null;
      use: SaleCouponUse;
    },
  ): Promise<{ overLimit: boolean }> {
    const existing = await tx.couponRedemption.findUnique({ where: { saleId: params.saleId } });
    if (existing) return { overLimit: false };

    await tx.couponRedemption.create({
      data: {
        couponId: params.use.couponId,
        tenantId: params.tenantId,
        branchId: params.branchId,
        saleId: params.saleId,
        customerId: params.customerId ?? null,
        userId: params.userId,
        code: params.use.code,
        amount: params.use.amount,
      },
    });
    const updated = await tx.coupon.update({
      where: { id: params.use.couponId },
      data: { usedCount: { increment: 1 } },
      select: { usedCount: true, usageLimit: true },
    });
    return { overLimit: updated.usageLimit != null && updated.usedCount > updated.usageLimit };
  }

  /** Called after a sale commits: tells the owner about coupons that did not check out. */
  async flagAfterSale(params: {
    tenantId: string;
    branchId: string;
    userId: string;
    saleId: string;
    receiptNumber: string;
    code: string;
    problem?: string | null;
    overLimit?: boolean;
    claimedDiscount?: number;
  }): Promise<void> {
    if (!params.problem && !params.overLimit) return;
    const actor = await this.accountability.actorName(params.userId);
    await this.accountability.raise({
      tenantId: params.tenantId,
      branchId: params.branchId,
      type: params.overLimit ? 'COUPON_OVERUSE' : 'COUPON_REJECTED',
      severity: 'MEDIUM',
      title: params.overLimit ? 'Coupon used past its limit' : 'Coupon did not check out',
      body: params.overLimit
        ? `${actor} used ${params.code} after it hit its limit (receipt ${params.receiptNumber}).`
        : `${actor} took a discount with ${params.code}, but: ${params.problem} (receipt ${params.receiptNumber}).`,
      actorUserId: params.userId,
      entityType: 'Sale',
      entityId: params.saleId,
      data: { code: params.code, claimedDiscount: params.claimedDiscount ?? null },
    });
  }

  /** A voided sale gives its coupon use back. Best effort: never blocks the void. */
  async releaseForSale(saleId: string): Promise<void> {
    try {
      const redemption = await this.prisma.couponRedemption.findUnique({ where: { saleId } });
      if (!redemption) return;
      await this.prisma.$transaction([
        this.prisma.couponRedemption.delete({ where: { saleId } }),
        this.prisma.coupon.update({
          where: { id: redemption.couponId },
          data: { usedCount: { decrement: 1 } },
        }),
      ]);
    } catch (error) {
      this.logger.error(`Failed to release coupon for sale ${saleId}: ${error}`);
    }
  }

  // ------------------------------------------------------------- reports

  async report(tenantId: string, days = 30) {
    const since = new Date(Date.now() - days * 86_400_000);
    const rows = await this.prisma.couponRedemption.findMany({
      where: { tenantId, createdAt: { gte: since } },
      select: { code: true, amount: true, userId: true, couponId: true },
    });
    const byCode = new Map<string, { code: string; uses: number; given: number }>();
    const byUser = new Map<string, { userId: string; uses: number; given: number }>();
    let totalGiven = 0;
    for (const row of rows) {
      const amount = Number(row.amount);
      totalGiven += amount;
      const c = byCode.get(row.code) ?? { code: row.code, uses: 0, given: 0 };
      c.uses += 1;
      c.given = round2(c.given + amount);
      byCode.set(row.code, c);
      const u = byUser.get(row.userId) ?? { userId: row.userId, uses: 0, given: 0 };
      u.uses += 1;
      u.given = round2(u.given + amount);
      byUser.set(row.userId, u);
    }
    const users = await this.prisma.user.findMany({
      where: { id: { in: [...byUser.keys()] } },
      select: { id: true, firstName: true, lastName: true },
    });
    const nameOf = new Map(users.map((u) => [u.id, `${u.firstName} ${u.lastName}`.trim()]));
    return {
      days,
      uses: rows.length,
      totalGiven: round2(totalGiven),
      byCode: [...byCode.values()].sort((a, b) => b.given - a.given),
      byCashier: [...byUser.values()]
        .map((u) => ({ ...u, name: nameOf.get(u.userId) ?? 'Unknown' }))
        .sort((a, b) => b.given - a.given),
    };
  }

  /** Used by the owner's daily summary. */
  async usageBetween(tenantId: string, branchId: string, from: Date, to: Date) {
    const rows = await this.prisma.couponRedemption.findMany({
      where: { tenantId, branchId, createdAt: { gte: from, lt: to } },
      select: { amount: true },
    });
    return { uses: rows.length, given: round2(rows.reduce((sum, r) => sum + Number(r.amount), 0)) };
  }
}
