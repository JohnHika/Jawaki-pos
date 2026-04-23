import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { RedisService } from '../../common/redis/redis.service';
import { ManualPaymentStatus } from '@prisma/client';
import {
  CreateManualPaymentRequestDto,
  ApproveManualPaymentDto,
  RejectManualPaymentDto,
  ManualPaymentQueryDto,
  ManualPaymentResponseDto,
} from '../dto/manual-payment.dto';

@Injectable()
export class ManualPaymentService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
  ) {}

  async createRequest(userId: string, tenantId: string, dto: CreateManualPaymentRequestDto) {
    // Validate branch belongs to tenant
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    // Validate sale if provided
    if (dto.saleId) {
      const sale = await this.prisma.sale.findFirst({
        where: { id: dto.saleId, branch: { tenantId } },
      });

      if (!sale) {
        throw new NotFoundException('Sale not found');
      }
    }

    // Generate request number
    const requestNumber = await this.generateRequestNumber(dto.branchId);

    // Create manual payment request
    const request = await this.prisma.manualPaymentRequest.create({
      data: {
        requestNumber,
        branchId: dto.branchId,
        requestedById: userId,
        saleId: dto.saleId,
        paymentMethod: dto.paymentMethod,
        amount: dto.amount,
        reason: dto.reason,
        notes: dto.notes,
        status: ManualPaymentStatus.PENDING,
        metadata: dto.metadata || {},
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        sale: { select: { receiptNumber: true } },
      },
    });

    return this.formatRequest(request);
  }

  async getPendingRequests(tenantId: string, query: ManualPaymentQueryDto) {
    const { branchId, status, startDate, endDate, page = 1, limit = 20 } = query;
    const skip = (page - 1) * limit;

    const where: any = {
      branch: { tenantId },
    };

    if (branchId) where.branchId = branchId;
    if (status) where.status = status;

    if (startDate || endDate) {
      where.createdAt = {};
      if (startDate) where.createdAt.gte = new Date(startDate);
      if (endDate) where.createdAt.lte = new Date(endDate);
    }

    const [requests, total] = await Promise.all([
      this.prisma.manualPaymentRequest.findMany({
        where,
        include: {
          branch: { select: { name: true } },
          requestedBy: { select: { firstName: true, lastName: true } },
          approvedBy: { select: { firstName: true, lastName: true } },
          sale: { select: { receiptNumber: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.manualPaymentRequest.count({ where }),
    ]);

    return {
      items: requests.map((r) => this.formatRequest(r)),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async getRequest(requestId: string, tenantId: string) {
    const request = await this.prisma.manualPaymentRequest.findFirst({
      where: {
        id: requestId,
        branch: { tenantId },
      },
      include: {
        branch: { select: { name: true, code: true } },
        requestedBy: { select: { firstName: true, lastName: true, email: true } },
        approvedBy: { select: { firstName: true, lastName: true } },
        sale: {
          select: {
            receiptNumber: true,
            totalAmount: true,
            customer: { select: { name: true, phone: true } },
          },
        },
      },
    });

    if (!request) {
      throw new NotFoundException('Manual payment request not found');
    }

    return this.formatRequest(request);
  }

  async approveRequest(
    requestId: string,
    userId: string,
    tenantId: string,
    dto: ApproveManualPaymentDto,
  ) {
    const request = await this.prisma.manualPaymentRequest.findFirst({
      where: {
        id: requestId,
        branch: { tenantId },
      },
    });

    if (!request) {
      throw new NotFoundException('Manual payment request not found');
    }

    if (request.status !== ManualPaymentStatus.PENDING) {
      throw new BadRequestException('Only pending requests can be approved');
    }

    const updated = await this.prisma.manualPaymentRequest.update({
      where: { id: requestId },
      data: {
        status: ManualPaymentStatus.APPROVED,
        approvedById: userId,
        approvedAt: new Date(),
        notes: dto.notes ? `${request.notes || ''}\nApproval notes: ${dto.notes}`.trim() : request.notes,
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        approvedBy: { select: { firstName: true, lastName: true } },
      },
    });

    return this.formatRequest(updated);
  }

  async rejectRequest(
    requestId: string,
    userId: string,
    tenantId: string,
    dto: RejectManualPaymentDto,
  ) {
    const request = await this.prisma.manualPaymentRequest.findFirst({
      where: {
        id: requestId,
        branch: { tenantId },
      },
    });

    if (!request) {
      throw new NotFoundException('Manual payment request not found');
    }

    if (request.status !== ManualPaymentStatus.PENDING) {
      throw new BadRequestException('Only pending requests can be rejected');
    }

    const updated = await this.prisma.manualPaymentRequest.update({
      where: { id: requestId },
      data: {
        status: ManualPaymentStatus.REJECTED,
        approvedById: userId,
        approvedAt: new Date(),
        rejectionReason: dto.rejectionReason,
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        approvedBy: { select: { firstName: true, lastName: true } },
      },
    });

    return this.formatRequest(updated);
  }

  async completeRequest(
    requestId: string,
    userId: string,
    tenantId: string,
    dto: { notes?: string } = {},
  ) {
    const request = await this.prisma.manualPaymentRequest.findFirst({
      where: {
        id: requestId,
        branch: { tenantId },
      },
    });

    if (!request) {
      throw new NotFoundException('Manual payment request not found');
    }

    if (request.status !== ManualPaymentStatus.APPROVED) {
      throw new BadRequestException('Only approved requests can be completed');
    }

    const updated = await this.prisma.manualPaymentRequest.update({
      where: { id: requestId },
      data: {
        status: ManualPaymentStatus.COMPLETED,
        completedAt: new Date(),
        notes: dto.notes ? `${request.notes || ''}\nCompletion notes: ${dto.notes}`.trim() : request.notes,
      },
      include: {
        branch: { select: { name: true } },
        requestedBy: { select: { firstName: true, lastName: true } },
        approvedBy: { select: { firstName: true, lastName: true } },
      },
    });

    return this.formatRequest(updated);
  }

  async deleteRequest(requestId: string, userId: string, tenantId: string) {
    const request = await this.prisma.manualPaymentRequest.findFirst({
      where: {
        id: requestId,
        branch: { tenantId },
      },
    });

    if (!request) {
      throw new NotFoundException('Manual payment request not found');
    }

    if (request.status !== ManualPaymentStatus.PENDING) {
      throw new BadRequestException('Only pending requests can be deleted');
    }

    await this.prisma.manualPaymentRequest.delete({
      where: { id: requestId },
    });

    return { success: true, message: 'Request deleted successfully' };
  }

  private async generateRequestNumber(branchId: string): Promise<string> {
    const branch = await this.prisma.branch.findUnique({
      where: { id: branchId },
      select: { code: true },
    });

    const today = new Date();
    const datePrefix = today.toISOString().slice(0, 10).replace(/-/g, '');
    const prefix = `MPR-${branch?.code || 'POS'}-${datePrefix}`;

    // Get count from Redis
    const key = `manual-payment:${prefix}`;
    let count = await this.redisService.get(key);

    if (!count) {
      // Count from database
      const startOfDay = new Date(today);
      startOfDay.setHours(0, 0, 0, 0);

      const existingCount = await this.prisma.manualPaymentRequest.count({
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

  private formatRequest(request: any): ManualPaymentResponseDto {
    return {
      id: request.id,
      requestNumber: request.requestNumber,
      saleId: request.saleId,
      branchId: request.branchId,
      branchName: request.branch?.name,
      requestedById: request.requestedById,
      requestedByName: request.requestedBy
        ? `${request.requestedBy.firstName} ${request.requestedBy.lastName}`
        : 'Unknown',
      approvedById: request.approvedById,
      approvedByName: request.approvedBy
        ? `${request.approvedBy.firstName} ${request.approvedBy.lastName}`
        : undefined,
      paymentMethod: request.paymentMethod,
      amount: Number(request.amount),
      reason: request.reason,
      status: request.status,
      notes: request.notes,
      rejectionReason: request.rejectionReason,
      approvedAt: request.approvedAt,
      completedAt: request.completedAt,
      metadata: request.metadata as Record<string, any>,
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
    };
  }
}
