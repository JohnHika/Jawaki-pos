import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { ExchangeRatesService } from '../exchange-rates/exchange-rates.service';
import { InventoryService } from '../inventory/inventory.service';
import { AccountabilityService } from '../accountability/accountability.service';
import {
  AllocationBasis,
  computeLandedCost,
  participantLedgers,
  priceToKeepMargin,
  weightedAverageCost,
} from './imports.math';
import {
  AddCostDto,
  AddParticipantDto,
  CreateShipmentDto,
  RecordImportPaymentDto,
  ReceiveShipmentDto,
  ShipmentItemDto,
  ShipmentQueryDto,
  UpdateShipmentDto,
} from './dto/imports.dto';

const num = (v: Prisma.Decimal | number | null | undefined) => (v === null || v === undefined ? 0 : Number(v));
const kes = (n: number) => `KES ${Math.round(n).toLocaleString('en-KE')}`;

@Injectable()
export class ImportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly rates: ExchangeRatesService,
    private readonly inventory: InventoryService,
    private readonly accountability: AccountabilityService,
  ) {}

  // ------------------------------------------------------------------ shipments

  async create(userId: string, tenantId: string, dto: CreateShipmentDto) {
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
      select: { id: true },
    });
    if (!branch) throw new NotFoundException('Branch not found');

    const currency = (dto.currency ?? 'USD').toUpperCase();
    const fxRate = dto.fxRate ?? (await this.requireRate(currency));
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { name: true },
    });

    const shipment = await this.prisma.importShipment.create({
      data: {
        tenantId,
        branchId: dto.branchId,
        title: dto.title.trim(),
        reference: dto.reference?.trim() || null,
        origin: dto.origin?.trim() || null,
        currency,
        fxRate,
        allocationBasis: dto.allocationBasis ?? 'VALUE',
        expectedArrival: dto.expectedArrival ? new Date(dto.expectedArrival) : null,
        notes: dto.notes ?? null,
        createdById: userId,
        // Your own share of the container always exists, so a single-owner
        // import needs no extra setup.
        participants: { create: [{ name: tenant?.name ?? 'My shop', isSelf: true }] },
      },
    });

    await this.accountability.record({
      userId,
      action: 'IMPORT_CREATED',
      entityType: 'ImportShipment',
      entityId: shipment.id,
      newValues: { title: shipment.title, currency, fxRate },
    });
    return this.get(tenantId, shipment.id);
  }

  async list(tenantId: string, query: ShipmentQueryDto) {
    const shipments = await this.prisma.importShipment.findMany({
      where: {
        tenantId,
        ...(query.branchId ? { branchId: query.branchId } : {}),
        ...(query.status ? { status: query.status } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: { items: true, costs: true, participants: true, payments: true },
    });

    return shipments.map((s) => {
      const calc = this.calculate(s);
      const ledgers = participantLedgers(
        calc.items,
        s.participants.map((p) => p.id),
        s.payments.map((p) => ({ participantId: p.participantId, amountKes: num(p.amountKes) })),
      );
      return {
        id: s.id,
        title: s.title,
        reference: s.reference,
        origin: s.origin,
        status: s.status,
        currency: s.currency,
        expectedArrival: s.expectedArrival,
        receivedAt: s.receivedAt,
        participantCount: s.participants.length,
        goodsKes: calc.goodsKes,
        costsKes: calc.costsKes,
        landedKes: calc.landedKes,
        outstandingKes: Math.max(
          ledgers.reduce((a, l) => a + Math.max(l.balanceKes, 0), 0),
          0,
        ),
        createdAt: s.createdAt,
      };
    });
  }

  async get(tenantId: string, id: string) {
    const s = await this.load(tenantId, id);
    const calc = this.calculate(s);
    const byItem = new Map(calc.items.map((i) => [i.id, i]));
    const ledgers = participantLedgers(
      calc.items,
      s.participants.map((p) => p.id),
      s.payments.map((p) => ({ participantId: p.participantId, amountKes: num(p.amountKes) })),
    );
    const ledgerByParticipant = new Map(ledgers.map((l) => [l.participantId, l]));

    return {
      id: s.id,
      branchId: s.branchId,
      title: s.title,
      reference: s.reference,
      origin: s.origin,
      status: s.status,
      currency: s.currency,
      fxRate: num(s.fxRate),
      allocationBasis: s.allocationBasis,
      basisUsed: calc.basisUsed,
      expectedArrival: s.expectedArrival,
      arrivedAt: s.arrivedAt,
      receivedAt: s.receivedAt,
      notes: s.notes,
      createdAt: s.createdAt,
      totals: {
        goodsKes: calc.goodsKes,
        costsKes: calc.costsKes,
        landedKes: calc.landedKes,
        upliftPercent: calc.uplift,
      },
      warnings: calc.warnings,
      costs: s.costs
        .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime())
        .map((c) => ({
          id: c.id,
          type: c.type,
          label: c.label,
          amount: num(c.amount),
          currency: c.currency,
          fxRate: num(c.fxRate),
          amountKes: num(c.amountKes),
          paidAt: c.paidAt,
          reference: c.reference,
          receiptUrl: c.receiptUrl,
        })),
      participants: s.participants.map((p) => {
        const l = ledgerByParticipant.get(p.id);
        return {
          id: p.id,
          name: p.name,
          phone: p.phone,
          isSelf: p.isSelf,
          notes: p.notes,
          goodsKes: l?.goodsKes ?? 0,
          costShareKes: l?.costShareKes ?? 0,
          owesKes: l?.owesKes ?? 0,
          paidKes: l?.paidKes ?? 0,
          balanceKes: l?.balanceKes ?? 0,
          status: l?.status ?? 'SETTLED',
        };
      }),
      items: s.items.map((i) => {
        const r = byItem.get(i.id);
        return {
          id: i.id,
          participantId: i.participantId,
          productId: i.productId,
          description: i.description,
          quantity: num(i.quantity),
          unit: i.unit,
          unitCost: num(i.unitCost),
          cbm: i.cbm === null ? null : num(i.cbm),
          weightKg: i.weightKg === null ? null : num(i.weightKg),
          receivedQty: i.receivedQty === null ? null : num(i.receivedQty),
          goodsValueKes: r?.goodsValueKes ?? 0,
          allocatedCostKes: r?.allocatedCostKes ?? 0,
          landedUnitCostKes: r?.landedUnitCostKes ?? 0,
          landedTotalKes: r?.landedTotalKes ?? 0,
        };
      }),
      payments: s.payments
        .sort((a, b) => b.paidAt.getTime() - a.paidAt.getTime())
        .map((p) => ({
          id: p.id,
          participantId: p.participantId,
          amountKes: num(p.amountKes),
          method: p.method,
          reference: p.reference,
          notes: p.notes,
          paidAt: p.paidAt,
        })),
    };
  }

  async update(userId: string, tenantId: string, id: string, dto: UpdateShipmentDto) {
    const s = await this.requireEditable(tenantId, id, { allowStatusOnly: true });

    const data: Prisma.ImportShipmentUpdateInput = {};
    if (dto.title !== undefined) data.title = dto.title.trim();
    if (dto.reference !== undefined) data.reference = dto.reference.trim() || null;
    if (dto.origin !== undefined) data.origin = dto.origin.trim() || null;
    if (dto.notes !== undefined) data.notes = dto.notes;
    if (dto.expectedArrival !== undefined) data.expectedArrival = new Date(dto.expectedArrival);
    if (dto.allocationBasis !== undefined) data.allocationBasis = dto.allocationBasis;
    if (dto.currency !== undefined) {
      const currency = dto.currency.toUpperCase();
      data.currency = currency;
      if (dto.fxRate === undefined && currency !== s.currency) {
        data.fxRate = await this.requireRate(currency);
      }
    }
    if (dto.fxRate !== undefined) data.fxRate = dto.fxRate;

    if (dto.status !== undefined) {
      this.assertTransition(s.status, dto.status);
      data.status = dto.status;
      if (dto.status === 'ARRIVED') data.arrivedAt = new Date();
    }

    const money =
      dto.currency !== undefined || dto.fxRate !== undefined || dto.allocationBasis !== undefined;
    if (money && s.status === 'RECEIVED') {
      throw new ConflictException('This shipment is already received; its costs can no longer change.');
    }

    await this.prisma.importShipment.update({ where: { id }, data });
    if (money) await this.recompute(id);

    await this.accountability.record({
      userId,
      action: 'IMPORT_UPDATED',
      entityType: 'ImportShipment',
      entityId: id,
      oldValues: { status: s.status, currency: s.currency, fxRate: num(s.fxRate), basis: s.allocationBasis },
      newValues: dto as unknown as Record<string, unknown>,
    });
    return this.get(tenantId, id);
  }

  // --------------------------------------------------------------- participants

  async addParticipant(userId: string, tenantId: string, id: string, dto: AddParticipantDto) {
    await this.requireEditable(tenantId, id, { allowReceived: true });
    await this.prisma.importParticipant.create({
      data: {
        shipmentId: id,
        name: dto.name.trim(),
        phone: dto.phone?.trim() || null,
        notes: dto.notes ?? null,
      },
    });
    return this.get(tenantId, id);
  }

  async removeParticipant(userId: string, tenantId: string, id: string, participantId: string) {
    await this.requireEditable(tenantId, id);
    const p = await this.prisma.importParticipant.findFirst({
      where: { id: participantId, shipmentId: id },
      include: { _count: { select: { items: true, payments: true } } },
    });
    if (!p) throw new NotFoundException('Participant not found');
    if (p.isSelf) throw new BadRequestException('You cannot remove your own share');
    if (p._count.items > 0 || p._count.payments > 0) {
      throw new ConflictException('Remove their goods and payments first');
    }
    await this.prisma.importParticipant.delete({ where: { id: participantId } });
    return this.get(tenantId, id);
  }

  // ---------------------------------------------------------------------- items

  async addItem(userId: string, tenantId: string, id: string, dto: ShipmentItemDto) {
    await this.requireEditable(tenantId, id);
    const participantId = await this.resolveParticipant(id, dto.participantId);
    await this.checkProduct(tenantId, dto.productId);

    await this.prisma.importItem.create({
      data: {
        shipmentId: id,
        participantId,
        productId: dto.productId ?? null,
        description: dto.description.trim(),
        quantity: dto.quantity,
        unit: dto.unit?.trim() || 'piece',
        unitCost: dto.unitCost,
        cbm: dto.cbm ?? null,
        weightKg: dto.weightKg ?? null,
      },
    });
    await this.recompute(id);
    return this.get(tenantId, id);
  }

  async updateItem(
    userId: string,
    tenantId: string,
    id: string,
    itemId: string,
    dto: Partial<ShipmentItemDto>,
  ) {
    await this.requireEditable(tenantId, id);
    const item = await this.prisma.importItem.findFirst({ where: { id: itemId, shipmentId: id } });
    if (!item) throw new NotFoundException('Item not found');
    if (dto.productId) await this.checkProduct(tenantId, dto.productId);
    const participantId = dto.participantId
      ? await this.resolveParticipant(id, dto.participantId)
      : undefined;

    await this.prisma.importItem.update({
      where: { id: itemId },
      data: {
        ...(participantId !== undefined && { participantId }),
        ...(dto.productId !== undefined && { productId: dto.productId }),
        ...(dto.description !== undefined && { description: dto.description.trim() }),
        ...(dto.quantity !== undefined && { quantity: dto.quantity }),
        ...(dto.unit !== undefined && { unit: dto.unit.trim() || 'piece' }),
        ...(dto.unitCost !== undefined && { unitCost: dto.unitCost }),
        ...(dto.cbm !== undefined && { cbm: dto.cbm }),
        ...(dto.weightKg !== undefined && { weightKg: dto.weightKg }),
      },
    });
    await this.recompute(id);
    return this.get(tenantId, id);
  }

  async removeItem(userId: string, tenantId: string, id: string, itemId: string) {
    await this.requireEditable(tenantId, id);
    const item = await this.prisma.importItem.findFirst({ where: { id: itemId, shipmentId: id } });
    if (!item) throw new NotFoundException('Item not found');
    await this.prisma.importItem.delete({ where: { id: itemId } });
    await this.recompute(id);
    return this.get(tenantId, id);
  }

  // ---------------------------------------------------------------------- costs

  async addCost(userId: string, tenantId: string, id: string, dto: AddCostDto) {
    await this.requireEditable(tenantId, id);
    const currency = (dto.currency ?? 'KES').toUpperCase();
    const fxRate = currency === 'KES' ? 1 : dto.fxRate ?? (await this.requireRate(currency));
    const amountKes = Math.round(dto.amount * fxRate * 100) / 100;

    await this.prisma.importCost.create({
      data: {
        shipmentId: id,
        type: dto.type,
        label: dto.label?.trim() || null,
        amount: dto.amount,
        currency,
        fxRate,
        amountKes,
        paidAt: dto.paidAt ? new Date(dto.paidAt) : null,
        reference: dto.reference?.trim() || null,
        receiptUrl: dto.receiptUrl ?? null,
        createdById: userId,
      },
    });
    await this.recompute(id);
    await this.accountability.record({
      userId,
      action: 'IMPORT_COST_ADDED',
      entityType: 'ImportShipment',
      entityId: id,
      newValues: { type: dto.type, amountKes, reference: dto.reference },
    });
    return this.get(tenantId, id);
  }

  async removeCost(userId: string, tenantId: string, id: string, costId: string) {
    await this.requireEditable(tenantId, id);
    const cost = await this.prisma.importCost.findFirst({ where: { id: costId, shipmentId: id } });
    if (!cost) throw new NotFoundException('Cost not found');
    await this.prisma.importCost.delete({ where: { id: costId } });
    await this.recompute(id);
    await this.accountability.record({
      userId,
      action: 'IMPORT_COST_REMOVED',
      entityType: 'ImportShipment',
      entityId: id,
      oldValues: { type: cost.type, amountKes: num(cost.amountKes) },
    });
    return this.get(tenantId, id);
  }

  // ------------------------------------------------------------------- payments

  async recordPayment(userId: string, tenantId: string, id: string, dto: RecordImportPaymentDto) {
    const s = await this.load(tenantId, id);
    const participant = s.participants.find((p) => p.id === dto.participantId);
    if (!participant) throw new NotFoundException('Participant not found');

    await this.prisma.importPayment.create({
      data: {
        shipmentId: id,
        participantId: dto.participantId,
        amountKes: dto.amountKes,
        method: dto.method ?? null,
        reference: dto.reference?.trim() || null,
        notes: dto.notes ?? null,
        paidAt: dto.paidAt ? new Date(dto.paidAt) : new Date(),
        recordedById: userId,
      },
    });
    await this.accountability.record({
      userId,
      action: 'IMPORT_PAYMENT_RECORDED',
      entityType: 'ImportShipment',
      entityId: id,
      newValues: { participant: participant.name, amountKes: dto.amountKes, reference: dto.reference },
    });
    return this.get(tenantId, id);
  }

  async removePayment(userId: string, tenantId: string, id: string, paymentId: string) {
    await this.load(tenantId, id);
    const payment = await this.prisma.importPayment.findFirst({
      where: { id: paymentId, shipmentId: id },
    });
    if (!payment) throw new NotFoundException('Payment not found');
    await this.prisma.importPayment.delete({ where: { id: paymentId } });
    // Deleting a payment makes someone owe money again, so it leaves a trail.
    await this.accountability.record({
      userId,
      action: 'IMPORT_PAYMENT_REMOVED',
      entityType: 'ImportShipment',
      entityId: id,
      oldValues: { amountKes: num(payment.amountKes), reference: payment.reference },
    });
    return this.get(tenantId, id);
  }

  // -------------------------------------------------------------------- receive

  /**
   * Books the arrived goods into stock at their true landed cost. Only your
   * own lines go into your stock; other traders' lines stay on the ledger.
   * If fewer units arrived than were ordered, the cost of the whole line is
   * carried by the units that did arrive - a short delivery makes each
   * remaining unit dearer, and the books should say so.
   */
  async receive(userId: string, tenantId: string, id: string, dto: ReceiveShipmentDto) {
    const s = await this.load(tenantId, id);
    if (s.status === 'RECEIVED') throw new ConflictException('This shipment was already received');
    if (s.status === 'CANCELLED') throw new ConflictException('This shipment was cancelled');
    if (s.status === 'PLANNED') {
      throw new ConflictException('Mark the shipment as in transit or arrived before receiving it');
    }

    const self = s.participants.find((p) => p.isSelf);
    if (!self) throw new BadRequestException('This shipment has no share of yours to receive');

    const calc = this.calculate(s);
    const byItem = new Map(calc.items.map((i) => [i.id, i]));
    const received = new Map((dto.items ?? []).map((l) => [l.itemId, l.receivedQty]));
    for (const itemId of received.keys()) {
      if (!s.items.some((i) => i.id === itemId)) {
        throw new BadRequestException('One of the received lines is not part of this shipment');
      }
    }

    const mine = s.items.filter((i) => i.participantId === self.id);
    const booked: Array<Record<string, unknown>> = [];
    const skipped: Array<{ itemId: string; description: string; reason: string }> = [];
    const costAlerts: Array<{ name: string; oldCost: number | null; newCost: number; basePrice: number; suggested: number | null }> = [];

    for (const item of mine) {
      const ordered = num(item.quantity);
      const arrived = received.has(item.id) ? received.get(item.id)! : ordered;
      if (arrived <= 0) {
        skipped.push({ itemId: item.id, description: item.description, reason: 'Nothing arrived' });
        continue;
      }
      if (!item.productId) {
        skipped.push({
          itemId: item.id,
          description: item.description,
          reason: 'Not linked to a product, so it was not added to stock',
        });
        continue;
      }

      const result = byItem.get(item.id)!;
      const unitCost = Math.round((result.landedTotalKes / arrived) * 100) / 100;

      const product = await this.prisma.product.findFirst({
        where: { id: item.productId, tenantId },
        select: { id: true, name: true, costPrice: true, basePrice: true, unit: true },
      });
      if (!product) {
        skipped.push({ itemId: item.id, description: item.description, reason: 'Product no longer exists' });
        continue;
      }
      const onHand = await this.prisma.stock.findUnique({
        where: { branchId_productId: { branchId: s.branchId, productId: product.id } },
        select: { quantity: true },
      });
      const oldCost = product.costPrice === null ? null : num(product.costPrice);
      const newAvg = weightedAverageCost(num(onHand?.quantity), oldCost, arrived, unitCost);

      await this.inventory.receiveBatch(userId, tenantId, {
        branchId: s.branchId,
        productId: product.id,
        reference: `import:${s.id}`,
        batches: [
          {
            quantity: arrived,
            unitsPerQuantity: 1,
            costPrice: unitCost,
            supplierRef: s.reference ?? undefined,
            notes: `Import "${s.title}" - landed cost ${kes(unitCost)} each`,
          },
        ],
      } as any);

      await this.prisma.product.update({ where: { id: product.id }, data: { costPrice: newAvg } });
      await this.prisma.importItem.update({ where: { id: item.id }, data: { receivedQty: arrived } });

      booked.push({
        itemId: item.id,
        productId: product.id,
        name: product.name,
        quantity: arrived,
        landedUnitCostKes: unitCost,
        newAverageCostKes: newAvg,
      });

      if (oldCost !== null && newAvg > oldCost * 1.05) {
        costAlerts.push({
          name: product.name,
          oldCost,
          newCost: newAvg,
          basePrice: num(product.basePrice),
          suggested: priceToKeepMargin(oldCost, num(product.basePrice), newAvg),
        });
      } else if (newAvg >= num(product.basePrice)) {
        costAlerts.push({
          name: product.name,
          oldCost,
          newCost: newAvg,
          basePrice: num(product.basePrice),
          suggested: null,
        });
      }
    }

    // Other people's lines are marked as handed over as ordered.
    await this.prisma.importShipment.update({
      where: { id },
      data: { status: 'RECEIVED', receivedAt: new Date(), receivedById: userId },
    });
    await this.redis.invalidatePattern(`products:${tenantId}:*`);

    await this.accountability.record({
      userId,
      action: 'IMPORT_RECEIVED',
      entityType: 'ImportShipment',
      entityId: id,
      newValues: { booked: booked.length, skipped: skipped.length, landedKes: calc.landedKes },
    });

    // The point of landed cost: tell the owner when prices on the shelf no
    // longer cover what the stock really cost to land.
    for (const a of costAlerts) {
      const underwater = a.newCost >= a.basePrice;
      await this.accountability.raise({
        tenantId,
        branchId: s.branchId,
        type: 'PRICE_REVIEW',
        severity: underwater ? 'HIGH' : 'MEDIUM',
        title: underwater ? 'Selling below landed cost' : 'Cost went up - check your price',
        body: underwater
          ? `${a.name} now costs ${kes(a.newCost)} to land but sells for ${kes(a.basePrice)}.`
          : `${a.name} cost rose from ${kes(a.oldCost ?? 0)} to ${kes(a.newCost)}.${a.suggested ? ` To keep your usual margin, price it at about ${kes(a.suggested)}.` : ''}`,
        actorUserId: userId,
        entityType: 'ImportShipment',
        entityId: id,
        data: { ...a },
      });
    }

    return { shipment: await this.get(tenantId, id), booked, skipped };
  }

  // -------------------------------------------------------------------- helpers

  private calculate(s: LoadedShipment) {
    return computeLandedCost({
      fxRate: num(s.fxRate),
      basis: s.allocationBasis as AllocationBasis,
      items: s.items.map((i) => ({
        id: i.id,
        participantId: i.participantId,
        quantity: num(i.quantity),
        unitCost: num(i.unitCost),
        cbm: i.cbm === null ? null : num(i.cbm),
        weightKg: i.weightKg === null ? null : num(i.weightKg),
      })),
      costs: s.costs.map((c) => ({ amountKes: num(c.amountKes) })),
    });
  }

  /** Stores the computed per-line figures so reports don't have to redo the maths. */
  private async recompute(id: string) {
    const s = await this.prisma.importShipment.findUnique({
      where: { id },
      include: { items: true, costs: true, participants: true, payments: true },
    });
    if (!s) return;
    const calc = this.calculate(s);
    await this.prisma.$transaction(
      calc.items.map((r) =>
        this.prisma.importItem.update({
          where: { id: r.id },
          data: {
            goodsValueKes: r.goodsValueKes,
            allocatedCostKes: r.allocatedCostKes,
            landedUnitCostKes: r.landedUnitCostKes,
          },
        }),
      ),
    );
  }

  private async load(tenantId: string, id: string) {
    const s = await this.prisma.importShipment.findFirst({
      where: { id, tenantId },
      include: { items: true, costs: true, participants: true, payments: true },
    });
    if (!s) throw new NotFoundException('Shipment not found');
    return s;
  }

  private async requireEditable(
    tenantId: string,
    id: string,
    opts: { allowStatusOnly?: boolean; allowReceived?: boolean } = {},
  ) {
    const s = await this.load(tenantId, id);
    if (s.status === 'CANCELLED') throw new ConflictException('This shipment was cancelled');
    if (s.status === 'RECEIVED' && !opts.allowStatusOnly && !opts.allowReceived) {
      throw new ConflictException('This shipment is already received; its goods and costs can no longer change.');
    }
    return s;
  }

  private assertTransition(from: string, to: string) {
    const order = ['PLANNED', 'IN_TRANSIT', 'ARRIVED'];
    if (to === 'CANCELLED') {
      if (from === 'RECEIVED') throw new ConflictException('A received shipment cannot be cancelled');
      return;
    }
    if (from === to) return;
    if (from === 'RECEIVED' || from === 'CANCELLED') {
      throw new ConflictException(`A ${from.toLowerCase()} shipment cannot change status`);
    }
    if (order.indexOf(to) < order.indexOf(from)) {
      throw new ConflictException(`Cannot move a shipment back from ${from} to ${to}`);
    }
  }

  private async resolveParticipant(shipmentId: string, participantId?: string) {
    if (participantId) {
      const p = await this.prisma.importParticipant.findFirst({
        where: { id: participantId, shipmentId },
        select: { id: true },
      });
      if (!p) throw new BadRequestException('That participant is not part of this shipment');
      return p.id;
    }
    const self = await this.prisma.importParticipant.findFirst({
      where: { shipmentId, isSelf: true },
      select: { id: true },
    });
    return self?.id ?? null;
  }

  private async checkProduct(tenantId: string, productId?: string) {
    if (!productId) return;
    const product = await this.prisma.product.findFirst({
      where: { id: productId, tenantId },
      select: { id: true },
    });
    if (!product) throw new BadRequestException('That product does not exist');
  }

  private async requireRate(currency: string): Promise<number> {
    const rate = await this.rates.rateFor(currency);
    if (!rate) {
      throw new BadRequestException(
        `No live rate for ${currency}. Enter today's KES rate yourself.`,
      );
    }
    return rate;
  }
}

type LoadedShipment = Prisma.ImportShipmentGetPayload<{
  include: { items: true; costs: true; participants: true; payments: true };
}>;
