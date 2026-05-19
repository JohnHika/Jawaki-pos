import { Injectable, BadRequestException } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { RedisService } from '../../common/redis/redis.service';
import { PaymentMethod } from '@prisma/client';
import {
  ProcessBulkPaymentDto,
  ProcessBulkCreditPaymentDto,
  BulkPaymentResultDto,
  BulkPaymentResultItemDto,
  BulkPaymentErrorDto,
  BulkPaymentStatusDto,
} from '../dto/bulk-payment.dto';

@Injectable()
export class BulkPaymentService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
  ) {}

  async processBulkPayment(
    userId: string,
    tenantId: string,
    dto: ProcessBulkPaymentDto,
  ): Promise<BulkPaymentResultDto> {
    // Validate branch belongs to tenant
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
    });

    if (!branch) {
      throw new BadRequestException('Branch not found');
    }

    // Generate batch ID
    const batchId = `BULK-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    const results: BulkPaymentResultItemDto[] = [];
    const errors: BulkPaymentErrorDto[] = [];
    let totalAmount = 0;
    let processedCount = 0;
    let failedCount = 0;

    // Process each payment
    for (const payment of dto.payments) {
      try {
        // Validate sale exists and belongs to tenant
        const sale = await this.prisma.sale.findFirst({
          where: {
            id: payment.saleId,
            branch: { tenantId },
          },
        });

        if (!sale) {
          throw new BadRequestException('Sale not found');
        }

        if (sale.status !== 'COMPLETED') {
          throw new BadRequestException('Sale is not in completed status');
        }

        // Check if payment method matches (for credit payments)
        if (dto.paymentMethod !== 'SPLIT' && sale.paymentMethod !== dto.paymentMethod) {
          if (!(sale.paymentMethod === 'CREDIT' && dto.paymentMethod === 'CASH')) {
            // Allow paying credit sales with cash
            throw new BadRequestException(
              `Payment method mismatch. Sale uses ${sale.paymentMethod}`,
            );
          }
        }

        // Calculate outstanding balance for credit sales
        const outstandingBalance = (sale.metadata as any)?.outstandingBalance ?? 0;
        const paymentAmount = payment.amount || Number(sale.totalAmount) - Number(sale.paidAmount);

        if (paymentAmount <= 0) {
          throw new BadRequestException('Sale is already fully paid');
        }

        if (paymentAmount > outstandingBalance && sale.paymentMethod === 'CREDIT') {
          throw new BadRequestException(
            `Payment amount exceeds outstanding balance of KES ${outstandingBalance}`,
          );
        }

        // Update sale with payment
        const newPaidAmount = Number(sale.paidAmount) + paymentAmount;
        const newOutstandingBalance = Math.max(0, outstandingBalance - paymentAmount);

        await this.prisma.sale.update({
          where: { id: payment.saleId },
          data: {
            paidAmount: newPaidAmount,
            changeAmount: newPaidAmount > Number(sale.totalAmount)
              ? newPaidAmount - Number(sale.totalAmount)
              : sale.changeAmount,
            metadata: {
              ...(sale.metadata as object),
              outstandingBalance: newOutstandingBalance,
              bulkPaymentBatchId: batchId,
              bulkPaymentNotes: dto.notes,
              bulkPaymentReference: dto.reference,
            },
          },
        });

        // Create payment record
        await this.prisma.payment.create({
          data: {
            saleId: payment.saleId,
            method: dto.paymentMethod as PaymentMethod,
            amount: paymentAmount,
            status: 'COMPLETED',
            paidAt: new Date(),
            providerResponse: {
              bulkPayment: true,
              batchId,
              reference: dto.reference,
              notes: dto.notes,
              paymentNotes: payment.notes,
            },
          },
        });

        // If fully paid, update credit sale status
        if (sale.paymentMethod === 'CREDIT' && newOutstandingBalance === 0) {
          await this.prisma.sale.update({
            where: { id: payment.saleId },
            data: {
              metadata: {
                ...(sale.metadata as object),
                outstandingBalance: 0,
                paidOffAt: new Date().toISOString(),
                paidOffBy: userId,
              },
            },
          });
        }

        results.push({
          saleId: payment.saleId,
          receiptNumber: sale.receiptNumber,
          amount: paymentAmount,
          status: 'success',
          message: newOutstandingBalance === 0 ? 'Fully paid' : `Remaining: KES ${newOutstandingBalance}`,
        });

        totalAmount += paymentAmount;
        processedCount++;
      } catch (error) {
        errors.push({
          saleId: payment.saleId,
          error: error.message || 'Unknown error',
        });
        failedCount++;

        results.push({
          saleId: payment.saleId,
          amount: payment.amount,
          status: 'failed',
          message: error.message || 'Unknown error',
        });
      }
    }

    // Store batch status in Redis
    const batchStatus: BulkPaymentStatusDto = {
      batchId,
      status: failedCount === 0 ? 'completed' : failedCount === dto.payments.length ? 'failed' : 'partial',
      createdAt: new Date(),
      completedAt: new Date(),
      totalPayments: dto.payments.length,
      processedPayments: processedCount,
      successfulPayments: processedCount,
      failedPayments: failedCount,
      totalAmount,
      results,
    };

    await this.redisService.set(
      `bulk-payment:${batchId}`,
      JSON.stringify(batchStatus),
      86400 * 7, // 7 days
    );

    return {
      success: processedCount > 0,
      batchId,
      processedCount,
      failedCount,
      totalAmount,
      results,
      errors,
    };
  }

  async processBulkCreditPayment(
    userId: string,
    tenantId: string,
    dto: ProcessBulkCreditPaymentDto,
  ): Promise<BulkPaymentResultDto> {
    // Validate branch belongs to tenant
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
    });

    if (!branch) {
      throw new BadRequestException('Branch not found');
    }

    // Generate batch ID
    const batchId = `CREDIT-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    const results: BulkPaymentResultItemDto[] = [];
    const errors: BulkPaymentErrorDto[] = [];
    let totalAmount = 0;
    let processedCount = 0;
    let failedCount = 0;

    // Process each payment as a new credit sale
    for (const payment of dto.payments) {
      try {
        // Validate sale exists
        const sale = await this.prisma.sale.findFirst({
          where: {
            id: payment.saleId,
            branch: { tenantId },
          },
        });

        if (!sale) {
          throw new BadRequestException('Sale not found');
        }

        // Create customer if not exists
        let customerId = sale.customerId;

        if (!customerId && (dto.customerName || dto.customerPhone)) {
          // Find existing customer by tenant + phone
          const existing = await this.prisma.customer.findFirst({
            where: {
              tenantId,
              phone: dto.customerPhone || undefined,
            },
          });

          if (existing) {
            customerId = existing.id;
            await this.prisma.customer.update({
              where: { id: existing.id },
              data: {
                name: dto.customerName || 'Unknown Customer',
                phone: dto.customerPhone,
              },
            });
          } else {
            const newCustomer = await this.prisma.customer.create({
              data: {
                tenantId,
                name: dto.customerName || 'Unknown Customer',
                phone: dto.customerPhone,
              },
            });
            customerId = newCustomer.id;
          }

          // Link sale to customer
          await this.prisma.sale.update({
            where: { id: payment.saleId },
            data: { customerId },
          });
        }

        // Update sale to credit payment if not already
        if (sale.paymentMethod !== 'CREDIT') {
          const outstandingBalance = payment.amount || Number(sale.totalAmount);
          const dueDate = dto.dueDate
            ? new Date(dto.dueDate)
            : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days default

          await this.prisma.sale.update({
            where: { id: payment.saleId },
            data: {
              paymentMethod: 'CREDIT',
              paidAmount: 0,
              metadata: {
                ...(sale.metadata as object),
                outstandingBalance,
                dueDate: dueDate.toISOString(),
                convertedToCreditAt: new Date().toISOString(),
                convertedToCreditBy: userId,
                bulkPaymentBatchId: batchId,
                customerName: dto.customerName,
                customerPhone: dto.customerPhone,
                notes: dto.notes,
              },
            },
          });

          results.push({
            saleId: payment.saleId,
            receiptNumber: sale.receiptNumber,
            amount: outstandingBalance,
            status: 'success',
            message: `Converted to credit. Due: ${dueDate.toLocaleDateString()}`,
          });
        } else {
          // Already credit, just update metadata
          const outstandingBalance = (sale.metadata as any)?.outstandingBalance ?? Number(sale.totalAmount);

          await this.prisma.sale.update({
            where: { id: payment.saleId },
            data: {
              metadata: {
                ...(sale.metadata as object),
                bulkPaymentBatchId: batchId,
                customerName: dto.customerName,
                customerPhone: dto.customerPhone,
                notes: dto.notes,
              },
            },
          });

          results.push({
            saleId: payment.saleId,
            receiptNumber: sale.receiptNumber,
            amount: outstandingBalance,
            status: 'success',
            message: 'Credit sale updated',
          });
        }

        totalAmount += payment.amount || Number(sale.totalAmount);
        processedCount++;
      } catch (error) {
        errors.push({
          saleId: payment.saleId,
          error: error.message || 'Unknown error',
        });
        failedCount++;

        results.push({
          saleId: payment.saleId,
          amount: payment.amount,
          status: 'failed',
          message: error.message || 'Unknown error',
        });
      }
    }

    // Store batch status in Redis
    const batchStatus: BulkPaymentStatusDto = {
      batchId,
      status: failedCount === 0 ? 'completed' : failedCount === dto.payments.length ? 'failed' : 'partial',
      createdAt: new Date(),
      completedAt: new Date(),
      totalPayments: dto.payments.length,
      processedPayments: processedCount,
      successfulPayments: processedCount,
      failedPayments: failedCount,
      totalAmount,
      results,
    };

    await this.redisService.set(
      `bulk-payment:${batchId}`,
      JSON.stringify(batchStatus),
      86400 * 7, // 7 days
    );

    return {
      success: processedCount > 0,
      batchId,
      processedCount,
      failedCount,
      totalAmount,
      results,
      errors,
    };
  }

  async getBulkPaymentStatus(batchId: string): Promise<BulkPaymentStatusDto | null> {
    const statusJson = await this.redisService.get(`bulk-payment:${batchId}`);

    if (statusJson) {
      return JSON.parse(statusJson) as BulkPaymentStatusDto;
    }

    return null;
  }

  async getBulkPaymentHistory(
    tenantId: string,
    query: any,
  ): Promise<{ items: any[]; total: number }> {
    const { branchId, page = 1, limit = 20 } = query;
    const skip = (page - 1) * limit;

    // Get all sales with bulk payment metadata
    const where: any = {
      branch: { tenantId },
      metadata: {
        path: ['bulkPaymentBatchId'],
        not: null,
      },
    };

    if (branchId) {
      where.branchId = branchId;
    }

    const sales = await this.prisma.sale.findMany({
      where,
      include: {
        branch: { select: { name: true } },
        customer: { select: { name: true, phone: true } },
      },
      orderBy: { updatedAt: 'desc' },
      skip,
      take: limit,
    });

    // Group by batch ID
    const batchMap = new Map();
    for (const sale of sales) {
      const batchId = (sale.metadata as any)?.bulkPaymentBatchId;
      if (!batchId) continue;

      if (!batchMap.has(batchId)) {
        batchMap.set(batchId, {
          batchId,
          branchName: sale.branch.name,
          totalAmount: 0,
          count: 0,
          createdAt: sale.updatedAt,
          reference: (sale.metadata as any)?.bulkPaymentReference,
          notes: (sale.metadata as any)?.bulkPaymentNotes,
        });
      }

      const batch = batchMap.get(batchId);
      batch.totalAmount += Number(sale.paidAmount || 0);
      batch.count++;
    }

    const items = Array.from(batchMap.values());
    return {
      items: items.slice(skip, skip + limit),
      total: items.length,
    };
  }
}
