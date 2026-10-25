import { getDayBoundsInTimezone } from '../common/operating-hours';
import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
  ConflictException,
  Optional,
} from '@nestjs/common';
import { AccountabilityService } from '../accountability/accountability.service';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { CashFlowService } from '../cash-flow/cash-flow.service';
import { AiService } from '../ai/ai.service';
import { NotificationsService } from '../notifications/notifications.service';
import {
  StockAdjustmentDto,
  CreateTransferDto,
  ReceiveTransferDto,
  StockQueryDto,
  ReceiveBatchDto,
  UpdateBatchDto,
  ExpiryDashboardQueryDto,
  BatchResponseDto,
  StockWithBatchesResponseDto,
  ExpiryDashboardResponseDto,
} from './dto/inventory.dto';
import { Prisma, StockMovementType } from '@prisma/client';
import { lockStockForUpdate } from '../common/stock-lock';
import { applyPurchaseCost } from '../common/product-cost';

@Injectable()
export class InventoryService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
    private cashFlowService: CashFlowService,
    private aiService: AiService,
    private notificationsService: NotificationsService,
    // Optional so specs that build the service by hand keep working.
    @Optional() private accountability?: AccountabilityService,
  ) {}

  async getStock(branchId: string, tenantId: string, query: StockQueryDto) {
    // Verify branch
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    const { search, categoryId, lowStock, page = 1, limit = 50 } = query;
    const skip = (page - 1) * limit;

    // Build product filter
    const productWhere: any = { tenantId, trackInventory: true };

    if (search) {
      productWhere.OR = [
        { name: { contains: search, mode: 'insensitive' } },
        { sku: { contains: search, mode: 'insensitive' } },
      ];
    }

    if (categoryId) {
      productWhere.categories = { some: { categoryId } };
    }

    // Get products with stock
    const products = await this.prisma.product.findMany({
      where: productWhere,
      include: {
        stock: { where: { branchId } },
      },
      orderBy: { name: 'asc' },
    });

    // Map to stock items
    let stockItems = products.map((p) => {
      const stock = p.stock[0];
      const quantity = stock ? Number(stock.quantity) : 0;
      const reservedQty = stock ? Number(stock.reservedQty) : 0;
      const availableQty = quantity - reservedQty;

      return {
        productId: p.id,
        sku: p.sku,
        productName: p.name,
        quantity,
        reservedQty,
        availableQty,
        minStock: p.minStock,
        isLowStock: quantity <= p.minStock,
        unit: p.unit,
        costPrice: p.costPrice ? Number(p.costPrice) : undefined,
        stockValue: p.costPrice ? quantity * Number(p.costPrice) : undefined,
      };
    });

    if (lowStock) {
      stockItems = stockItems.filter((s) => s.isLowStock);
    }

    const total = stockItems.length;
    const paginatedItems = stockItems.slice(skip, skip + limit);

    return {
      items: paginatedItems,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
      summary: {
        totalProducts: total,
        lowStockCount: stockItems.filter((s) => s.isLowStock).length,
        totalValue: stockItems.reduce((sum, s) => sum + (s.stockValue || 0), 0),
      },
    };
  }

  async getProductStock(productId: string, tenantId: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, tenantId },
      include: {
        stock: {
          include: {
            branch: { select: { id: true, name: true, code: true } },
          },
        },
      },
    });

    if (!product) {
      throw new NotFoundException('Product not found');
    }

    return {
      productId: product.id,
      sku: product.sku,
      productName: product.name,
      branches: product.stock.map((s) => ({
        branchId: s.branchId,
        branchName: s.branch.name,
        branchCode: s.branch.code,
        quantity: Number(s.quantity),
        reservedQty: Number(s.reservedQty),
        availableQty: Number(s.quantity) - Number(s.reservedQty),
      })),
    };
  }

  async adjustStock(userId: string, tenantId: string, dto: StockAdjustmentDto) {
    // Verify branch
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    // Verify products
    const productIds = dto.items.map((i) => i.productId);
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds }, tenantId },
    });

    if (products.length !== productIds.length) {
      throw new NotFoundException('One or more products not found');
    }

    const recorded: any[] = [];
    return this.prisma.$transaction(async (tx) => {
      const movements: any[] = [];

      for (const item of [...dto.items].sort((a, b) =>
        a.productId.localeCompare(b.productId),
      )) {
        const stock = await lockStockForUpdate(
          tx,
          dto.branchId,
          item.productId,
          true,
        );
        if (!stock) {
          throw new ConflictException('Could not lock stock for adjustment');
        }

        const previousQty = Number(stock.quantity);
        const newQty = item.quantity;
        const quantityChange = newQty - previousQty;

        await tx.stock.update({
          where: { id: stock.id },
          data: { quantity: newQty },
        });

        // Record movement
        const movement = await tx.stockMovement.create({
          data: {
            branchId: dto.branchId,
            productId: item.productId,
            type: dto.type,
            quantity: quantityChange,
            previousQty,
            newQty,
            reference: dto.reference,
            notes: item.notes || dto.notes,
            createdById: userId,
          },
        });

        movements.push(movement);
        recorded.push(movement);
      }

      return { success: true, movementCount: movements.length };
    }).then(async (result) => {
      // See receiveBatch for why this is needed: CatalogService caches
      // GET /products (with embedded stock) for 20s per tenant+branch.
      await this.redisService.invalidatePattern(`products:${tenantId}:*`);
      await this.recordAdjustment(userId, tenantId, dto, recorded, products);
      return result;
    });
  }

  /**
   * Audit entry + owner alert for a manual stock adjustment. Writing stock
   * off is the easiest way to hide theft, so every loss is recorded with who
   * did it and what it cost, and large ones are HIGH.
   */
  private async recordAdjustment(
    userId: string,
    tenantId: string,
    dto: StockAdjustmentDto,
    movements: Array<{ productId: string; quantity: unknown; previousQty: unknown; newQty: unknown }>,
    products: Array<{ id: string; name: string; costPrice: unknown; basePrice: unknown }>,
  ) {
    if (!this.accountability) return;
    try {
      const byId = new Map(products.map((p) => [p.id, p]));
      let lossValue = 0;
      let lossUnits = 0;
      let gainUnits = 0;
      const lines = movements.map((m) => {
        const product = byId.get(m.productId);
        const change = Number(m.quantity);
        const cost = Number(product?.costPrice ?? product?.basePrice ?? 0);
        if (change < 0) {
          lossValue += -change * cost;
          lossUnits += -change;
        } else {
          gainUnits += change;
        }
        return {
          productId: m.productId,
          name: product?.name,
          previousQty: Number(m.previousQty),
          newQty: Number(m.newQty),
          change,
        };
      });

      await this.accountability.record({
        userId,
        action: 'STOCK_ADJUSTED',
        entityType: 'Stock',
        entityId: dto.branchId,
        newValues: { type: dto.type, reference: dto.reference, notes: dto.notes, lines },
      });

      if (lossUnits === 0 && gainUnits === 0) return;
      const settings = await this.accountability.getSettings(tenantId);
      const actor = await this.accountability.actorName(userId);
      const changed = lines.filter((l) => l.change !== 0);
      const first = changed[0];
      const more = changed.length - 1;
      const what = first
        ? `${first.name} ${first.change < 0 ? '' : '+'}${first.change}${more > 0 ? ` and ${more} more` : ''}`
        : 'stock';

      if (lossUnits > 0) {
        const threshold = settings.alerts.stockWriteOffValue;
        await this.accountability.raise({
          tenantId,
          branchId: dto.branchId,
          type: 'STOCK_WRITE_OFF',
          severity: threshold > 0 && lossValue >= threshold ? 'HIGH' : 'MEDIUM',
          title: 'Stock written off',
          body: `${actor} reduced stock (${what}). About KES ${Math.round(lossValue).toLocaleString('en-KE')} at cost.${dto.notes ? ' Note: ' + dto.notes : ''}`,
          actorUserId: userId,
          entityType: 'Stock',
          entityId: dto.branchId,
          data: { adjustmentType: dto.type, lossValue, lossUnits, lines },
        });
      } else {
        await this.accountability.raise({
          tenantId,
          branchId: dto.branchId,
          type: 'STOCK_ADJUSTMENT',
          severity: 'LOW',
          title: 'Stock increased by hand',
          body: `${actor} increased stock (${what}).`,
          actorUserId: userId,
          entityType: 'Stock',
          entityId: dto.branchId,
          data: { adjustmentType: dto.type, gainUnits, lines },
        });
      }
    } catch (error) {
      // Recording must never undo an adjustment that has already committed.
    }
  }

  async getStockMovements(
    branchId: string,
    tenantId: string,
    productId?: string,
    startDate?: string,
    endDate?: string,
    page = 1,
    limit = 50,
  ) {
    // Verify branch
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    const where: any = { branchId };
    if (productId) where.productId = productId;

    if (startDate || endDate) {
      // Plain calendar dates ("2026-10-13") cover the whole day in the branch's
      // timezone; `new Date("2026-10-13")` is midnight UTC and used to cut off
      // the entire last day of the range.
      const dateOnly = /^\d{4}-\d{2}-\d{2}$/;
      const timezone = branch.timezone || 'Africa/Nairobi';
      where.createdAt = {};
      if (startDate) {
        where.createdAt.gte = dateOnly.test(startDate)
          ? getDayBoundsInTimezone(startDate, timezone).start
          : new Date(startDate);
      }
      if (endDate) {
        where.createdAt.lte = dateOnly.test(endDate)
          ? getDayBoundsInTimezone(endDate, timezone).end
          : new Date(endDate);
      }
    }

    const [movements, total] = await Promise.all([
      this.prisma.stockMovement.findMany({
        where,
        include: {
          product: { select: { name: true, sku: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.stockMovement.count({ where }),
    ]);

    return {
      items: movements.map((m) => ({
        id: m.id,
        productId: m.productId,
        productName: m.product.name,
        sku: m.product.sku,
        type: m.type,
        quantity: Number(m.quantity),
        previousQty: Number(m.previousQty),
        newQty: Number(m.newQty),
        reference: m.reference,
        notes: m.notes,
        createdAt: m.createdAt,
        createdById: m.createdById,
      })),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  // ==================== STOCK TRANSFERS ====================

  async createTransfer(
    userId: string,
    tenantId: string,
    dto: CreateTransferDto,
    activeBranchId?: string,
  ) {
    if (activeBranchId && dto.fromBranchId !== activeBranchId) {
      throw new ForbiddenException('Transfers must leave from your active branch');
    }
    // Verify branches
    const [fromBranch, toBranch] = await Promise.all([
      this.prisma.branch.findFirst({ where: { id: dto.fromBranchId, tenantId } }),
      this.prisma.branch.findFirst({ where: { id: dto.toBranchId, tenantId } }),
    ]);

    if (!fromBranch) throw new NotFoundException('Source branch not found');
    if (!toBranch) throw new NotFoundException('Destination branch not found');
    if (dto.fromBranchId === dto.toBranchId) {
      throw new BadRequestException('Cannot transfer to the same branch');
    }
    if (new Set(dto.items.map((item) => item.productId)).size !== dto.items.length) {
      throw new BadRequestException('Each product can appear only once in a transfer');
    }

    if (dto.requestId) {
      const prior = await this.prisma.stockTransfer.findUnique({
        where: { requestId: dto.requestId },
        include: { items: true },
      });
      if (prior) {
        if (!this.matchesTransferRequest(prior, dto)) {
          throw new ConflictException('This transfer request key was already used for a different transfer');
        }
        return this.getTransfer(prior.id, tenantId, activeBranchId);
      }
    }

    // Verify products and stock
    const productIds = dto.items.map((i) => i.productId);
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds }, tenantId },
      include: {
        stock: { where: { branchId: dto.fromBranchId } },
      },
    });

    if (products.length !== productIds.length) {
      throw new NotFoundException('One or more products not found');
    }

    // Validate stock availability
    for (const item of dto.items) {
      const product = products.find((p) => p.id === item.productId);
      const stock = product?.stock[0];
      const available = stock ? Number(stock.quantity) : 0;

      if (available < item.quantity) {
        throw new BadRequestException(
          `Insufficient stock for ${product?.name}. Available: ${available}`,
        );
      }
    }

    // Create transfer
    let transfer: { id: string };
    try {
      transfer = await this.prisma.stockTransfer.create({
        data: {
          requestId: dto.requestId,
          fromBranchId: dto.fromBranchId,
          toBranchId: dto.toBranchId,
          status: 'pending',
          notes: dto.notes,
          createdById: userId,
          items: {
            create: dto.items.map((item) => ({
              productId: item.productId,
              requestedQty: item.quantity,
            })),
          },
        },
        select: { id: true },
      });
    } catch (error) {
      if (
        dto.requestId &&
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        const prior = await this.prisma.stockTransfer.findUnique({
          where: { requestId: dto.requestId },
          include: { items: true },
        });
        if (prior && this.matchesTransferRequest(prior, dto)) {
          return this.getTransfer(prior.id, tenantId, activeBranchId);
        }
        if (prior) {
          throw new ConflictException(
            'This transfer request key was already used for a different transfer',
          );
        }
      }
      throw error;
    }

    return this.getTransfer(transfer.id, tenantId, activeBranchId);
  }

  async sendTransfer(
    transferId: string,
    userId: string,
    tenantId: string,
    activeBranchId?: string,
  ) {
    const transfer = await this.getTransferInternal(transferId, tenantId);

    if (activeBranchId && transfer.fromBranchId !== activeBranchId) {
      throw new ForbiddenException('Only the source branch can dispatch this transfer');
    }

    if (transfer.status !== 'pending') {
      throw new BadRequestException('Transfer is not in pending status');
    }

    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`
        SELECT id FROM stock_transfers WHERE id = ${transferId} FOR UPDATE
      `;
      const lockedTransfer = await tx.stockTransfer.findUnique({
        where: { id: transferId },
        include: { items: true },
      });
      if (!lockedTransfer || lockedTransfer.status !== 'pending') {
        throw new BadRequestException('Transfer is not in pending status');
      }

      // Deduct stock from source branch
      for (const item of [...lockedTransfer.items].sort((a, b) =>
        a.productId.localeCompare(b.productId),
      )) {
        const stock = await lockStockForUpdate(
          tx,
          lockedTransfer.fromBranchId,
          item.productId,
        );

        if (!stock || Number(stock.quantity) < Number(item.requestedQty)) {
          throw new BadRequestException('Insufficient stock');
        }

        const previousQty = Number(stock.quantity);
        const newQty = previousQty - Number(item.requestedQty);

        await tx.stock.update({
          where: { id: stock.id },
          data: { quantity: newQty },
        });

        await tx.stockMovement.create({
          data: {
            branchId: lockedTransfer.fromBranchId,
            productId: item.productId,
            type: StockMovementType.TRANSFER_OUT,
            quantity: -Number(item.requestedQty),
            previousQty,
            newQty,
            reference: transferId,
            notes: `Transfer to branch`,
            createdById: userId,
          },
        });

        // Update sent quantity
        await tx.stockTransferItem.update({
          where: { id: item.id },
          data: { sentQty: item.requestedQty },
        });
      }

      // Update transfer status
      return tx.stockTransfer.update({
        where: { id: transferId },
        data: { status: 'in_transit' },
      });
    }).then(async (result) => {
      // See receiveBatch for why this is needed: CatalogService caches
      // GET /products (with embedded stock) for 20s per tenant+branch.
      await this.redisService.invalidatePattern(`products:${tenantId}:*`);
      return result;
    });
  }

  async receiveTransfer(
    transferId: string,
    userId: string,
    tenantId: string,
    dto: ReceiveTransferDto,
    activeBranchId?: string,
  ) {
    const transfer = await this.getTransferInternal(transferId, tenantId);

    if (activeBranchId && transfer.toBranchId !== activeBranchId) {
      throw new ForbiddenException('Only the destination branch can confirm this transfer');
    }

    if (transfer.status !== 'in_transit') {
      throw new BadRequestException('Transfer is not in transit');
    }

    const sentItems = new Map(
      transfer.items.map((item) => [item.productId, Number(item.sentQty ?? item.requestedQty)]),
    );
    const receivedProductIds = new Set<string>();
    let hasDifference = false;
    let totalReceived = 0;
    for (const item of dto.receivedItems) {
      if (!sentItems.has(item.productId)) {
        throw new BadRequestException('Received items must match the dispatched transfer');
      }
      if (receivedProductIds.has(item.productId)) {
        throw new BadRequestException('Each transferred product must be listed once');
      }
      receivedProductIds.add(item.productId);
      const sentQty = sentItems.get(item.productId)!;
      if (item.quantity > sentQty) {
        throw new BadRequestException('Received quantity cannot exceed the amount dispatched');
      }
      totalReceived += item.quantity;
      if (item.quantity !== sentQty) hasDifference = true;
    }
    if (receivedProductIds.size !== sentItems.size) {
      throw new BadRequestException('Enter the received quantity for every transferred product');
    }
    if (totalReceived <= 0) {
      throw new BadRequestException('At least one transferred item must be received');
    }
    if (hasDifference && !dto.notes?.trim()) {
      throw new BadRequestException('Add a note explaining the quantity difference');
    }

    return this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`
        SELECT id FROM stock_transfers WHERE id = ${transferId} FOR UPDATE
      `;
      const lockedTransfer = await tx.stockTransfer.findUnique({
        where: { id: transferId },
        include: { items: true },
      });
      if (!lockedTransfer || lockedTransfer.status !== 'in_transit') {
        throw new BadRequestException('Transfer is not in transit');
      }

      for (const receivedItem of [...dto.receivedItems].sort((a, b) =>
        a.productId.localeCompare(b.productId),
      )) {
        const item = lockedTransfer.items.find(
          (candidate) => candidate.productId === receivedItem.productId,
        );
        if (!item) {
          throw new BadRequestException('Received items must match the dispatched transfer');
        }

        if (receivedItem.quantity > 0) {
          const stock = await lockStockForUpdate(
            tx,
            lockedTransfer.toBranchId,
            receivedItem.productId,
            true,
          );
          if (!stock) {
            throw new ConflictException('Could not lock destination stock');
          }

          const previousQty = Number(stock.quantity);
          const newQty = previousQty + receivedItem.quantity;

          await tx.stock.update({
            where: { id: stock.id },
            data: { quantity: newQty },
          });

          await tx.stockMovement.create({
            data: {
              branchId: lockedTransfer.toBranchId,
              productId: receivedItem.productId,
              type: StockMovementType.TRANSFER_IN,
              quantity: receivedItem.quantity,
              previousQty,
              newQty,
              reference: transferId,
              notes: `Transfer from branch`,
              createdById: userId,
            },
          });
        }

        // Update received quantity
        await tx.stockTransferItem.update({
          where: { id: item.id },
          data: { receivedQty: receivedItem.quantity },
        });
      }

      // Update transfer status
      return tx.stockTransfer.update({
        where: { id: transferId },
        data: {
          status: 'completed',
          approvedById: userId,
          notes: dto.notes
            ? `${lockedTransfer.notes || ''}\nReceived: ${dto.notes}`
            : lockedTransfer.notes,
        },
      });
    }).then(async (result) => {
      // See receiveBatch for why this is needed: CatalogService caches
      // GET /products (with embedded stock) for 20s per tenant+branch.
      await this.redisService.invalidatePattern(`products:${tenantId}:*`);
      return result;
    });
  }

  async getTransfer(
    transferId: string,
    tenantId: string,
    activeBranchId?: string,
  ) {
    const transfer = await this.getTransferInternal(transferId, tenantId);
    if (
      activeBranchId &&
      transfer.fromBranchId !== activeBranchId &&
      transfer.toBranchId !== activeBranchId
    ) {
      throw new ForbiddenException('Access denied');
    }
    const [branches, products] = await Promise.all([
      this.prisma.branch.findMany({
        where: {
          id: { in: [transfer.fromBranchId, transfer.toBranchId] },
          tenantId,
        },
        select: { id: true, name: true },
      }),
      this.prisma.product.findMany({
        where: {
          id: { in: transfer.items.map((item) => item.productId) },
          tenantId,
        },
        select: { id: true, name: true },
      }),
    ]);
    const branchNames = new Map(branches.map((branch) => [branch.id, branch.name]));
    const productNames = new Map(products.map((product) => [product.id, product.name]));

    return {
      id: transfer.id,
      fromBranchId: transfer.fromBranchId,
      fromBranchName: branchNames.get(transfer.fromBranchId),
      toBranchId: transfer.toBranchId,
      toBranchName: branchNames.get(transfer.toBranchId),
      status: transfer.status,
      notes: transfer.notes,
      items: transfer.items.map((i) => ({
        productId: i.productId,
        productName: productNames.get(i.productId),
        requestedQty: Number(i.requestedQty),
        sentQty: i.sentQty === null ? undefined : Number(i.sentQty),
        receivedQty: i.receivedQty === null ? undefined : Number(i.receivedQty),
      })),
      createdAt: transfer.createdAt,
      createdById: transfer.createdById,
    };
  }

  async getTransfers(
    tenantId: string,
    branchId?: string,
    status?: string,
    page = 1,
    limit = 20,
  ) {
    // A transfer belongs to the tenant only when both sides belong to it.
    const tenantBranches = await this.prisma.branch.findMany({
      where: { tenantId },
      select: { id: true, name: true },
    });
    const branchIds = tenantBranches.map((b) => b.id);
    const where: any = {
      AND: [
        { fromBranchId: { in: branchIds } },
        { toBranchId: { in: branchIds } },
      ],
    };
    if (branchId) {
      where.AND.push({
        OR: [{ fromBranchId: branchId }, { toBranchId: branchId }],
      });
    }
    if (status) where.status = status;

    const [transfers, total] = await Promise.all([
      this.prisma.stockTransfer.findMany({
        where,
        include: {
          items: {
            include: {
              transfer: false,
            },
          },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.stockTransfer.count({ where }),
    ]);

    const involvedBranchIds = [...new Set(
      transfers.flatMap((transfer) => [transfer.fromBranchId, transfer.toBranchId]),
    )];
    const involvedProductIds = [...new Set(
      transfers.flatMap((transfer) => transfer.items.map((item) => item.productId)),
    )];
    const [branches, products] = await Promise.all([
      this.prisma.branch.findMany({
        where: { id: { in: involvedBranchIds }, tenantId },
        select: { id: true, name: true },
      }),
      this.prisma.product.findMany({
        where: { id: { in: involvedProductIds }, tenantId },
        select: { id: true, name: true },
      }),
    ]);
    const branchNames = new Map(branches.map((branch) => [branch.id, branch.name]));
    const productNames = new Map(products.map((product) => [product.id, product.name]));

    return {
      items: transfers.map((transfer) => ({
        id: transfer.id,
        fromBranchId: transfer.fromBranchId,
        fromBranchName: branchNames.get(transfer.fromBranchId),
        toBranchId: transfer.toBranchId,
        toBranchName: branchNames.get(transfer.toBranchId),
        status: transfer.status,
        notes: transfer.notes,
        createdAt: transfer.createdAt,
        createdById: transfer.createdById,
        items: transfer.items.map((item) => ({
          productId: item.productId,
          productName: productNames.get(item.productId),
          requestedQty: Number(item.requestedQty),
          sentQty: item.sentQty === null ? undefined : Number(item.sentQty),
          receivedQty: item.receivedQty === null ? undefined : Number(item.receivedQty),
        })),
      })),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  // ==================== LOW STOCK ALERTS ====================

  async getLowStockAlerts(tenantId: string, branchId?: string) {
    const where: any = { tenantId, trackInventory: true };

    const products = await this.prisma.product.findMany({
      where,
      include: {
        stock: branchId
          ? { where: { branchId } }
          : { include: { branch: { select: { id: true, name: true } } } },
      },
    });

    const alerts: any[] = [];

    for (const product of products) {
      for (const stock of product.stock) {
        const quantity = Number(stock.quantity);
        if (quantity <= product.minStock) {
          alerts.push({
            productId: product.id,
            sku: product.sku,
            productName: product.name,
            branchId: stock.branchId,
            branchName: (stock as any).branch?.name,
            currentStock: quantity,
            minStock: product.minStock,
            shortfall: product.minStock - quantity,
          });
        }
      }
    }

    return alerts.sort((a, b) => b.shortfall - a.shortfall);
  }

  /**
   * Budget-aware restock suggestions: start from the same low-stock alerts
   * as getLowStockAlerts(), estimate a reorder quantity from each product's
   * recent sales velocity (units sold over the trailing 14 days), then trim
   * the list to fit whatever cash the branch currently has available —
   * fastest-selling items (soonest to stock out) are kept first since
   * they're the ones most likely to cause a lost sale.
   */
  async getRestockSuggestions(tenantId: string, branchId: string) {
    const alerts = await this.getLowStockAlerts(tenantId, branchId);
    if (alerts.length === 0) {
      return { branchId, availableCash: 0, items: [], trimmedCount: 0, aiRationale: null };
    }

    const windowStart = new Date();
    windowStart.setDate(windowStart.getDate() - 14);

    const productIds = alerts.map((a) => a.productId);
    const [velocity, products, cash, branch] = await Promise.all([
      this.prisma.saleItem.groupBy({
        by: ['productId'],
        where: {
          productId: { in: productIds },
          sale: { branchId, status: 'COMPLETED', createdAt: { gte: windowStart } },
        },
        _sum: { quantity: true },
      }),
      this.prisma.product.findMany({
        where: { id: { in: productIds } },
        select: { id: true, costPrice: true, basePrice: true },
      }),
      this.cashFlowService.getAvailableCash(branchId),
      this.prisma.branch.findUnique({ where: { id: branchId }, select: { name: true } }),
    ]);

    const velocityMap = new Map(velocity.map((v) => [v.productId, Number(v._sum.quantity) || 0]));
    const productMap = new Map(products.map((p) => [p.id, p]));

    const candidates = alerts
      .map((alert) => {
        const soldLast14Days = velocityMap.get(alert.productId) || 0;
        const dailyVelocity = soldLast14Days / 14;
        // Reorder enough to cover 14 days of typical demand plus the current
        // shortfall; fall back to just covering the shortfall when a product
        // hasn't sold recently (velocity data can't justify buying more).
        const suggestedQty = Math.max(alert.shortfall, Math.ceil(dailyVelocity * 14));
        const unitCost = Number(productMap.get(alert.productId)?.costPrice ?? productMap.get(alert.productId)?.basePrice ?? 0);
        const daysOfStockRemaining = dailyVelocity > 0 ? Math.floor(alert.currentStock / dailyVelocity) : 999;

        return {
          productId: alert.productId,
          productName: alert.productName,
          sku: alert.sku,
          currentStock: alert.currentStock,
          minStock: alert.minStock,
          suggestedQty,
          unitCost,
          estimatedCost: Math.round(suggestedQty * unitCost * 100) / 100,
          dailyVelocity,
          daysOfStockRemaining,
        };
      })
      // Fastest-selling / soonest-to-stock-out first — these cause the most
      // immediate lost sales if left unfunded.
      .sort((a, b) => a.daysOfStockRemaining - b.daysOfStockRemaining);

    const budget = Math.max(cash.availableCash, 0);
    let remainingBudget = budget;
    const items: typeof candidates = [];
    let trimmedCount = 0;

    for (const candidate of candidates) {
      if (candidate.estimatedCost <= 0) continue;
      if (candidate.estimatedCost <= remainingBudget) {
        items.push(candidate);
        remainingBudget -= candidate.estimatedCost;
      } else {
        trimmedCount += 1;
      }
    }

    const aiRationale = await this.aiService.explainRestockPlan({
      branchName: branch?.name || 'this branch',
      availableCash: budget,
      items: items.map((i) => ({
        productName: i.productName,
        suggestedQty: i.suggestedQty,
        estimatedCost: i.estimatedCost,
        daysOfStockRemaining: i.daysOfStockRemaining,
      })),
      trimmedCount,
    });

    return { branchId, availableCash: budget, items, trimmedCount, aiRationale };
  }

  async bulkAdjustStock(
    userId: string,
    tenantId: string,
    branchId: string,
    adjustments: Array<{ productId: string; quantity: number; notes?: string }>,
  ) {
    // Verify branch exists in the tenant
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
    });

    if (!branch) {
      throw new ForbiddenException('Branch not found or access denied');
    }

    return this.prisma.$transaction(async (tx) => {
      const results: any[] = [];

      for (const adjustment of [...adjustments].sort((a, b) =>
        a.productId.localeCompare(b.productId),
      )) {
        const stock = await lockStockForUpdate(
          tx,
          branchId,
          adjustment.productId,
          true,
        );
        if (!stock) {
          throw new ConflictException('Could not lock stock for adjustment');
        }
        const previousQty = Number(stock.quantity);
        const newQty = previousQty + adjustment.quantity;
        const updatedStock = await tx.stock.update({
          where: { id: stock.id },
          data: { quantity: newQty },
        });

        // Create a stockMovement record with type ADJUSTMENT
        const movement = await tx.stockMovement.create({
          data: {
            branchId,
            productId: adjustment.productId,
            type: StockMovementType.ADJUSTMENT,
            quantity: adjustment.quantity,
            previousQty,
            newQty,
            notes: adjustment.notes,
            createdById: userId,
          },
        });

        results.push({ stock: updatedStock, movement });
      }

      return results;
    }).then(async (result) => {
      // See receiveBatch for why this is needed: CatalogService caches
      // GET /products (with embedded stock) for 20s per tenant+branch.
      await this.redisService.invalidatePattern(`products:${tenantId}:*`);
      return result;
    });
  }

  // ==================== HELPERS ====================

  private async getTransferInternal(transferId: string, tenantId: string) {
    const transfer = await this.prisma.stockTransfer.findUnique({
      where: { id: transferId },
      include: {
        items: {
          include: {
            transfer: false,
          },
        },
      },
    });

    if (!transfer) {
      throw new NotFoundException('Transfer not found');
    }

    // Verify both sides belong to this tenant; checking only the source branch
    // could expose a cross-tenant destination or allow a forged transfer row.
    const branches = await this.prisma.branch.findMany({
      where: {
        id: { in: [transfer.fromBranchId, transfer.toBranchId] },
        tenantId,
      },
      select: { id: true },
    });

    if (branches.length !== 2) {
      throw new ForbiddenException('Access denied');
    }

    return transfer;
  }

  private matchesTransferRequest(
    transfer: {
      fromBranchId: string;
      toBranchId: string;
      notes: string | null;
      items: Array<{ productId: string; requestedQty: unknown }>;
    },
    dto: CreateTransferDto,
  ) {
    if (
      transfer.fromBranchId !== dto.fromBranchId ||
      transfer.toBranchId !== dto.toBranchId ||
      (transfer.notes ?? undefined) !== dto.notes ||
      transfer.items.length !== dto.items.length
    ) {
      return false;
    }

    const existingItems = new Map(
      transfer.items.map((item) => [item.productId, Number(item.requestedQty)]),
    );
    return dto.items.every(
      (item) => existingItems.get(item.productId) === item.quantity,
    );
  }

  // ==================== BATCH MANAGEMENT ====================

  /**
   * Receive stock with batch tracking
   * Used when stock keeper receives new inventory
   */
  async receiveBatch(userId: string, tenantId: string, dto: ReceiveBatchDto) {
    // Verify branch and product
    const [branch, product] = await Promise.all([
      this.prisma.branch.findFirst({ where: { id: dto.branchId, tenantId } }),
      this.prisma.product.findFirst({
        where: { id: dto.productId, tenantId },
        include: { pricingTiers: true },
      }),
    ]);

    if (!branch) throw new NotFoundException('Branch not found');
    if (!product) throw new NotFoundException('Product not found');

    return this.prisma.$transaction(async (tx) => {
      const lockedStock = await lockStockForUpdate(
        tx,
        dto.branchId,
        dto.productId,
        true,
      );
      if (!lockedStock) {
        throw new ConflictException('Could not lock stock for receiving');
      }
      const stock = lockedStock;

      const createdBatches = [];
      const receivedUnits: Array<{
        quantity: number;
        unit: string;
        unitsPerQuantity: number;
        baseQuantity: number;
      }> = [];
      const batchReceipts: Array<{
        batchId: string;
        batchNumber: string;
        baseQuantity: number;
        expiryDate: Date | null;
        notes: string;
      }> = [];
      let totalReceived = 0;
      let runningQuantity = Number(lockedStock.quantity);
      // Cost is averaged in batch by batch, from the quantity on hand at that point.
      let costRunningQuantity = runningQuantity;

      // Auto-generate batch numbers when not supplied: <SKU>-<YYMMDD>-<seq>
      const skuPrefix = this.getBatchSkuPrefix(product.sku);
      const datePart = this.getBatchDatePart();
      const batchPrefix = `${skuPrefix}-${datePart}-`;

      // Start from the highest existing sequence for this prefix instead of a
      // simple count — count can be lower than the max sequence if batches were
      // deleted or created out of order, which causes repeated P2002 conflicts.
      const existingBatches = await tx.stockBatch.findMany({
        where: { stockId: stock.id, batchNumber: { startsWith: batchPrefix } },
        select: { batchNumber: true },
      });

      const existingBatchNumbers =
          new Set(existingBatches.map((b) => b.batchNumber));
      const batchNumberRegex = new RegExp(
        `${batchPrefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(\\d{3})$`,
      );

      let seq = 0;
      for (const { batchNumber } of existingBatches) {
        const match = batchNumber.match(batchNumberRegex);
        if (match) {
          seq = Math.max(seq, parseInt(match[1], 10));
        }
      }

      // Create batch records
      for (const batch of dto.batches) {
        // Unit conversion logic
        let baseQuantity = batch.quantity;
        let conversionNote = '';

        // If unit is provided and it's not the base unit, convert to base units
        if (batch.unit && batch.unit !== product.unit) {
          const conversionFactor = batch.unitsPerQuantity || this.getConversionFactor(
            product,
            batch.unit
          );

          if (conversionFactor) {
            baseQuantity = batch.quantity * conversionFactor;
            conversionNote = `Received ${batch.quantity} ${batch.unit} = ${baseQuantity} ${product.unit}`;
          } else {
            throw new Error(
              `No conversion factor found for unit "${batch.unit}". ` +
              `Please configure unit conversions for this product.`
            );
          }
        } else if (batch.unitsPerQuantity && batch.unitsPerQuantity !== 1) {
          // Manual conversion factor provided
          baseQuantity = batch.quantity * batch.unitsPerQuantity;
          conversionNote = `Received ${batch.quantity} ${batch.unit || 'units'} = ${baseQuantity} ${product.unit}`;
        }

        // Record the entered unit even when it is already the base unit.
        // Other devices rebuild the preferred stock display from this note.
        if (!conversionNote) {
          conversionNote = `Received ${batch.quantity} ${batch.unit || product.unit} = ${baseQuantity} ${product.unit}`;
        }

        const expiryDate = batch.expiryDate ? new Date(batch.expiryDate) : null;
        // `expiryDate && ...` evaluates to `null` (not `false`) when there's
        // no expiry date — isBlocked is a non-nullable Boolean column, and
        // passing it `null` makes Prisma reject the ENTIRE create() as
        // invalid (misleadingly reported as "Argument `stock` is missing",
        // since it falls back to describing the relation-based input shape
        // instead of naming the real offending field). This surfaced to
        // users as an unconditional "Batch number conflict" on every batch
        // received without an expiry date, regardless of batch numbers.
        const isExpired = Boolean(expiryDate && expiryDate < new Date());

        // Combine notes with conversion info
        const finalNotes = conversionNote
          ? batch.notes
            ? `${conversionNote}. ${batch.notes}`
            : conversionNote
          : batch.notes;

        const suppliedBatchNumber = batch.batchNumber?.trim();
        let createdBatch;

        if (suppliedBatchNumber) {
          createdBatch = await tx.stockBatch.create({
            data: {
              stockId: stock.id,
              batchNumber: suppliedBatchNumber,
              quantity: baseQuantity,
              expiryDate,
              manufactureDate: batch.manufactureDate ? new Date(batch.manufactureDate) : null,
              costPrice: batch.costPrice,
              supplierRef: batch.supplierRef,
              notes: finalNotes,
              isBlocked: isExpired, // Auto-block expired batches
            },
          });
        } else {
          const maxAttempts = 50;
          for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
            seq += 1;
            const candidateBatchNumber = `${batchPrefix}${String(seq).padStart(3, '0')}`;

            // If this exact number is already known, don't waste a DB round-trip.
            if (existingBatchNumbers.has(candidateBatchNumber)) {
              continue;
            }

            try {
              createdBatch = await tx.stockBatch.create({
                data: {
                  stockId: stock.id,
                  batchNumber: candidateBatchNumber,
                  quantity: baseQuantity,
                  expiryDate,
                  manufactureDate: batch.manufactureDate ? new Date(batch.manufactureDate) : null,
                  costPrice: batch.costPrice,
                  supplierRef: batch.supplierRef,
                  notes: finalNotes,
                  isBlocked: isExpired, // Auto-block expired batches
                },
              });
              break;
            } catch (error) {
              // P2002 = unique constraint violation. Another request likely
              // grabbed the same candidate. Retry with the next number.
              if (error.code === 'P2002' && attempt < maxAttempts - 1) {
                continue;
              }

              // Last-resort fallback: append a random 4-char suffix so the
              // user can still receive stock even if the sequence is exhausted.
              const fallback = `${candidateBatchNumber}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`;
              try {
                createdBatch = await tx.stockBatch.create({
                  data: {
                    stockId: stock.id,
                    batchNumber: fallback,
                    quantity: baseQuantity,
                    expiryDate,
                    manufactureDate: batch.manufactureDate ? new Date(batch.manufactureDate) : null,
                    costPrice: batch.costPrice,
                    supplierRef: batch.supplierRef,
                    notes: finalNotes,
                    isBlocked: isExpired,
                  },
                });
                break;
              } catch (fallbackError) {
                throw new ConflictException(
                  'Could not generate a unique batch number, please retry',
                );
              }
            }
          }
        }

        createdBatches.push(createdBatch);
        totalReceived += baseQuantity;
        await applyPurchaseCost(tx, product.id, costRunningQuantity, baseQuantity, batch.costPrice);
        costRunningQuantity += baseQuantity;
        receivedUnits.push({
          quantity: batch.quantity,
          unit: batch.unit || product.unit,
          unitsPerQuantity: baseQuantity / batch.quantity,
          baseQuantity,
        });

        batchReceipts.push({
          batchId: createdBatch.id,
          batchNumber: createdBatch.batchNumber,
          baseQuantity,
          expiryDate,
          notes: finalNotes,
        });
      }

      const lastReceivedUnit = receivedUnits[receivedUnits.length - 1];
      const samePackaging = receivedUnits.every(
        (entry) =>
          entry.unit === lastReceivedUnit.unit &&
          entry.unitsPerQuantity === lastReceivedUnit.unitsPerQuantity,
      );
      const receiptMetadata = {
        quantity: samePackaging
          ? receivedUnits.reduce((sum, entry) => sum + entry.quantity, 0)
          : lastReceivedUnit.quantity,
        unit: lastReceivedUnit.unit,
        unitsPerQuantity: lastReceivedUnit.unitsPerQuantity,
        baseQuantity: samePackaging
          ? receivedUnits.reduce((sum, entry) => sum + entry.baseQuantity, 0)
          : lastReceivedUnit.baseQuantity,
      };
      const receiptMarker =
        `[Receipt metadata: quantity=${receiptMetadata.quantity}; ` +
        `unit=${encodeURIComponent(receiptMetadata.unit)}; ` +
        `unitsPerQuantity=${receiptMetadata.unitsPerQuantity}]`;

      const latestMovement = await tx.stockMovement.findFirst({
        where: { branchId: dto.branchId, productId: dto.productId },
        orderBy: { createdAt: 'desc' },
        select: { createdAt: true },
      });
      let nextMovementTimestamp = Math.max(
        Date.now(),
        (latestMovement?.createdAt.getTime() ?? 0) + 1,
      );

      // Every movement in this receive carries the same aggregate marker.
      // A remote phone therefore reconstructs the same display metadata no
      // matter which tied movement is applied last.
      for (const receipt of batchReceipts) {
        const previousQuantity = runningQuantity;
        runningQuantity += receipt.baseQuantity;
        await tx.stockMovement.create({
          data: {
            branchId: dto.branchId,
            productId: dto.productId,
            batchId: receipt.batchId,
            type: StockMovementType.BATCH_RECEIVE,
            quantity: receipt.baseQuantity,
            previousQty: previousQuantity,
            newQty: runningQuantity,
            batchNumber: receipt.batchNumber,
            expiryDate: receipt.expiryDate,
            reference: dto.reference,
            notes: `${receiptMarker} ${receipt.notes}`,
            createdById: userId,
            createdAt: new Date(nextMovementTimestamp++),
          },
        });
      }

      // Update total stock quantity
      const updatedStock = await tx.stock.update({
        where: { id: stock.id },
        data: {
          quantity: { increment: totalReceived },
        },
      });

      return {
        success: true,
        stockId: stock.id,
        batchesReceived: createdBatches.length,
        totalQuantity: totalReceived,
        currentQuantity: Number(updatedStock.quantity),
        receiptMetadata,
        receivedUnits,
        batches: createdBatches,
      };
    }).then(async (result) => {
      // CatalogService caches GET /products responses (with embedded stock
      // quantities) for 20s per tenant+branch. Without invalidating here,
      // a receive-stock immediately followed by reopening the Products
      // screen could show the pre-receipt quantity for up to 20s — looking
      // exactly like the stock update silently failed even though it
      // committed. Mirrors the same invalidatePattern CatalogService calls
      // on every write of its own.
      await this.redisService.invalidatePattern(`products:${tenantId}:*`);
      return result;
    });
  }

  /**
   * Sanitized, uppercase SKU prefix used as the human-readable part of an
   * auto-generated batch number.
   */
  private getBatchSkuPrefix(sku: string): string {
    return sku.toUpperCase().replace(/[^A-Z0-9]+/g, '').slice(0, 10) || 'ITEM';
  }

  /**
   * YYMMDD date part used as the second segment of an auto-generated batch number.
   */
  private getBatchDatePart(): string {
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    return `${yy}${mm}${dd}`;
  }

  /**
   * Get conversion factor for a unit based on product configuration
   */
  private getConversionFactor(product: any, unit: string): number | null {
    const unitLower = unit.toLowerCase();
    const baseUnit = product.unit.toLowerCase();

    // If it's the base unit, no conversion needed
    if (unitLower === baseUnit) return 1;

    const tier = (product.pricingTiers ?? []).find(
      (t: any) => t.unit.toLowerCase() === unitLower,
    );
    return tier ? Number(tier.quantityPerUnit) || null : null;
  }

  /**
   * Get stock with batch details
   */
  async getStockWithBatches(
    branchId: string,
    productId: string,
    tenantId: string,
  ): Promise<StockWithBatchesResponseDto> {
    const stock = await this.prisma.stock.findUnique({
      where: {
        branchId_productId: {
          branchId,
          productId,
        },
      },
      include: {
        product: true,
        batches: {
          orderBy: { expiryDate: 'asc' }, // FEFO ordering
        },
      },
    });

    if (!stock) {
      throw new NotFoundException('Stock not found for this product in this branch');
    }

    const now = new Date();
    const batches: BatchResponseDto[] = stock.batches.map((batch) => {
      const availableQty = Number(batch.quantity) - Number(batch.reservedQty);
      const isExpired = batch.expiryDate ? batch.expiryDate < now : false;
      const daysUntilExpiry = batch.expiryDate
        ? Math.ceil((batch.expiryDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24))
        : undefined;

      let expiryStatus: 'expired' | 'expiring_soon' | 'good' = 'good';
      if (isExpired) {
        expiryStatus = 'expired';
      } else if (daysUntilExpiry !== undefined && daysUntilExpiry <= 90) {
        expiryStatus = 'expiring_soon';
      }

      return {
        id: batch.id,
        batchNumber: batch.batchNumber,
        quantity: Number(batch.quantity),
        reservedQty: Number(batch.reservedQty),
        availableQty,
        expiryDate: batch.expiryDate,
        manufactureDate: batch.manufactureDate,
        costPrice: batch.costPrice ? Number(batch.costPrice) : undefined,
        supplierRef: batch.supplierRef,
        notes: batch.notes,
        isBlocked: batch.isBlocked || isExpired,
        isExpired,
        daysUntilExpiry,
        expiryStatus,
        createdAt: batch.createdAt,
      };
    });

    const totalQuantity = batches.reduce((sum, b) => sum + b.quantity, 0);
    const totalReservedQty = batches.reduce((sum, b) => sum + b.reservedQty, 0);

    return {
      productId: stock.product.id,
      sku: stock.product.sku,
      productName: stock.product.name,
      totalQuantity,
      totalReservedQty,
      totalAvailableQty: totalQuantity - totalReservedQty,
      batches,
      hasExpiredBatches: batches.some((b) => b.isExpired),
      hasExpiringSoonBatches: batches.some((b) => b.expiryStatus === 'expiring_soon'),
    };
  }

  /**
   * FEFO Logic: Allocate stock from batches closest to expiry
   * Returns array of batch allocations for a requested quantity
   */
  async allocateBatchesFEFO(
    branchId: string,
    productId: string,
    requestedQty: number,
    tenantId: string,
  ): Promise<Array<{ batchId: string; batchNumber: string; quantity: number; expiryDate?: Date }>> {
    const stock = await this.prisma.stock.findUnique({
      where: {
        branchId_productId: {
          branchId,
          productId,
        },
      },
      include: {
        batches: {
          where: {
            isBlocked: false,
            expiryDate: { gt: new Date() }, // Only non-expired batches
          },
          orderBy: { expiryDate: 'asc' }, // FEFO: First expiry first
        },
      },
    });

    if (!stock) {
      throw new NotFoundException('Stock not found');
    }

    const allocations: Array<{ batchId: string; batchNumber: string; quantity: number; expiryDate?: Date }> = [];
    let remainingQty = requestedQty;

    for (const batch of stock.batches) {
      const availableQty = Number(batch.quantity) - Number(batch.reservedQty);
      
      if (availableQty <= 0) continue;

      const allocateQty = Math.min(availableQty, remainingQty);

      allocations.push({
        batchId: batch.id,
        batchNumber: batch.batchNumber,
        quantity: allocateQty,
        expiryDate: batch.expiryDate,
      });

      remainingQty -= allocateQty;

      if (remainingQty <= 0) break;
    }

    if (remainingQty > 0) {
      throw new BadRequestException(
        `Insufficient non-expired stock. Requested: ${requestedQty}, Available: ${requestedQty - remainingQty}`,
      );
    }

    return allocations;
  }

  /**
   * Update batch details (e.g., block, adjust quantity)
   */
  async updateBatch(
    batchId: string,
    userId: string,
    tenantId: string,
    dto: UpdateBatchDto,
  ) {
    const batch = await this.prisma.stockBatch.findUnique({
      where: { id: batchId },
      include: { stock: { include: { branch: true, product: true } } },
    });

    if (!batch) {
      throw new NotFoundException('Batch not found');
    }

    // Verify tenant access
    if (batch.stock.branch.tenantId !== tenantId) {
      throw new ForbiddenException('Access denied');
    }

    return this.prisma.$transaction(async (tx) => {
      const lockedStock = await lockStockForUpdate(
        tx,
        batch.stock.branchId,
        batch.stock.productId,
      );
      if (!lockedStock) {
        throw new ConflictException('Could not lock stock for batch update');
      }
      const [lockedBatch] = await tx.$queryRaw<Array<{ quantity: unknown }>>`
        SELECT quantity
        FROM stock_batches
        WHERE id = ${batchId}
        FOR UPDATE
      `;
      if (!lockedBatch) {
        throw new ConflictException('Could not lock batch for update');
      }

      const previousBatchQty = Number(lockedBatch.quantity);
      const updateData: any = {};

      if (dto.quantity !== undefined) {
        updateData.quantity = dto.quantity;
        const qtyChange = dto.quantity - previousBatchQty;
        const previousQty = Number(lockedStock.quantity);
        const newQty = previousQty + qtyChange;

        // Update total stock
        await tx.stock.update({
          where: { id: lockedStock.id },
          data: { quantity: newQty },
        });

        // Record movement
        await tx.stockMovement.create({
          data: {
            branchId: batch.stock.branchId,
            productId: batch.stock.productId,
            batchId: batch.id,
            type: StockMovementType.ADJUSTMENT,
            quantity: qtyChange,
            previousQty,
            newQty,
            batchNumber: batch.batchNumber,
            expiryDate: batch.expiryDate,
            notes: dto.notes || 'Batch quantity adjustment',
            createdById: userId,
          },
        });
      }

      if (dto.expiryDate !== undefined) {
        updateData.expiryDate = new Date(dto.expiryDate);
      }

      if (dto.isBlocked !== undefined) {
        updateData.isBlocked = dto.isBlocked;
      }

      if (dto.notes !== undefined) {
        updateData.notes = dto.notes;
      }

      return tx.stockBatch.update({
        where: { id: batchId },
        data: updateData,
      });
    }).then(async (result) => {
      // See receiveBatch for why this is needed: CatalogService caches
      // GET /products (with embedded stock) for 20s per tenant+branch.
      // Only the quantity edit path actually changes total stock, but the
      // batch's own product could be shown elsewhere too — cheap either way.
      await this.redisService.invalidatePattern(`products:${tenantId}:*`);
      return result;
    });
  }

  /**
   * Expiry Dashboard: Shows products expiring in different time zones
   */
  async getExpiryDashboard(
    tenantId: string,
    query: ExpiryDashboardQueryDto,
  ): Promise<ExpiryDashboardResponseDto> {
    const { branchId, zone, search, page = 1, limit = 50 } = query;

    // Verify branch
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    const now = new Date();
    const whereClause: any = {
      stock: {
        branchId,
      },
    };

    // Filter by expiry zone
    if (zone === 'expired') {
      whereClause.expiryDate = { lt: now };
    } else if (zone === '30days') {
      const days30 = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
      whereClause.expiryDate = { gte: now, lte: days30 };
    } else if (zone === '60days') {
      const days30 = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
      const days60 = new Date(now.getTime() + 60 * 24 * 60 * 60 * 1000);
      whereClause.expiryDate = { gt: days30, lte: days60 };
    } else if (zone === '90days') {
      const days60 = new Date(now.getTime() + 60 * 24 * 60 * 60 * 1000);
      const days90 = new Date(now.getTime() + 90 * 24 * 60 * 60 * 1000);
      whereClause.expiryDate = { gt: days60, lte: days90 };
    }

    // Search filter
    if (search) {
      whereClause.stock = {
        ...whereClause.stock,
        product: {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            { sku: { contains: search, mode: 'insensitive' } },
          ],
        },
      };
    }

    const [batches, total] = await Promise.all([
      this.prisma.stockBatch.findMany({
        where: whereClause,
        include: {
          stock: {
            include: {
              product: { select: { id: true, name: true, sku: true } },
            },
          },
        },
        orderBy: { expiryDate: 'asc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.stockBatch.count({ where: whereClause }),
    ]);

    // Calculate summary — four targeted zone queries instead of pulling
    // every batch for the branch into memory. costPrice*quantity value per
    // zone still has to be summed row-by-row (Prisma has no computed-column
    // SUM), but each query only touches the batches in that zone rather
    // than the branch's entire batch history.
    const days30 = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    const days60 = new Date(now.getTime() + 60 * 24 * 60 * 60 * 1000);
    const days90 = new Date(now.getTime() + 90 * 24 * 60 * 60 * 1000);

    const zoneWhere = (range: { lt?: Date; gt?: Date; lte?: Date; gte?: Date }) => ({
      stock: { branchId },
      expiryDate: range,
    });

    const [expiredBatches, expiring30Batches, expiring60Batches, expiring90Batches] =
      await Promise.all([
        this.prisma.stockBatch.findMany({
          where: zoneWhere({ lt: now }),
          select: { quantity: true, costPrice: true },
        }),
        this.prisma.stockBatch.findMany({
          where: zoneWhere({ gte: now, lte: days30 }),
          select: { quantity: true, costPrice: true },
        }),
        this.prisma.stockBatch.findMany({
          where: zoneWhere({ gt: days30, lte: days60 }),
          select: { quantity: true, costPrice: true },
        }),
        this.prisma.stockBatch.findMany({
          where: zoneWhere({ gt: days60, lte: days90 }),
          select: { quantity: true, costPrice: true },
        }),
      ]);

    const summarizeZone = (rows: Array<{ quantity: any; costPrice: any }>) =>
      rows.reduce(
        (acc, row) => {
          const qty = Number(row.quantity);
          const value = row.costPrice ? qty * Number(row.costPrice) : 0;
          return { count: acc.count + 1, value: acc.value + value };
        },
        { count: 0, value: 0 },
      );

    const expired = summarizeZone(expiredBatches);
    const expiring30 = summarizeZone(expiring30Batches);
    const expiring60 = summarizeZone(expiring60Batches);
    const expiring90 = summarizeZone(expiring90Batches);

    const summary = {
      expiredCount: expired.count,
      expiredValue: expired.value,
      expiring30Days: expiring30.count,
      expiring30DaysValue: expiring30.value,
      expiring60Days: expiring60.count,
      expiring60DaysValue: expiring60.value,
      expiring90Days: expiring90.count,
      expiring90DaysValue: expiring90.value,
    };

    const items = batches.map((batch) => {
      const daysUntilExpiry = batch.expiryDate
        ? Math.ceil((batch.expiryDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24))
        : undefined;

      let expiryStatus: 'expired' | 'critical' | 'warning' | 'good' = 'good';
      if (batch.expiryDate) {
        if (batch.expiryDate < now) {
          expiryStatus = 'expired';
        } else if (daysUntilExpiry !== undefined && daysUntilExpiry <= 30) {
          expiryStatus = 'critical';
        } else if (daysUntilExpiry !== undefined && daysUntilExpiry <= 90) {
          expiryStatus = 'warning';
        }
      }

      const qty = Number(batch.quantity);
      const costValue = batch.costPrice ? qty * Number(batch.costPrice) : undefined;

      return {
        productId: batch.stock.product.id,
        productName: batch.stock.product.name,
        sku: batch.stock.product.sku,
        batchNumber: batch.batchNumber,
        quantity: qty,
        expiryDate: batch.expiryDate,
        daysUntilExpiry,
        expiryStatus,
        isBlocked: batch.isBlocked,
        costValue,
      };
    });

    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
      summary,
    };
  }

  /**
   * Auto-block expired batches (run as cron job)
   */
  async blockExpiredBatches(tenantId: string) {
    const now = new Date();

    // Find all expired batches that are not blocked
    const expiredBatches = await this.prisma.stockBatch.findMany({
      where: {
        expiryDate: { lt: now },
        isBlocked: false,
        stock: {
          branch: { tenantId },
        },
      },
    });

    // Block them
    const blockedCount = await this.prisma.stockBatch.updateMany({
      where: {
        id: { in: expiredBatches.map((b) => b.id) },
      },
      data: {
        isBlocked: true,
      },
    });

    return {
      success: true,
      blockedCount: blockedCount.count,
      batches: expiredBatches.map((b) => ({
        id: b.id,
        batchNumber: b.batchNumber,
        expiryDate: b.expiryDate,
      })),
    };
  }

  // ==================== STOCK REQUEST METHODS ====================

  /**
   * Create a new stock request (cashiers/sellers request stock)
   */
  async createStockRequest(
    userId: string,
    tenantId: string,
    dto: {
      branchId: string;
      productId: string;
      quantity: number;
      unit?: string;
      reason?: string;
      priority?: string;
      images?: string[];
    },
  ) {
    // Verify branch and product belong to tenant
    const [branch, product] = await Promise.all([
      this.prisma.branch.findFirst({
        where: { id: dto.branchId, tenantId },
      }),
      this.prisma.product.findFirst({
        where: { id: dto.productId, tenantId },
      }),
    ]);

    if (!branch || !product) {
      throw new Error('Branch or product not found');
    }

    // Get current stock level
    const stock = await this.prisma.stock.findUnique({
      where: {
        branchId_productId: {
          branchId: dto.branchId,
          productId: dto.productId,
        },
      },
    });

    // Create the request
    const request = await this.prisma.stockRequest.create({
      data: {
        branchId: dto.branchId,
        requestedById: userId,
        productId: dto.productId,
        quantity: dto.quantity,
        unit: dto.unit || product.unit,
        reason: dto.reason,
        priority: dto.priority || 'normal',
        images: dto.images || [],
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        product: { select: { name: true, sku: true, unit: true } },
      },
    });

    return {
      id: request.id,
      branchId: request.branchId,
      branchName: request.branch.name,
      requestedById: request.requestedById,
      requestedByName: `${request.requestedBy.firstName} ${request.requestedBy.lastName}`,
      productId: request.productId,
      productName: request.product.name,
      productSku: request.product.sku,
      quantity: Number(request.quantity),
      unit: request.unit,
      reason: request.reason,
      priority: request.priority,
      status: request.status,
      images: request.images,
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      currentStock: stock ? Number(stock.quantity) : 0,
    };
  }

  /**
   * Get stock requests (filtered by role and permissions)
   */
  async getStockRequests(
    userId: string,
    tenantId: string,
    query: {
      branchId?: string;
      status?: string;
      priority?: string;
      productId?: string;
      requestedById?: string;
      page?: number;
      limit?: number;
    },
  ) {
    const page = query.page || 1;
    const limit = query.limit || 20;
    const skip = (page - 1) * limit;

    // Build where clause
    const where: any = {
      branch: { tenantId },
    };

    if (query.branchId) where.branchId = query.branchId;
    if (query.status) where.status = query.status;
    if (query.priority) where.priority = query.priority;
    if (query.productId) where.productId = query.productId;
    if (query.requestedById) where.requestedById = query.requestedById;

    const [requests, total] = await Promise.all([
      this.prisma.stockRequest.findMany({
        where,
        include: {
          branch: { select: { name: true } },
          requestedBy: { select: { firstName: true, lastName: true } },
          product: { select: { name: true, sku: true, unit: true } },
          resolvedBy: { select: { firstName: true, lastName: true } },
        },
        orderBy: [
          { status: 'asc' }, // Pending first
          { createdAt: 'desc' },
        ],
        skip,
        take: limit,
      }),
      this.prisma.stockRequest.count({ where }),
    ]);

    // Get current stock for each request
    const stockData = await Promise.all(
      requests.map((request) =>
        this.prisma.stock.findUnique({
          where: {
            branchId_productId: {
              branchId: request.branchId,
              productId: request.productId,
            },
          },
          select: { quantity: true },
        }),
      ),
    );

    const items = requests.map((request, index) => ({
      id: request.id,
      branchId: request.branchId,
      branchName: request.branch.name,
      requestedById: request.requestedById,
      requestedByName: `${request.requestedBy.firstName} ${request.requestedBy.lastName}`,
      productId: request.productId,
      productName: request.product.name,
      productSku: request.product.sku,
      quantity: Number(request.quantity),
      unit: request.unit,
      reason: request.reason,
      priority: request.priority,
      status: request.status,
      images: request.images,
      resolvedById: request.resolvedById,
      resolvedByName: request.resolvedBy
        ? `${request.resolvedBy.firstName} ${request.resolvedBy.lastName}`
        : undefined,
      resolvedAt: request.resolvedAt,
      resolution: request.resolution,
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      currentStock: stockData[index] ? Number(stockData[index].quantity) : 0,
    }));

    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  /**
   * Get a single stock request
   */
  async getStockRequest(id: string, tenantId: string) {
    const request = await this.prisma.stockRequest.findFirst({
      where: {
        id,
        branch: { tenantId },
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        product: { select: { name: true, sku: true, unit: true } },
        resolvedBy: { select: { firstName: true, lastName: true } },
      },
    });

    if (!request) {
      throw new Error('Stock request not found');
    }

    const stock = await this.prisma.stock.findUnique({
      where: {
        branchId_productId: {
          branchId: request.branchId,
          productId: request.productId,
        },
      },
      select: { quantity: true },
    });

    return {
      id: request.id,
      branchId: request.branchId,
      branchName: request.branch.name,
      requestedById: request.requestedById,
      requestedByName: `${request.requestedBy.firstName} ${request.requestedBy.lastName}`,
      productId: request.productId,
      productName: request.product.name,
      productSku: request.product.sku,
      quantity: Number(request.quantity),
      unit: request.unit,
      reason: request.reason,
      priority: request.priority,
      status: request.status,
      images: request.images,
      resolvedById: request.resolvedById,
      resolvedByName: request.resolvedBy
        ? `${request.resolvedBy.firstName} ${request.resolvedBy.lastName}`
        : undefined,
      resolvedAt: request.resolvedAt,
      resolution: request.resolution,
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      currentStock: stock ? Number(stock.quantity) : 0,
    };
  }

  /**
   * Update a stock request (requester can edit before approval)
   */
  async updateStockRequest(
    id: string,
    userId: string,
    tenantId: string,
    dto: {
      quantity?: number;
      unit?: string;
      reason?: string;
      priority?: string;
      images?: string[];
    },
  ) {
    // Verify request exists and belongs to user
    const existing = await this.prisma.stockRequest.findFirst({
      where: {
        id,
        requestedById: userId,
        branch: { tenantId },
        status: 'PENDING', // Can only edit pending requests
      },
    });

    if (!existing) {
      throw new Error('Stock request not found or cannot be edited');
    }

    const updated = await this.prisma.stockRequest.update({
      where: { id },
      data: {
        ...(dto.quantity !== undefined && { quantity: dto.quantity }),
        ...(dto.unit && { unit: dto.unit }),
        ...(dto.reason !== undefined && { reason: dto.reason }),
        ...(dto.priority && { priority: dto.priority }),
        ...(dto.images && { images: dto.images }),
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        product: { select: { name: true, sku: true } },
      },
    });

    return {
      id: updated.id,
      branchId: updated.branchId,
      branchName: updated.branch.name,
      requestedById: updated.requestedById,
      requestedByName: `${updated.requestedBy.firstName} ${updated.requestedBy.lastName}`,
      productId: updated.productId,
      productName: updated.product.name,
      productSku: updated.product.sku,
      quantity: Number(updated.quantity),
      unit: updated.unit,
      reason: updated.reason,
      priority: updated.priority,
      status: updated.status,
      images: updated.images,
      createdAt: updated.createdAt,
      updatedAt: updated.updatedAt,
    };
  }

  /**
   * Resolve a stock request (approve/reject/fulfill) - Supervisor+ only
   */
  async resolveStockRequest(
    id: string,
    userId: string,
    tenantId: string,
    dto: {
      status: 'APPROVED' | 'REJECTED' | 'FULFILLED';
      resolution?: string;
    },
  ) {
    const request = await this.prisma.stockRequest.findFirst({
      where: {
        id,
        branch: { tenantId },
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        product: { select: { name: true, sku: true } },
      },
    });

    if (!request) {
      throw new Error('Stock request not found');
    }

    if (request.status !== 'PENDING' && request.status !== 'APPROVED') {
      throw new Error('Can only resolve pending or approved requests');
    }

    const updated = await this.prisma.stockRequest.update({
      where: { id },
      data: {
        status: dto.status,
        resolvedById: userId,
        resolvedAt: new Date(),
        resolution: dto.resolution,
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        product: { select: { name: true, sku: true } },
        resolvedBy: { select: { firstName: true, lastName: true } },
      },
    });

    // Fire-and-forget: the requester should hear about the outcome, but a
    // notification failure must never fail the resolve action itself
    // (NotificationsService.sendToUser already fails soft internally).
    void this.notificationsService.sendToUser(updated.requestedById, {
      title:
        updated.status === 'APPROVED'
          ? 'Stock request approved'
          : updated.status === 'FULFILLED'
            ? 'Stock request fulfilled'
            : 'Stock request rejected',
      body: `${updated.product.name} (${updated.quantity} ${updated.unit}) — ${updated.branch.name}${
        updated.resolution ? `: ${updated.resolution}` : ''
      }`,
      data: {
        type: 'stock_request_resolved',
        stockRequestId: updated.id,
        status: updated.status,
      },
    });

    return {
      id: updated.id,
      branchId: updated.branchId,
      branchName: updated.branch.name,
      requestedById: updated.requestedById,
      requestedByName: `${updated.requestedBy.firstName} ${updated.requestedBy.lastName}`,
      productId: updated.productId,
      productName: updated.product.name,
      productSku: updated.product.sku,
      quantity: Number(updated.quantity),
      unit: updated.unit,
      reason: updated.reason,
      priority: updated.priority,
      status: updated.status,
      images: updated.images,
      resolvedById: updated.resolvedById,
      resolvedByName: `${updated.resolvedBy.firstName} ${updated.resolvedBy.lastName}`,
      resolvedAt: updated.resolvedAt,
      resolution: updated.resolution,
      createdAt: updated.createdAt,
      updatedAt: updated.updatedAt,
    };
  }

  /**
   * Cancel a stock request
   */
  async cancelStockRequest(id: string, userId: string, tenantId: string) {
    const request = await this.prisma.stockRequest.findFirst({
      where: {
        id,
        requestedById: userId,
        branch: { tenantId },
        status: 'PENDING',
      },
    });

    if (!request) {
      throw new Error('Stock request not found or cannot be cancelled');
    }

    const updated = await this.prisma.stockRequest.update({
      where: { id },
      data: {
        status: 'CANCELLED',
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        product: { select: { name: true, sku: true } },
      },
    });

    return {
      id: updated.id,
      status: updated.status,
      cancelledAt: updated.updatedAt,
    };
  }

  /**
   * Get stock request statistics
   */
  async getStockRequestStats(tenantId: string, branchId?: string) {
    const where: any = {
      branch: { tenantId },
    };

    if (branchId) where.branchId = branchId;

    const [pending, approved, rejected, fulfilled, cancelled, urgent] = await Promise.all([
      this.prisma.stockRequest.count({ where: { ...where, status: 'PENDING' } }),
      this.prisma.stockRequest.count({ where: { ...where, status: 'APPROVED' } }),
      this.prisma.stockRequest.count({ where: { ...where, status: 'REJECTED' } }),
      this.prisma.stockRequest.count({ where: { ...where, status: 'FULFILLED' } }),
      this.prisma.stockRequest.count({ where: { ...where, status: 'CANCELLED' } }),
      this.prisma.stockRequest.count({ where: { ...where, priority: 'urgent', status: 'PENDING' } }),
    ]);

    return {
      pending,
      approved,
      rejected,
      fulfilled,
      cancelled,
      urgent,
      total: pending + approved + rejected + fulfilled + cancelled,
    };
  }
}
