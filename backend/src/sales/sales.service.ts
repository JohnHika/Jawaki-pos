import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
  Optional,
} from '@nestjs/common';
import { AccountabilityService } from '../accountability/accountability.service';
import { CouponsService, SaleCouponUse } from '../coupons/coupons.service';
import { spreadCouponDiscount } from '../coupons/coupons.rules';
import { severityForAmount } from '../accountability/accountability.rules';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { getDayBoundsInTimezone, todayInTimezone } from '../common/operating-hours';
import { CashFlowService } from '../cash-flow/cash-flow.service';
import { CashEntryType } from '../cash-flow/dto/cash-flow.dto';
import { FinanceService } from '../finance/finance.service';
import {
  CreateSaleDto,
  CreateRefundDto,
  ReconcileOfflineSalesDto,
  SalesQueryDto,
} from './dto/sales.dto';
import {
  PaymentMethod,
  PaymentStatus,
  Prisma,
  ReceivableStatus,
  SaleStatus,
  StockMovementType,
} from '@prisma/client';
import { lockStockForUpdate } from '../common/stock-lock';

@Injectable()
export class SalesService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
    private cashFlowService: CashFlowService,
    private financeService: FinanceService,
    // Optional so unit tests (and any caller that builds the service by hand)
    // keep working without the accountability layer.
    @Optional() private accountability?: AccountabilityService,
    @Optional() private coupons?: CouponsService,
  ) {}

  async createSale(
    userId: string,
    tenantId: string,
    dto: CreateSaleDto,
    options: {
      verifiedMerchantMpesa?: boolean;
      /** True only when replaying an already completed sale through sync. */
      offlineReconciliation?: boolean;
    } = {},
  ) {
    if (
      dto.paymentMethod === PaymentMethod.MANUAL ||
      dto.tenders?.some((tender) => tender.method === PaymentMethod.MANUAL)
    ) {
      throw new BadRequestException(
        'Manual payment recording is unavailable. Choose cash, verified M-Pesa, or debt.',
      );
    }

    // M-Pesa sales are created only after the merchant Paystack charge has
    // been verified. The generic sales and offline-sync endpoints must never
    // turn a payment prompt into a completed sale.
    if (
      dto.paymentMethod === PaymentMethod.MPESA &&
      !options.verifiedMerchantMpesa
    ) {
      throw new BadRequestException(
        'M-Pesa sales can only be recorded after payment is verified.',
      );
    }

    // Other electronic methods have no verified settlement path into this
    // endpoint. An arbitrary client reference cannot prove payment.
    if (
      dto.paymentMethod === PaymentMethod.PESAPAL ||
      dto.paymentMethod === PaymentMethod.TOURISTTAP
    ) {
      throw new BadRequestException(
        'Electronic sales can only be recorded after provider payment is verified.',
      );
    }
    if (
      dto.paymentMethod === PaymentMethod.SPLIT &&
      dto.tenders?.some((tender) =>
        tender.method !== PaymentMethod.CASH && tender.method !== PaymentMethod.CREDIT,
      )
    ) {
      throw new BadRequestException(
        'Split payments currently support cash and debt only. Use the verified M-Pesa checkout for electronic payments.',
      );
    }

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
        // Return existing sale (idempotent). The original create already
        // logged its cash-ledger entry inside its own transaction, so no
        // entry is appended here — re-appending on every retry would
        // double-count the same sale's cash in the till.
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

      // Fractional sales are a product-level choice (e.g. 0.5 kg of rice).
      // Enforce it on the server as well as the POS so API clients cannot
      // bypass a merchant's whole-unit inventory setting.
      if (!product.allowFractions && !Number.isInteger(item.quantity)) {
        throw new BadRequestException(
          `${product.name} is sold in whole units. Update its product settings before selling a fraction.`,
        );
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
        unit: item.unit ?? null,
        quantityPerUnit: item.quantityPerUnit ?? null,
      });

    }

    const discountAmount = dto.discountAmount || 0;
    const totalAmount = subtotal + totalTax - discountAmount;

    // SPLIT sales derive their payment amounts from the tender rows. CREDIT
    // tenders are obligations, not money received, so keep them out of
    // Sale.paidAmount while creating their receivable below.
    if (dto.paymentMethod === PaymentMethod.SPLIT) {
      const splitTenders = dto.tenders ?? [];
      const cashTenders = splitTenders.filter((tender) => tender.method === PaymentMethod.CASH);
      const debtTenders = splitTenders.filter((tender) => tender.method === PaymentMethod.CREDIT);
      if (
        splitTenders.length !== 2 ||
        cashTenders.length !== 1 ||
        debtTenders.length !== 1 ||
        splitTenders.some((tender) => !Number.isFinite(tender.amount) || tender.amount <= 0)
      ) {
        throw new BadRequestException(
          'A split needs one positive cash amount and one positive debt amount.',
        );
      }
      if (!dto.customerId) {
        throw new BadRequestException('Choose a customer before adding the debt portion.');
      }
    } else if (dto.tenders && dto.tenders.length > 0) {
      throw new BadRequestException('tenders is only valid when paymentMethod is SPLIT');
    }

    const tenderTotal = dto.tenders?.reduce((sum, t) => sum + t.amount, 0);
    if (
      dto.paymentMethod === PaymentMethod.SPLIT &&
      (!Number.isFinite(tenderTotal) ||
        tenderTotal! > Number.MAX_SAFE_INTEGER / 100 ||
        totalAmount > Number.MAX_SAFE_INTEGER / 100)
    ) {
      throw new BadRequestException('Split payment amounts exceed the supported limit.');
    }
    const splitCreditPortion = dto.paymentMethod === PaymentMethod.SPLIT
      ? (dto.tenders ?? [])
          .filter((tender) => tender.method === PaymentMethod.CREDIT)
          .reduce((sum, tender) => sum + tender.amount, 0)
      : 0;

    if (
      dto.paymentMethod === PaymentMethod.SPLIT &&
      Math.round(tenderTotal! * 100) !== Math.round(totalAmount * 100)
    ) {
      throw new BadRequestException(
        'The cash and debt portions must add up exactly to the sale total.',
      );
    }

    // For CREDIT payment, paidAmount is optional (defaults to 0, creating an outstanding balance)
    const paidAmount = dto.paymentMethod === PaymentMethod.SPLIT
      ? tenderTotal! - splitCreditPortion
      : dto.paymentMethod === PaymentMethod.CREDIT
        ? (dto.paidAmount ?? 0)
        : (dto.paidAmount ?? totalAmount);

    const changeAmount = dto.paymentMethod === PaymentMethod.SPLIT
      ? Math.round((tenderTotal! - totalAmount) * 100) / 100
      : Math.round((paidAmount - totalAmount) * 100) / 100;

    if (
      dto.paymentMethod === PaymentMethod.SPLIT
        ? Math.round(tenderTotal! * 100) < Math.round(totalAmount * 100)
        : Math.round(paidAmount * 100) < Math.round(totalAmount * 100) &&
          dto.paymentMethod !== PaymentMethod.CREDIT
    ) {
      throw new BadRequestException('Paid amount is less than total');
    }

    // A credit obligation is derived server-side from the receipt's payment
    // representation. Clients never provide a receivable balance. For SPLIT,
    // only the explicit CREDIT tender becomes debt; cash tenders are settled.
    const creditPortion = dto.paymentMethod === PaymentMethod.SPLIT
      ? splitCreditPortion
      : dto.paymentMethod === PaymentMethod.CREDIT
        ? Math.max(totalAmount - paidAmount, 0)
        : 0;

    // A coupon the shop issued is an approved discount, so it does not count
    // against the cashier's own discount limit. The phone has already taken
    // the money off at the counter, so a coupon that does not check out here
    // is flagged to the owner, never used to refuse a sale that has happened.
    let couponUse: SaleCouponUse | null = null;
    let couponProblem: string | null = null;
    const couponCode = dto.couponCode?.trim();
    if (couponCode && this.coupons) {
      const checked = await this.coupons.assessForSale({
        tenantId,
        code: couponCode,
        customerId: dto.customerId,
        lines: saleItems.map((line) => ({
          productId: line.productId,
          amount: Number(line.unitPrice) * Number(line.quantity) - Number(line.discount),
        })),
      });
      if (checked.verdict.ok) {
        const amount = Math.min(checked.verdict.discount, discountAmount);
        if (amount > 0 && checked.couponId) {
          couponUse = { couponId: checked.couponId, code: checked.code, amount, productIds: checked.productIds };
        }
      } else {
        couponProblem = checked.verdict.message;
        if (!options.offlineReconciliation && !options.verifiedMerchantMpesa) {
          throw new BadRequestException(checked.verdict.message);
        }
      }
    }

    // The coupon's money comes off the items it applies to, so the price guard
    // judges the price each item really sold at, not the sticker price.
    const couponShares = couponUse
      ? spreadCouponDiscount(
          saleItems.map((line) => ({
            productId: line.productId,
            amount: Number(line.unitPrice) * Number(line.quantity) - Number(line.discount),
          })),
          couponUse.productIds,
          couponUse.amount,
        )
      : null;

    // offlineId is also the idempotency key for ordinary online sales, so it
    // cannot prove that a sale was created while disconnected. Only the sync
    // pipeline marks completed offline sales for flag-and-record handling. A
    // verified provider charge is recorded even if policy changed after the
    // customer paid; any violation is still made auditable.
    const assessment = this.accountability
      ? await this.accountability.assessSale({
          userId,
          tenantId,
          branchId: dto.branchId,
          customerId: dto.customerId,
          overallDiscount: Math.max(discountAmount - (couponUse?.amount ?? 0), 0),
          creditAmount: creditPortion,
          enforce: !options.offlineReconciliation && !options.verifiedMerchantMpesa,
          lines: saleItems.map((line, index) => {
            const product = products.find((p) => p.id === line.productId);
            return {
              productId: line.productId,
              name: line.productName,
              quantity: Number(line.quantity),
              unitPrice: Number(line.unitPrice),
              discount: Number(line.discount),
              approvedDiscount: couponShares?.[index] ?? 0,
              costPrice: product?.costPrice != null ? Number(product.costPrice) : null,
              minPrice: product?.minPrice != null ? Number(product.minPrice) : null,
            };
          }),
        })
      : { violations: [], blocked: false };
    if (assessment.blocked) {
      this.accountability!.refuse(assessment.violations);
    }

    // Clients identify their device by its own uuid; Sale.deviceId is a foreign
    // key to the Device row id. Resolve it (within this company), and drop it
    // if unknown rather than failing the whole sale with a foreign-key error.
    let resolvedDeviceId: string | null = null;
    if (dto.deviceId) {
      const device = await this.prisma.device.findFirst({
        where: {
          branch: { tenantId },
          OR: [{ id: dto.deviceId }, { deviceUuid: dto.deviceId }],
        },
        select: { id: true },
      });
      resolvedDeviceId = device?.id ?? null;
    }

    // Generate receipt number
    const receiptNumber = await this.generateReceiptNumber(dto.branchId);

    let couponOverLimit = false;

    // Create sale with transaction
    const sale = await this.prisma.$transaction(async (tx: Prisma.TransactionClient) => {
      // Stock validation and movement arithmetic must happen after the same
      // row locks used by receiving. Pre-transaction reads can become stale
      // while waiting behind another sale or receipt and can drive stock
      // negative or record incorrect previous/new balances.
      for (const item of [...dto.items].sort((a, b) =>
        a.productId.localeCompare(b.productId),
      )) {
        const product = products.find((candidate) => candidate.id === item.productId);
        if (!product?.trackInventory) continue;

        const stock = await lockStockForUpdate(
          tx,
          dto.branchId,
          product.id,
        );
        if (!stock) {
          throw new BadRequestException(
            `Insufficient stock for ${product.name}. Available: 0`,
          );
        }

        const currentStock = Number(stock.quantity);
        if (currentStock < item.quantity) {
          throw new BadRequestException(
            `Insufficient stock for ${product.name}. Available: ${currentStock}`,
          );
        }

        stockUpdates.push({
          branchId: dto.branchId,
          productId: product.id,
          type: StockMovementType.SALE,
          quantity: -item.quantity,
          previousQty: currentStock,
          newQty: currentStock - item.quantity,
        });

        await tx.$queryRaw`
          SELECT id
          FROM stock_batches
          WHERE "stockId" = ${stock.id}
          FOR UPDATE
        `;
        const batches = await tx.stockBatch.findMany({
          where: { stockId: stock.id, isBlocked: false },
          orderBy: [{ expiryDate: 'asc' }, { id: 'asc' }],
        });
        if (batches.length === 0) continue;

        const now = new Date();
        if (
          batches.some(
            (batch) =>
              batch.expiryDate &&
              batch.expiryDate < now &&
              Number(batch.quantity) > 0,
          )
        ) {
          throw new BadRequestException(
            `Cannot sell ${product.name}: Product has expired batches. Please check inventory.`,
          );
        }

        const allocations = [];
        let remainingQty = item.quantity;
        for (const batch of batches) {
          if (remainingQty <= 0) break;
          const availableQty =
            Number(batch.quantity) - Number(batch.reservedQty);
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

      // Create sale
      const newSale = await tx.sale.create({
        data: {
          branchId: dto.branchId,
          deviceId: resolvedDeviceId,
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
          metadata: couponUse
            ? { coupon: { code: couponUse.code, amount: couponUse.amount } }
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

      if (couponUse && this.coupons) {
        const redeemed = await this.coupons.redeemInTx(tx, {
          tenantId,
          branchId: dto.branchId,
          saleId: newSale.id,
          userId,
          customerId: dto.customerId,
          use: couponUse,
        });
        couponOverLimit = redeemed.overLimit;
      }

      // Retail credit is a first-class obligation linked to this immutable
      // receipt, written on this same transaction as stock and sale rows.
      if (creditPortion > 0) {
        await this.financeService.createRetailReceivableForSale(tx, {
          tenantId,
          branchId: dto.branchId,
          saleId: newSale.id,
          customerId: dto.customerId,
          originalAmount: creditPortion,
          dueDate: dto.creditDueDate
            ? new Date(dto.creditDueDate)
            : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
          offlineId: dto.offlineId,
          createdById: userId,
        });
      }

      // Split sales get one Payment row per tender so the breakdown
      // (how much was cash vs M-Pesa vs card) survives past the top-level
      // Sale.paymentMethod=SPLIT, which on its own can't represent that.
      let tenderPayments: Awaited<ReturnType<typeof tx.payment.findMany>> = [];
      if (dto.paymentMethod === PaymentMethod.SPLIT && dto.tenders) {
        await tx.payment.createMany({
          data: dto.tenders.map((tender) => ({
            saleId: newSale.id,
            method: tender.method,
            amount: tender.amount,
            status: tender.method === PaymentMethod.CREDIT
              ? PaymentStatus.PENDING
              : PaymentStatus.COMPLETED,
            transactionId: tender.reference,
            paidAt: new Date(),
          })),
        });
        tenderPayments = await tx.payment.findMany({ where: { saleId: newSale.id } });
      }

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

      // Cash-flow ledger only ever tracks physical cash movements — sales
      // paid by M-Pesa/card/credit don't put cash in the till, so they're
      // excluded here. ALL_REVENUE mode reads straight from Sale.totalAmount
      // instead of this ledger for that reason (see
      // CashFlowService.getAvailableCash). Written on the same tx as the
      // sale itself: a crash can no longer commit the sale while losing its
      // cash entry (or vice versa).
      if (dto.paymentMethod === PaymentMethod.CASH && Number(paidAmount) > 0) {
        await this.cashFlowService.recordEntry({
          tx,
          branchId: dto.branchId,
          type: CashEntryType.SALE_CASH_IN,
          amount: Number(paidAmount) - Math.max(0, changeAmount),
          referenceType: 'sale',
          referenceId: newSale.id,
          createdById: userId,
        });
      } else if (dto.paymentMethod === PaymentMethod.SPLIT && dto.tenders) {
        // Only the cash tender(s) put physical money in the till. Change is
        // handed back in cash regardless of which tender it's notionally
        // "from," so it comes out of the cash portion specifically — not
        // proportionally across all tenders, which would misstate how much
        // cash actually changed hands.
        const cashTendered = dto.tenders
          .filter((t) => t.method === PaymentMethod.CASH)
          .reduce((sum, t) => sum + t.amount, 0);
        const netCashIn = cashTendered - Math.max(0, changeAmount);
        if (netCashIn > 0) {
          await this.cashFlowService.recordEntry({
            tx,
            branchId: dto.branchId,
            type: CashEntryType.SALE_CASH_IN,
            amount: netCashIn,
            referenceType: 'sale',
            referenceId: newSale.id,
            createdById: userId,
          });
        }
      }

      return { ...newSale, payments: tenderPayments };
    });

    if (this.accountability && assessment.violations.length > 0) {
      await this.accountability.flagSale(
        {
          tenantId,
          branchId: dto.branchId,
          userId,
          saleId: sale.id,
          receiptNumber: sale.receiptNumber,
        },
        assessment.violations,
      );
    }

    if (this.coupons && couponCode && (couponProblem || couponOverLimit)) {
      await this.coupons.flagAfterSale({
        tenantId,
        branchId: dto.branchId,
        userId,
        saleId: sale.id,
        receiptNumber: sale.receiptNumber,
        code: couponCode.toUpperCase(),
        problem: couponProblem,
        overLimit: couponOverLimit,
        claimedDiscount: discountAmount,
      });
    }

    return this.formatSale(sale);
  }

  /**
   * Turns the `startDate`/`endDate` query values into a `createdAt` filter.
   *
   * Clients send plain calendar dates ("2026-10-13"). `new Date("2026-10-13")` is
   * midnight UTC, so using it as an inclusive upper bound dropped the whole last
   * day: a one-day range ("Today") matched nothing and "This Week" omitted
   * today's sales. Date-only values are therefore expanded to the start/end of
   * that day in the branch's timezone; full timestamps are used as given.
   */
  private async resolveCreatedAtRange(
    tenantId: string,
    branchId: string | undefined,
    startDate?: string,
    endDate?: string,
  ): Promise<{ gte?: Date; lte?: Date } | undefined> {
    if (!startDate && !endDate) return undefined;
    const dateOnly = /^\d{4}-\d{2}-\d{2}$/;

    let timezone = 'Africa/Nairobi';
    if (branchId && ((startDate && dateOnly.test(startDate)) || (endDate && dateOnly.test(endDate)))) {
      const branch = await this.prisma.branch.findFirst({
        where: { id: branchId, tenantId },
        select: { timezone: true },
      });
      if (branch?.timezone) timezone = branch.timezone;
    }

    const range: { gte?: Date; lte?: Date } = {};
    if (startDate) {
      range.gte = dateOnly.test(startDate)
        ? getDayBoundsInTimezone(startDate, timezone).start
        : new Date(startDate);
    }
    if (endDate) {
      range.lte = dateOnly.test(endDate)
        ? getDayBoundsInTimezone(endDate, timezone).end
        : new Date(endDate);
    }
    return range;
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

    const createdAt = await this.resolveCreatedAtRange(tenantId, branchId, startDate, endDate);
    if (createdAt) where.createdAt = createdAt;

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

  async reconcileOfflineSales(tenantId: string, dto: ReconcileOfflineSalesDto) {
    if (dto.offlineIds.length === 0) return { offlineIds: [] };

    const sales = await this.prisma.sale.findMany({
      where: {
        branchId: dto.branchId,
        branch: { tenantId },
        offlineId: { in: dto.offlineIds },
      },
      select: { offlineId: true },
    });

    return {
      offlineIds: sales
        .map((sale) => sale.offlineId)
        .filter((offlineId): offlineId is string => offlineId !== null),
    };
  }

  async getSale(saleId: string, tenantId: string, userId?: string) {
    const sale = await this.prisma.sale.findFirst({
      where: {
        id: saleId,
        branch: { tenantId },
        ...(userId ? { userId } : {}),
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

  async getReceipt(receiptNumber: string, tenantId: string, userId?: string) {
    const sale = await this.prisma.sale.findFirst({
      where: {
        receiptNumber,
        branch: { tenantId },
        ...(userId ? { userId } : {}),
      },
      include: {
        items: true,
        branch: { select: { name: true, code: true, address: true, phone: true } },
        user: { select: { firstName: true, lastName: true } },
        customer: { select: { name: true, phone: true } },
        payments: true,
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

    // A repeated request is a safe retry (for example after the app lost the
    // original response). Never restore stock or reverse cash twice.
    if (sale.status === SaleStatus.VOIDED) return sale;

    if (sale.status !== SaleStatus.COMPLETED) {
      throw new BadRequestException('Only completed sales can be voided');
    }

    // Void sale and restore stock
    const outcome = await this.prisma.$transaction(async (tx: Prisma.TransactionClient) => {
      await tx.$queryRaw`
        SELECT id FROM sales WHERE id = ${saleId} FOR UPDATE
      `;
      const lockedSale = await tx.sale.findUnique({
        where: { id: saleId },
        include: { items: true, payments: true },
      });
      if (!lockedSale) {
        throw new NotFoundException('Sale not found');
      }
      if (lockedSale.status === SaleStatus.VOIDED) {
        return { sale: lockedSale, didVoid: false };
      }
      if (lockedSale.status !== SaleStatus.COMPLETED) {
        throw new BadRequestException('Only completed sales can be voided');
      }

      // A credit sale's receivable is part of the sale's financial record.
      // Close an untouched receivable with the void. If any amount has already
      // been collected (or an M-Pesa request is pending), stop and require that
      // money to be reconciled first instead of erasing a real customer debt.
      const receivableRows = await tx.$queryRaw<Array<{ id: string }>>`
        SELECT id FROM retail_receivables WHERE "saleId" = ${saleId} FOR UPDATE
      `;
      if (receivableRows.length > 0) {
        const receivableId = receivableRows[0].id;
        const lockKey = `merchant-receivable:${tenantId}:retail:${receivableId}`;
        await tx.$queryRaw`
          SELECT pg_advisory_xact_lock(hashtextextended(${lockKey}, 0))
        `;
        const receivable = await tx.retailReceivable.findUnique({
          where: { id: receivableId },
          include: { payments: { select: { id: true } } },
        });
        if (!receivable) throw new NotFoundException('Sale receivable not found');
        const hasCollectedAmount =
          receivable.payments.length > 0 ||
          receivable.status !== ReceivableStatus.OPEN ||
          !receivable.outstandingAmount.equals(receivable.originalAmount);
        const pendingCharge = await tx.merchantCharge.count({
          where: {
            tenantId,
            purpose: 'RECEIVABLE',
            receivableType: 'retail',
            receivableId,
            status: { in: ['PENDING', 'SETTLING', 'NEEDS_REVIEW'] },
          },
        });
        if (hasCollectedAmount || pendingCharge > 0) {
          throw new ConflictException(
            pendingCharge > 0
              ? 'This sale has an M-Pesa debt payment in progress. Resolve it before voiding the sale.'
              : 'This sale has collected debt payments. Refund or reconcile them before voiding the sale.',
          );
        }
        await tx.retailReceivable.update({
          where: { id: receivableId },
          data: { status: ReceivableStatus.VOIDED, outstandingAmount: 0 },
        });
      }

      const voidedSale = await tx.sale.update({
        where: { id: saleId },
        data: {
          status: SaleStatus.VOIDED,
          notes: `${lockedSale.notes || ''}\nVOIDED: ${reason}`,
          metadata: {
            ...((lockedSale.metadata as object) || {}),
            voidedBy: userId,
            voidedAt: new Date().toISOString(),
            voidReason: reason,
          },
        },
      });

      // Restore stock
      for (const item of [...lockedSale.items].sort((a, b) =>
        a.productId.localeCompare(b.productId),
      )) {
        const stock = await lockStockForUpdate(
          tx,
          lockedSale.branchId,
          item.productId,
        );

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

      // Reverse the cash that was originally logged in, so a voided cash sale
      // doesn't keep inflating "available cash to restock." Same tx as the
      // status flip: a crash can't leave a voided sale with its cash still
      // counted in the till (or an un-voided sale with cash removed).
      const cashReceived =
        lockedSale.paymentMethod === PaymentMethod.CASH
          ? Number(lockedSale.paidAmount) - Number(lockedSale.changeAmount)
          : lockedSale.paymentMethod === PaymentMethod.SPLIT
            ? lockedSale.payments
                .filter((payment) => payment.method === PaymentMethod.CASH)
                .reduce((sum, payment) => sum + Number(payment.amount), 0) -
              Number(lockedSale.changeAmount)
            : 0;
      if (cashReceived > 0) {
        await this.cashFlowService.recordEntry({
          tx,
          branchId: sale.branchId,
          type: CashEntryType.SALE_CASH_IN,
          amount: -cashReceived,
          referenceType: 'sale',
          referenceId: sale.id,
          note: `Voided: ${reason}`,
          createdById: userId,
        });
      }

      return { sale: voidedSale, didVoid: true };
    });

    const voided = outcome.sale;
    if (!outcome.didVoid) return voided;
    await this.coupons?.releaseForSale(saleId);
    await this.recordVoid(sale, userId, tenantId, reason);

    return voided;
  }

  /**
   * Audit entry + owner alert for a void. A void is the classic way to pocket
   * cash (ring the sale, take the money, void it), so it is always recorded;
   * it is HIGH when it is large or happens after the day was already closed.
   */
  private async recordVoid(
    sale: { id: string; branchId: string; receiptNumber: string; totalAmount: unknown; createdAt: Date; paymentMethod: PaymentMethod },
    userId: string,
    tenantId: string,
    reason: string,
  ) {
    if (!this.accountability) return;
    try {
      const settings = await this.accountability.getSettings(tenantId);
      const amount = Number(sale.totalAmount);
      const createdDay = new Date(
        Date.UTC(
          sale.createdAt.getUTCFullYear(),
          sale.createdAt.getUTCMonth(),
          sale.createdAt.getUTCDate(),
        ),
      );
      const closed = await this.prisma.dailyClose.findFirst({
        where: { branchId: sale.branchId, date: createdDay },
        select: { id: true },
      });
      const severity = closed ? 'HIGH' : severityForAmount(amount, settings.alerts.voidAlertAmount);
      const actor = await this.accountability.actorName(userId);

      await this.accountability.record({
        userId,
        action: 'SALE_VOIDED',
        entityType: 'Sale',
        entityId: sale.id,
        oldValues: { status: 'COMPLETED', totalAmount: amount, paymentMethod: sale.paymentMethod },
        newValues: { status: 'VOIDED', reason },
      });
      await this.accountability.raise({
        tenantId,
        branchId: sale.branchId,
        type: 'VOID',
        severity,
        title: closed ? 'Sale voided after day close' : 'Sale voided',
        body: `${actor} voided receipt ${sale.receiptNumber} (KES ${Math.round(amount).toLocaleString('en-KE')}, ${sale.paymentMethod}). Reason: ${reason || 'none given'}`,
        actorUserId: userId,
        entityType: 'Sale',
        entityId: sale.id,
        data: { amount, reason, afterDayClose: !!closed },
      });
    } catch (error) {
      // Recording must never undo a void that has already committed.
    }
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

    // Create refund
    const createdRefund = await this.prisma.$transaction(async (tx) => {
      await tx.$queryRaw`
        SELECT id FROM sales WHERE id = ${dto.saleId} FOR UPDATE
      `;
      const lockedSale = await tx.sale.findUnique({
        where: { id: dto.saleId },
        include: { items: true, refunds: { include: { items: true } } },
      });
      if (!lockedSale || lockedSale.status === SaleStatus.VOIDED) {
        throw new BadRequestException('Cannot refund a voided sale');
      }

      let lockedRefundAmount = 0;
      const lockedRefundItems: any[] = [];
      for (const refundItem of dto.items) {
        const saleItem = lockedSale.items.find(
          (item) => item.id === refundItem.saleItemId,
        );
        if (!saleItem) {
          throw new NotFoundException(
            `Sale item ${refundItem.saleItemId} not found`,
          );
        }
        const alreadyRefunded = lockedSale.refunds
          .flatMap((existingRefund) => existingRefund.items)
          .filter((item) => item.saleItemId === refundItem.saleItemId)
          .reduce((sum, item) => sum + Number(item.quantity), 0);
        const availableQty = Number(saleItem.quantity) - alreadyRefunded;
        if (refundItem.quantity > availableQty) {
          throw new BadRequestException(
            `Cannot refund ${refundItem.quantity} of ${saleItem.productName}. Available: ${availableQty}`,
          );
        }
        const amount =
          (Number(saleItem.totalAmount) / Number(saleItem.quantity)) *
          refundItem.quantity;
        lockedRefundAmount += amount;
        lockedRefundItems.push({
          saleItemId: refundItem.saleItemId,
          quantity: refundItem.quantity,
          amount,
          restockItem: refundItem.restockItem ?? true,
          productId: saleItem.productId,
        });
      }

      const refund = await tx.refund.create({
        data: {
          saleId: dto.saleId,
          amount: lockedRefundAmount,
          reason: dto.reason,
          status: 'completed',
          processedById: userId,
          processedAt: new Date(),
          items: {
            create: lockedRefundItems.map((i) => ({
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
      for (const item of [...lockedRefundItems].sort((a, b) =>
        a.productId.localeCompare(b.productId),
      )) {
        if (item.restockItem) {
          const stock = await lockStockForUpdate(
            tx,
            lockedSale.branchId,
            item.productId,
          );

          if (stock) {
            const previousQty = Number(stock.quantity);
            const newQty = previousQty + item.quantity;

            await tx.stock.update({
              where: { id: stock.id },
              data: { quantity: newQty },
            });

            await tx.stockMovement.create({
              data: {
                branchId: lockedSale.branchId,
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
      const totalRefunded =
        lockedSale.refunds.reduce((sum, r) => sum + Number(r.amount), 0) +
        lockedRefundAmount;
      const newStatus = totalRefunded >= Number(lockedSale.totalAmount)
        ? SaleStatus.REFUNDED
        : SaleStatus.PARTIAL_REFUND;

      await tx.sale.update({
        where: { id: dto.saleId },
        data: { status: newStatus },
      });

      return refund;
    });

    await this.recordRefund(createdRefund, sale, userId, tenantId, dto.reason);

    return createdRefund;
  }

  private async recordRefund(
    refund: { id: string; amount: unknown },
    sale: { id: string; branchId: string; receiptNumber: string },
    userId: string,
    tenantId: string,
    reason: string,
  ) {
    if (!this.accountability) return;
    try {
      const settings = await this.accountability.getSettings(tenantId);
      const amount = Number(refund.amount);
      const actor = await this.accountability.actorName(userId);
      await this.accountability.record({
        userId,
        action: 'SALE_REFUNDED',
        entityType: 'Sale',
        entityId: sale.id,
        newValues: { refundId: refund.id, amount, reason },
      });
      await this.accountability.raise({
        tenantId,
        branchId: sale.branchId,
        type: 'REFUND',
        severity: severityForAmount(amount, settings.alerts.refundAlertAmount),
        title: 'Refund given',
        body: `${actor} refunded KES ${Math.round(amount).toLocaleString('en-KE')} on receipt ${sale.receiptNumber}. Reason: ${reason || 'none given'}`,
        actorUserId: userId,
        entityType: 'Sale',
        entityId: sale.id,
        data: { amount, reason, refundId: refund.id },
      });
    } catch (error) {
      // Recording must never undo a refund that has already committed.
    }
  }

  async getDailySummary(branchId: string, date: string, tenantId: string) {
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
      select: { timezone: true },
    });
    const { start: startOfDay, end: endOfDay } = getDayBoundsInTimezone(
      date,
      branch?.timezone ?? 'Africa/Nairobi',
    );

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
      cardSales: 0,
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
    const { branchId, userId, startDate, endDate, page = 1, limit = 50 } = query;
    const skip = (page - 1) * limit;

    const where: any = {
      branch: { tenantId },
      paymentMethod: PaymentMethod.CREDIT,
      status: SaleStatus.COMPLETED,
    };

    if (branchId) where.branchId = branchId;
    if (userId) where.userId = userId;

    const createdAt = await this.resolveCreatedAtRange(tenantId, branchId, startDate, endDate);
    if (createdAt) where.createdAt = createdAt;

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

  async getDebtorsByCustomer(tenantId: string) {
    // Reuse the credit-sale outstanding-balance query logic, then aggregate per customer.
    const sales = await this.prisma.sale.findMany({
      where: {
        branch: { tenantId },
        paymentMethod: PaymentMethod.CREDIT,
        status: SaleStatus.COMPLETED,
      },
      include: {
        customer: { select: { id: true, name: true, phone: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    // Only sales that still have an outstanding balance
    const salesWithOutstanding = sales.filter((s) => {
      const outstanding = (s.metadata as any)?.outstandingBalance ?? 0;
      return Number(outstanding) > 0;
    });

    // Group by customerId; sales with no linked customer fall into a shared bucket.
    const UNLINKED_KEY = 'unlinked';
    const grouped = new Map<
      string,
      {
        customerId: string | null;
        customerName: string;
        phone: string | null;
        totalOutstanding: number;
        creditSaleCount: number;
        oldestUnpaidAt: Date;
      }
    >();

    for (const sale of salesWithOutstanding) {
      const outstanding = Number((sale.metadata as any)?.outstandingBalance ?? 0);
      const key = sale.customerId ?? UNLINKED_KEY;
      const existing = grouped.get(key);
      if (existing) {
        existing.totalOutstanding += outstanding;
        existing.creditSaleCount++;
        if (sale.createdAt < existing.oldestUnpaidAt) {
          existing.oldestUnpaidAt = sale.createdAt;
        }
      } else {
        grouped.set(key, {
          customerId: sale.customerId ?? null,
          customerName: sale.customer?.name ?? 'Walk-in / unlinked',
          phone: sale.customer?.phone ?? null,
          totalOutstanding: outstanding,
          creditSaleCount: 1,
          oldestUnpaidAt: sale.createdAt,
        });
      }
    }

    return Array.from(grouped.values())
      .map((d) => ({
        customerId: d.customerId,
        customerName: d.customerName,
        phone: d.phone,
        totalOutstanding: d.totalOutstanding,
        creditSaleCount: d.creditSaleCount,
        oldestUnpaidAt: d.oldestUnpaidAt.toISOString(),
      }))
      .sort((a, b) => b.totalOutstanding - a.totalOutstanding);
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
      select: { code: true, timezone: true },
    });

    const timezone = branch?.timezone ?? 'Africa/Nairobi';
    const todayStr = todayInTimezone(timezone);
    const datePrefix = todayStr.replace(/-/g, '');
    const prefix = `${branch?.code || 'POS'}-${datePrefix}`;

    // Get count for today
    const key = `receipt:${prefix}`;
    let count = await this.redisService.get(key);

    if (!count) {
      // Count from database
      const { start: startOfDay } = getDayBoundsInTimezone(todayStr, timezone);

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

    if (sale.payments && sale.payments.length > 0) {
      result.tenders = sale.payments.map((p: any) => ({
        method: p.method,
        amount: Number(p.amount),
        reference: p.transactionId,
      }));
    }

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
        unit: item.unit ?? null,
        quantityPerUnit:
          item.quantityPerUnit != null ? Number(item.quantityPerUnit) : null,
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
