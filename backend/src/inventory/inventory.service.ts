import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
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
import { StockMovementType } from '@prisma/client';

@Injectable()
export class InventoryService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
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

    return this.prisma.$transaction(async (tx) => {
      const movements: any[] = [];

      for (const item of dto.items) {
        const stock = await tx.stock.findUnique({
          where: {
            branchId_productId: {
              branchId: dto.branchId,
              productId: item.productId,
            },
          },
        });

        const previousQty = stock ? Number(stock.quantity) : 0;
        const newQty = item.quantity;
        const quantityChange = newQty - previousQty;

        // Update or create stock
        await tx.stock.upsert({
          where: {
            branchId_productId: {
              branchId: dto.branchId,
              productId: item.productId,
            },
          },
          create: {
            branchId: dto.branchId,
            productId: item.productId,
            quantity: newQty,
          },
          update: {
            quantity: newQty,
          },
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
      }

      return { success: true, movementCount: movements.length };
    });
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
      where.createdAt = {};
      if (startDate) where.createdAt.gte = new Date(startDate);
      if (endDate) where.createdAt.lte = new Date(endDate);
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

  async createTransfer(userId: string, tenantId: string, dto: CreateTransferDto) {
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
    const transfer = await this.prisma.stockTransfer.create({
      data: {
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
      include: {
        items: {
          include: {
            transfer: false,
          },
        },
      },
    });

    return this.getTransfer(transfer.id, tenantId);
  }

  async sendTransfer(transferId: string, userId: string, tenantId: string) {
    const transfer = await this.getTransferInternal(transferId, tenantId);

    if (transfer.status !== 'pending') {
      throw new BadRequestException('Transfer is not in pending status');
    }

    return this.prisma.$transaction(async (tx) => {
      // Deduct stock from source branch
      for (const item of transfer.items) {
        const stock = await tx.stock.findUnique({
          where: {
            branchId_productId: {
              branchId: transfer.fromBranchId,
              productId: item.productId,
            },
          },
        });

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
            branchId: transfer.fromBranchId,
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
    });
  }

  async receiveTransfer(
    transferId: string,
    userId: string,
    tenantId: string,
    dto: ReceiveTransferDto,
  ) {
    const transfer = await this.getTransferInternal(transferId, tenantId);

    if (transfer.status !== 'in_transit') {
      throw new BadRequestException('Transfer is not in transit');
    }

    return this.prisma.$transaction(async (tx) => {
      for (const receivedItem of dto.receivedItems) {
        const item = transfer.items.find((i) => i.productId === receivedItem.productId);
        if (!item) continue;

        // Add stock to destination branch
        const stock = await tx.stock.findUnique({
          where: {
            branchId_productId: {
              branchId: transfer.toBranchId,
              productId: receivedItem.productId,
            },
          },
        });

        const previousQty = stock ? Number(stock.quantity) : 0;
        const newQty = previousQty + receivedItem.quantity;

        await tx.stock.upsert({
          where: {
            branchId_productId: {
              branchId: transfer.toBranchId,
              productId: receivedItem.productId,
            },
          },
          create: {
            branchId: transfer.toBranchId,
            productId: receivedItem.productId,
            quantity: receivedItem.quantity,
          },
          update: {
            quantity: { increment: receivedItem.quantity },
          },
        });

        await tx.stockMovement.create({
          data: {
            branchId: transfer.toBranchId,
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
          notes: dto.notes ? `${transfer.notes || ''}\nReceived: ${dto.notes}` : transfer.notes,
        },
      });
    });
  }

  async getTransfer(transferId: string, tenantId: string) {
    const transfer = await this.getTransferInternal(transferId, tenantId);

    return {
      id: transfer.id,
      fromBranchId: transfer.fromBranchId,
      fromBranchName: (transfer as any).fromBranch?.name,
      toBranchId: transfer.toBranchId,
      toBranchName: (transfer as any).toBranch?.name,
      status: transfer.status,
      notes: transfer.notes,
      items: transfer.items.map((i: any) => ({
        productId: i.productId,
        productName: i.product?.name,
        requestedQty: Number(i.requestedQty),
        sentQty: i.sentQty ? Number(i.sentQty) : undefined,
        receivedQty: i.receivedQty ? Number(i.receivedQty) : undefined,
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
    const where: any = {};

    if (branchId) {
      where.OR = [{ fromBranchId: branchId }, { toBranchId: branchId }];
    }

    if (status) {
      where.status = status;
    }

    // Filter by tenant through branches
    const tenantBranches = await this.prisma.branch.findMany({
      where: { tenantId },
      select: { id: true },
    });
    const branchIds = tenantBranches.map((b) => b.id);

    where.fromBranchId = { in: branchIds };

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

    return {
      items: transfers,
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

    // Verify tenant access
    const branch = await this.prisma.branch.findFirst({
      where: { id: transfer.fromBranchId, tenantId },
    });

    if (!branch) {
      throw new ForbiddenException('Access denied');
    }

    return transfer;
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
      this.prisma.product.findFirst({ where: { id: dto.productId, tenantId } }),
    ]);

    if (!branch) throw new NotFoundException('Branch not found');
    if (!product) throw new NotFoundException('Product not found');

    return this.prisma.$transaction(async (tx) => {
      // Get or create stock record
      let stock = await tx.stock.findUnique({
        where: {
          branchId_productId: {
            branchId: dto.branchId,
            productId: dto.productId,
          },
        },
      });

      if (!stock) {
        stock = await tx.stock.create({
          data: {
            branchId: dto.branchId,
            productId: dto.productId,
            quantity: 0,
          },
        });
      }

      const createdBatches = [];
      let totalReceived = 0;

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

        const expiryDate = batch.expiryDate ? new Date(batch.expiryDate) : null;
        const isExpired = expiryDate && expiryDate < new Date();

        // Combine notes with conversion info
        const finalNotes = conversionNote
          ? batch.notes
            ? `${conversionNote}. ${batch.notes}`
            : conversionNote
          : batch.notes;

        const createdBatch = await tx.stockBatch.create({
          data: {
            stockId: stock.id,
            batchNumber: batch.batchNumber,
            quantity: baseQuantity,
            expiryDate,
            manufactureDate: batch.manufactureDate ? new Date(batch.manufactureDate) : null,
            costPrice: batch.costPrice,
            supplierRef: batch.supplierRef,
            notes: finalNotes,
            isBlocked: isExpired, // Auto-block expired batches
          },
        });

        createdBatches.push(createdBatch);
        totalReceived += baseQuantity;

        // Record stock movement for each batch
        await tx.stockMovement.create({
          data: {
            branchId: dto.branchId,
            productId: dto.productId,
            batchId: createdBatch.id,
            type: StockMovementType.BATCH_RECEIVE,
            quantity: baseQuantity,
            previousQty: Number(stock.quantity),
            newQty: Number(stock.quantity) + baseQuantity,
            batchNumber: batch.batchNumber,
            expiryDate,
            reference: dto.reference,
            notes: finalNotes,
            createdById: userId,
          },
        });
      }

      // Update total stock quantity
      await tx.stock.update({
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
        batches: createdBatches,
      };
    });
  }

  /**
   * Get conversion factor for a unit based on product configuration
   */
  private getConversionFactor(product: any, unit: string): number | null {
    const unitLower = unit.toLowerCase();
    const baseUnit = product.unit.toLowerCase();

    // If it's the base unit, no conversion needed
    if (unitLower === baseUnit) return 1;

    // Check secondary unit
    if (product.secondaryUnit && unitLower === product.secondaryUnit.toLowerCase()) {
      return Number(product.secondaryUnitQty) || null;
    }

    // Check tertiary unit
    if (product.tertiaryUnit && unitLower === product.tertiaryUnit.toLowerCase()) {
      return Number(product.tertiaryUnitQty) || null;
    }

    // No matching unit found
    return null;
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
      const previousQty = Number(batch.quantity);
      const updateData: any = {};

      if (dto.quantity !== undefined) {
        updateData.quantity = dto.quantity;
        const qtyChange = dto.quantity - previousQty;

        // Update total stock
        await tx.stock.update({
          where: { id: batch.stockId },
          data: { quantity: { increment: qtyChange } },
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
            newQty: dto.quantity,
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

    // Calculate summary
    const allBatches = await this.prisma.stockBatch.findMany({
      where: { stock: { branchId } },
      include: { stock: true },
    });

    const days30 = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    const days60 = new Date(now.getTime() + 60 * 24 * 60 * 60 * 1000);
    const days90 = new Date(now.getTime() + 90 * 24 * 60 * 60 * 1000);

    const summary = {
      expiredCount: 0,
      expiredValue: 0,
      expiring30Days: 0,
      expiring30DaysValue: 0,
      expiring60Days: 0,
      expiring60DaysValue: 0,
      expiring90Days: 0,
      expiring90DaysValue: 0,
    };

    for (const batch of allBatches) {
      const qty = Number(batch.quantity);
      const value = batch.costPrice ? qty * Number(batch.costPrice) : 0;

      if (batch.expiryDate) {
        if (batch.expiryDate < now) {
          summary.expiredCount++;
          summary.expiredValue += value;
        } else if (batch.expiryDate <= days30) {
          summary.expiring30Days++;
          summary.expiring30DaysValue += value;
        } else if (batch.expiryDate <= days60) {
          summary.expiring60Days++;
          summary.expiring60DaysValue += value;
        } else if (batch.expiryDate <= days90) {
          summary.expiring90Days++;
          summary.expiring90DaysValue += value;
        }
      }
    }

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
