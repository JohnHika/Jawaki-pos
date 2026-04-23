import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import {
  CreateSaleDto,
  CreateRefundDto,
  SalesQueryDto,
} from './dto/sales.dto';
import { SaleStatus, PaymentMethod, StockMovementType } from '@prisma/client';

@Injectable()
export class SalesService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
  ) {}

  async createSale(userId: string, tenantId: string, dto: CreateSaleDto) {
    // Validate branch belongs to tenant
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    // Check for duplicate offline ID
    if (dto.offlineId) {
      const existing = await this.prisma.sale.findUnique({
        where: { offlineId: dto.offlineId },
      });
      if (existing) {
        // Return existing sale (idempotent)
        return this.getSale(existing.id, tenantId);
      }
    }

    // Get products with branch prices
    const productIds = dto.items.map((i) => i.productId);
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds }, tenantId },
      include: {
        priceOverrides: {
          where: { branchId: dto.branchId, isActive: true },
        },
        stock: {
          where: { branchId: dto.branchId },
        },
      },
    });

    if (products.length !== productIds.length) {
      throw new NotFoundException('One or more products not found');
    }

    // Validate stock and calculate totals
    let subtotal = 0;
    let totalTax = 0;
    const saleItems: any[] = [];
    const stockUpdates: any[] = [];
    const batchAllocations: Map<string, any[]> = new Map(); // productId -> batch allocations

    for (const item of dto.items) {
      const product = products.find((p) => p.id === item.productId);
      if (!product) continue;

      // Check stock if tracking inventory
      if (product.trackInventory) {
        const currentStock = product.stock[0]?.quantity || 0;
        if (Number(currentStock) < item.quantity) {
          throw new BadRequestException(
            `Insufficient stock for ${product.name}. Available: ${currentStock}`,
          );
        }

        // Get batch allocations using FEFO logic
        const stockWithBatches = await this.prisma.stock.findUnique({
          where: {
            branchId_productId: {
              branchId: dto.branchId,
              productId: product.id,
            },
          },
          include: {
            batches: {
              where: {
                isBlocked: false,
              },
              orderBy: { expiryDate: 'asc' }, // FEFO: First expiry first
            },
          },
        });

        if (stockWithBatches && stockWithBatches.batches.length > 0) {
          // Check for expired batches
          const now = new Date();
          const hasExpiredBatches = stockWithBatches.batches.some(
            (b) => b.expiryDate && b.expiryDate < now && Number(b.quantity) > 0,
          );

          if (hasExpiredBatches) {
            throw new BadRequestException(
              `Cannot sell ${product.name}: Product has expired batches. Please check inventory.`,
            );
          }

          // Allocate batches using FEFO
          const allocations = [];
          let remainingQty = item.quantity;

          for (const batch of stockWithBatches.batches) {
            if (remainingQty <= 0) break;

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
          }

          if (remainingQty > 0) {
            throw new BadRequestException(
              `Insufficient non-expired stock for ${product.name}. Requested: ${item.quantity}, Available: ${item.quantity - remainingQty}`,
            );
          }

          batchAllocations.set(product.id, allocations);
        }
      }

      // Determine price
      let unitPrice = item.unitPrice;
      if (unitPrice === undefined) {
        if (product.priceOverrides[0]) {
          unitPrice = Number(product.priceOverrides[0].price);
        } else {
          unitPrice = Number(product.basePrice);
        }
      }

      const lineDiscount = item.discount || 0;
      const lineSubtotal = unitPrice * item.quantity - lineDiscount;
      const taxRate = Number(product.taxRate);
      const taxAmount = lineSubtotal * (taxRate / 100);
      const lineTotal = lineSubtotal + taxAmount;

      subtotal += lineSubtotal;
      totalTax += taxAmount;

      saleItems.push({
        productId: product.id,
        productName: product.name,
        quantity: item.quantity,
        unitPrice,
        discount: lineDiscount,
        taxRate,
        taxAmount,
        totalAmount: lineTotal,
      });

      if (product.trackInventory) {
        const currentStock = Number(product.stock[0]?.quantity || 0);
        stockUpdates.push({
          branchId: dto.branchId,
          productId: product.id,
          type: StockMovementType.SALE,
          quantity: -item.quantity,
          previousQty: currentStock,
          newQty: currentStock - item.quantity,
        });
      }
    }

    const discountAmount = dto.discountAmount || 0;
    const totalAmount = subtotal + totalTax - discountAmount;

    // For CREDIT payment, paidAmount is optional (defaults to 0, creating an outstanding balance)
    const paidAmount = dto.paymentMethod === PaymentMethod.CREDIT
      ? (dto.paidAmount ?? 0)
      : (dto.paidAmount ?? totalAmount);

    const changeAmount = paidAmount - totalAmount;

    if (paidAmount < totalAmount && dto.paymentMethod !== PaymentMethod.CREDIT) {
      throw new BadRequestException('Paid amount is less than total');
    }

    // For credit sales, store the outstanding balance in metadata
    const outstandingBalance = dto.paymentMethod === PaymentMethod.CREDIT
      ? totalAmount - paidAmount
      : 0;

    // Generate receipt number
    const receiptNumber = await this.generateReceiptNumber(dto.branchId);

    // Create sale with transaction
    const sale = await this.prisma.$transaction(async (tx) => {
      // Create sale
      const newSale = await tx.sale.create({
        data: {
          branchId: dto.branchId,
          deviceId: dto.deviceId,
          userId,
          receiptNumber,
          customerId: dto.customerId,
          status: SaleStatus.COMPLETED,
          subtotal,
          taxAmount: totalTax,
          discountAmount,
          totalAmount,
          paidAmount: paidAmount,
          changeAmount: Math.max(0, changeAmount),
          paymentMethod: dto.paymentMethod,
          notes: dto.notes,
          offlineId: dto.offlineId,
          metadata: outstandingBalance > 0
            ? { outstandingBalance, dueDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString() }
            : {},
          items: {
            create: saleItems,
          },
        },
        include: {
          items: true,
          branch: { select: { name: true } },
          user: { select: { firstName: true, lastName: true } },
          customer: { select: { name: true } },
        },
      });

      // Update stock
      for (const update of stockUpdates) {
        await tx.stock.upsert({
          where: {
            branchId_productId: {
              branchId: update.branchId,
              productId: update.productId,
            },
          },
          create: {
            branchId: update.branchId,
            productId: update.productId,
            quantity: update.newQty,
          },
          update: {
            quantity: { decrement: Math.abs(update.quantity) },
          },
        });

        // Record stock movement
        await tx.stockMovement.create({
          data: {
            branchId: update.branchId,
            productId: update.productId,
            type: update.type,
            quantity: update.quantity,
            previousQty: update.previousQty,
            newQty: update.newQty,
            reference: newSale.id,
            createdById: userId,
          },
        });

        // Update batches and create batch sale item records
        const allocations = batchAllocations.get(update.productId);
        if (allocations && allocations.length > 0) {
          // Find the sale item for this product
          const saleItem = newSale.items.find((si) => si.productId === update.productId);

          for (const allocation of allocations) {
            // Deduct from batch
            await tx.stockBatch.update({
              where: { id: allocation.batchId },
              data: {
                quantity: { decrement: allocation.quantity },
              },
            });

            // Create sale item batch record for tracking
            if (saleItem) {
              await tx.saleItemBatch.create({
                data: {
                  saleItemId: saleItem.id,
                  stockBatchId: allocation.batchId,
                  quantity: allocation.quantity,
                  batchNumber: allocation.batchNumber,
                  expiryDate: allocation.expiryDate,
                },
              });
            }

            // Record stock movement for batch
            await tx.stockMovement.create({
              data: {
                branchId: update.branchId,
                productId: update.productId,
                batchId: allocation.batchId,
                type: StockMovementType.SALE,
                quantity: -allocation.quantity,
                previousQty: update.previousQty,
                newQty: update.newQty,
                batchNumber: allocation.batchNumber,
                expiryDate: allocation.expiryDate,
                reference: newSale.id,
                notes: `Sale from batch ${allocation.batchNumber}`,
                createdById: userId,
              },
            });
          }
        }
      }

      return newSale;
    });

    return this.formatSale(sale);
  }

  async getSales(tenantId: string, query: SalesQueryDto) {
    const { branchId, userId, status, paymentMethod, startDate, endDate, page = 1, limit = 50 } = query;
    const skip = (page - 1) * limit;

    const where: any = {
      branch: { tenantId },
    };

    if (branchId) where.branchId = branchId;
    if (userId) where.userId = userId;
    if (status) where.status = status;
    if (paymentMethod) where.paymentMethod = paymentMethod;

    if (startDate || endDate) {
      where.createdAt = {};
      if (startDate) where.createdAt.gte = new Date(startDate);
      if (endDate) where.createdAt.lte = new Date(endDate);
    }

    const [sales, total] = await Promise.all([
      this.prisma.sale.findMany({
        where,
        include: {
          branch: { select: { name: true } },
          user: { select: { firstName: true, lastName: true } },
          customer: { select: { name: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.sale.count({ where }),
    ]);

    return {
      items: sales.map((s) => this.formatSale(s)),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async getSale(saleId: string, tenantId: string) {
    const sale = await this.prisma.sale.findFirst({
      where: {
        id: saleId,
        branch: { tenantId },
      },
      include: {
        items: {
          include: {
            product: { select: { sku: true } },
          },
        },
        branch: { select: { name: true, code: true, address: true, phone: true } },
        user: { select: { firstName: true, lastName: true } },
        customer: { select: { name: true, phone: true } },
        payments: true,
        refunds: {
          include: { items: true },
        },
      },
    });

    if (!sale) {
      throw new NotFoundException('Sale not found');
    }

    return this.formatSale(sale, true);
  }

  async getReceipt(receiptNumber: string, tenantId: string) {
    const sale = await this.prisma.sale.findFirst({
      where: {
        receiptNumber,
        branch: { tenantId },
      },
      include: {
        items: true,
        branch: { select: { name: true, code: true, address: true, phone: true } },
        user: { select: { firstName: true, lastName: true } },
        customer: { select: { name: true, phone: true } },
      },
    });

    if (!sale) {
      throw new NotFoundException('Receipt not found');
    }

    return this.formatSale(sale, true);
  }

  async voidSale(saleId: string, userId: string, tenantId: string, reason: string) {
    const sale = await this.prisma.sale.findFirst({
      where: {
        id: saleId,
        branch: { tenantId },
      },
      include: { items: true },
    });

    if (!sale) {
      throw new NotFoundException('Sale not found');
    }

    if (sale.status !== SaleStatus.COMPLETED) {
      throw new BadRequestException('Only completed sales can be voided');
    }

    // Void sale and restore stock
    return this.prisma.$transaction(async (tx) => {
      const voidedSale = await tx.sale.update({
        where: { id: saleId },
        data: {
          status: SaleStatus.VOIDED,
          notes: `${sale.notes || ''}\nVOIDED: ${reason}`,
          metadata: {
            ...((sale.metadata as object) || {}),
            voidedBy: userId,
            voidedAt: new Date().toISOString(),
            voidReason: reason,
          },
        },
      });

      // Restore stock
      for (const item of sale.items) {
        const stock = await tx.stock.findUnique({
          where: {
            branchId_productId: {
              branchId: sale.branchId,
              productId: item.productId,
            },
          },
        });

        if (stock) {
          const previousQty = Number(stock.quantity);
          const newQty = previousQty + Number(item.quantity);

          await tx.stock.update({
            where: { id: stock.id },
            data: { quantity: newQty },
          });

          await tx.stockMovement.create({
            data: {
              branchId: sale.branchId,
              productId: item.productId,
              type: StockMovementType.RETURN,
              quantity: Number(item.quantity),
              previousQty,
              newQty,
              reference: saleId,
              notes: `Void: ${reason}`,
              createdById: userId,
            },
          });
        }
      }

      return voidedSale;
    });
  }

  async createRefund(userId: string, tenantId: string, dto: CreateRefundDto) {
    const sale = await this.prisma.sale.findFirst({
      where: {
        id: dto.saleId,
        branch: { tenantId },
      },
      include: { items: true, refunds: { include: { items: true } } },
    });

    if (!sale) {
      throw new NotFoundException('Sale not found');
    }

    if (sale.status === SaleStatus.VOIDED) {
      throw new BadRequestException('Cannot refund a voided sale');
    }

    // Validate refund quantities
    let refundAmount = 0;
    const refundItems: any[] = [];

    for (const refundItem of dto.items) {
      const saleItem = sale.items.find((i) => i.id === refundItem.saleItemId);
      if (!saleItem) {
        throw new NotFoundException(`Sale item ${refundItem.saleItemId} not found`);
      }

      // Check already refunded quantity
      const alreadyRefunded = sale.refunds
        .flatMap((r) => r.items)
        .filter((ri) => ri.saleItemId === refundItem.saleItemId)
        .reduce((sum, ri) => sum + Number(ri.quantity), 0);

      const availableQty = Number(saleItem.quantity) - alreadyRefunded;
      if (refundItem.quantity > availableQty) {
        throw new BadRequestException(
          `Cannot refund ${refundItem.quantity} of ${saleItem.productName}. Available: ${availableQty}`,
        );
      }

      const itemRefundAmount = (Number(saleItem.totalAmount) / Number(saleItem.quantity)) * refundItem.quantity;
      refundAmount += itemRefundAmount;

      refundItems.push({
        saleItemId: refundItem.saleItemId,
        quantity: refundItem.quantity,
        amount: itemRefundAmount,
        restockItem: refundItem.restockItem ?? true,
        productId: saleItem.productId,
      });
    }

    // Create refund
    return this.prisma.$transaction(async (tx) => {
      const refund = await tx.refund.create({
        data: {
          saleId: dto.saleId,
          amount: refundAmount,
          reason: dto.reason,
          status: 'completed',
          processedById: userId,
          processedAt: new Date(),
          items: {
            create: refundItems.map((i) => ({
              saleItemId: i.saleItemId,
              quantity: i.quantity,
              amount: i.amount,
              restockItem: i.restockItem,
            })),
          },
        },
        include: { items: true },
      });

      // Restore stock for restocked items
      for (const item of refundItems) {
        if (item.restockItem) {
          const stock = await tx.stock.findUnique({
            where: {
              branchId_productId: {
                branchId: sale.branchId,
                productId: item.productId,
              },
            },
          });

          if (stock) {
            const previousQty = Number(stock.quantity);
            const newQty = previousQty + item.quantity;

            await tx.stock.update({
              where: { id: stock.id },
              data: { quantity: newQty },
            });

            await tx.stockMovement.create({
              data: {
                branchId: sale.branchId,
                productId: item.productId,
                type: StockMovementType.RETURN,
                quantity: item.quantity,
                previousQty,
                newQty,
                reference: refund.id,
                notes: `Refund: ${dto.reason}`,
                createdById: userId,
              },
            });
          }
        }
      }

      // Update sale status
      const totalRefunded = sale.refunds.reduce((sum, r) => sum + Number(r.amount), 0) + refundAmount;
      const newStatus = totalRefunded >= Number(sale.totalAmount)
        ? SaleStatus.REFUNDED
        : SaleStatus.PARTIAL_REFUND;

      await tx.sale.update({
        where: { id: dto.saleId },
        data: { status: newStatus },
      });

      return refund;
    });
  }

  async getDailySummary(branchId: string, date: string, tenantId: string) {
    const startOfDay = new Date(date);
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date(date);
    endOfDay.setHours(23, 59, 59, 999);

    const [sales, refunds] = await Promise.all([
      this.prisma.sale.findMany({
        where: {
          branchId,
          branch: { tenantId },
          createdAt: { gte: startOfDay, lte: endOfDay },
        },
      }),
      this.prisma.refund.findMany({
        where: {
          sale: {
            branchId,
            branch: { tenantId },
          },
          createdAt: { gte: startOfDay, lte: endOfDay },
        },
      }),
    ]);

    const completedSales = sales.filter((s) => s.status === SaleStatus.COMPLETED);
    const voidedSales = sales.filter((s) => s.status === SaleStatus.VOIDED);

    // Calculate credit sales and outstanding balances
    const creditSales = completedSales.filter((s) => s.paymentMethod === PaymentMethod.CREDIT);
    const totalOutstanding = creditSales.reduce((sum, s) => {
      const outstanding = (s.metadata as any)?.outstandingBalance ?? 0;
      return sum + Number(outstanding);
    }, 0);

    return {
      date,
      totalSales: completedSales.reduce((sum, s) => sum + Number(s.totalAmount), 0),
      totalTransactions: completedSales.length,
      totalTax: completedSales.reduce((sum, s) => sum + Number(s.taxAmount), 0),
      totalDiscount: completedSales.reduce((sum, s) => sum + Number(s.discountAmount), 0),
      cashSales: completedSales
        .filter((s) => s.paymentMethod === PaymentMethod.CASH)
        .reduce((sum, s) => sum + Number(s.totalAmount), 0),
      mpesaSales: completedSales
        .filter((s) => s.paymentMethod === PaymentMethod.MPESA)
        .reduce((sum, s) => sum + Number(s.totalAmount), 0),
      cardSales: completedSales
        .filter((s) => s.paymentMethod === PaymentMethod.PESAPAL)
        .reduce((sum, s) => sum + Number(s.totalAmount), 0),
      creditSales: creditSales.reduce((sum, s) => sum + Number(s.totalAmount), 0),
      outstandingBalance: totalOutstanding,
      voidedCount: voidedSales.length,
      refundedAmount: refunds.reduce((sum, r) => sum + Number(r.amount), 0),
    };
  }

  async getCreditSalesWithOutstandingBalance(
    tenantId: string,
    query: SalesQueryDto,
  ) {
    const { branchId, startDate, endDate, page = 1, limit = 50 } = query;
    const skip = (page - 1) * limit;

    const where: any = {
      branch: { tenantId },
      paymentMethod: PaymentMethod.CREDIT,
      status: SaleStatus.COMPLETED,
    };

    if (branchId) where.branchId = branchId;

    if (startDate || endDate) {
      where.createdAt = {};
      if (startDate) where.createdAt.gte = new Date(startDate);
      if (endDate) where.createdAt.lte = new Date(endDate);
    }

    // Filter for sales with outstanding balance
    const sales = await this.prisma.sale.findMany({
      where,
      include: {
        branch: { select: { name: true } },
        user: { select: { firstName: true, lastName: true } },
        customer: { select: { name: true, phone: true } },
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    });

    // Filter to only those with outstanding balance
    const salesWithOutstanding = sales.filter((s) => {
      const outstanding = (s.metadata as any)?.outstandingBalance ?? 0;
      return Number(outstanding) > 0;
    });

    const total = salesWithOutstanding.length;

    return {
      items: salesWithOutstanding.map((s) => ({
        ...this.formatSale(s, true),
        outstandingBalance: (s.metadata as any)?.outstandingBalance ?? 0,
        dueDate: (s.metadata as any)?.dueDate,
      })),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  // ==================== BULK SALES OPERATIONS ====================

  async bulkCreateSales(userId: string, tenantId: string, sales: any[]) {
    const results: any[] = [];
    for (const dto of sales) {
      const sale = await this.createSale(userId, tenantId, dto);
      results.push(sale);
    }
    return results;
  }

  async bulkVoidSales(userId: string, tenantId: string, ids: string[], reason: string) {
    const results: any[] = [];
    for (const saleId of ids) {
      const result = await this.voidSale(saleId, userId, tenantId, reason);
      results.push(result);
    }
    return results;
  }

  // ==================== HELPERS ====================

  private async generateReceiptNumber(branchId: string): Promise<string> {
    const branch = await this.prisma.branch.findUnique({
      where: { id: branchId },
      select: { code: true },
    });

    const today = new Date();
    const datePrefix = today.toISOString().slice(0, 10).replace(/-/g, '');
    const prefix = `${branch?.code || 'POS'}-${datePrefix}`;

    // Get count for today
    const key = `receipt:${prefix}`;
    let count = await this.redisService.get(key);
    
    if (!count) {
      // Count from database
      const startOfDay = new Date(today);
      startOfDay.setHours(0, 0, 0, 0);
      
      const existingCount = await this.prisma.sale.count({
        where: {
          branchId,
          createdAt: { gte: startOfDay },
        },
      });
      count = String(existingCount);
    }

    const newCount = parseInt(count, 10) + 1;
    await this.redisService.set(key, String(newCount), 86400); // TTL 24 hours

    return `${prefix}-${String(newCount).padStart(4, '0')}`;
  }

  private formatSale(sale: any, includeItems = false) {
    const result: any = {
      id: sale.id,
      receiptNumber: sale.receiptNumber,
      branchId: sale.branchId,
      branchName: sale.branch?.name,
      userId: sale.userId,
      userName: sale.user ? `${sale.user.firstName} ${sale.user.lastName}` : undefined,
      customerId: sale.customerId,
      customerName: sale.customer?.name,
      customerPhone: sale.customer?.phone,
      status: sale.status,
      subtotal: Number(sale.subtotal),
      taxAmount: Number(sale.taxAmount),
      discountAmount: Number(sale.discountAmount),
      totalAmount: Number(sale.totalAmount),
      paidAmount: Number(sale.paidAmount),
      changeAmount: Number(sale.changeAmount),
      paymentMethod: sale.paymentMethod,
      notes: sale.notes,
      createdAt: sale.createdAt,
    };

    if (includeItems && sale.items) {
      result.items = sale.items.map((item: any) => ({
        id: item.id,
        productId: item.productId,
        productName: item.productName,
        sku: item.product?.sku,
        quantity: Number(item.quantity),
        unitPrice: Number(item.unitPrice),
        discount: Number(item.discount),
        taxRate: Number(item.taxRate),
        taxAmount: Number(item.taxAmount),
        totalAmount: Number(item.totalAmount),
      }));
    }

    if (sale.branch) {
      result.branch = {
        name: sale.branch.name,
        code: sale.branch.code,
        address: sale.branch.address,
        phone: sale.branch.phone,
      };
    }

    if (sale.refunds) {
      result.refunds = sale.refunds;
    }

    return result;
  }
}
