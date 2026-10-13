import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ManualPaymentStatus, PaymentMethod, PaymentStatus, Prisma } from '@prisma/client';
import { randomBytes } from 'crypto';
import { AuditService } from '../audit/audit.service';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  CreateManualPaymentRequestDto,
  ManualPaymentListQueryDto,
  RejectManualPaymentDto,
} from './dto/manual-payment.dto';

export const MANUAL_APPROVE_PERMISSION = 'payments.manual_approve';

/**
 * Approval workflow for payments taken outside the app (bank transfer, cheque, etc.).
 * A cashier raises a request; a different user holding `payments.manual_approve` approves
 * or rejects it. Approving a request linked to a sale also records a COMPLETED MANUAL payment.
 */
@Injectable()
export class ManualPaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditService: AuditService,
  ) {}

  async createRequest(userId: string, tenantId: string, dto: CreateManualPaymentRequestDto) {
    await this.assertBranch(tenantId, dto.branchId);
    if (dto.saleId) {
      const sale = await this.prisma.sale.findFirst({
        where: { id: dto.saleId, branchId: dto.branchId, branch: { tenantId } },
        include: { manualPaymentRequest: true },
      });
      if (!sale) throw new NotFoundException('Sale not found');
      if (sale.manualPaymentRequest) {
        throw new BadRequestException('This sale already has a manual payment request');
      }
      if (dto.amount > Number(sale.totalAmount)) {
        throw new BadRequestException('Amount exceeds the sale total');
      }
    }

    const created = await this.prisma.manualPaymentRequest.create({
      data: {
        requestNumber: this.newRequestNumber(),
        saleId: dto.saleId ?? null,
        branchId: dto.branchId,
        requestedById: userId,
        paymentMethod: dto.paymentMethod.trim().toLowerCase(),
        amount: dto.amount,
        reason: dto.reason.trim(),
        notes: dto.notes?.trim() || null,
      },
      include: this.include,
    });
    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'manual_payment_request',
      entityId: created.id,
      newValues: { branchId: dto.branchId, saleId: dto.saleId, amount: dto.amount, paymentMethod: dto.paymentMethod },
    });
    return this.format(created);
  }

  /** Approvers see every request in the tenant; everyone else sees only their own. */
  async list(userId: string, tenantId: string, permissions: string[], query: ManualPaymentListQueryDto) {
    const canApprove = permissions.includes(MANUAL_APPROVE_PERMISSION);
    const rows = await this.prisma.manualPaymentRequest.findMany({
      where: {
        branch: { tenantId },
        ...(query.branchId ? { branchId: query.branchId } : {}),
        ...(query.status ? { status: query.status } : {}),
        ...(canApprove ? {} : { requestedById: userId }),
      },
      include: this.include,
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    return rows.map((row) => this.format(row));
  }

  async approve(approverId: string, tenantId: string, id: string) {
    const request = await this.findPendingForDecision(approverId, tenantId, id);
    const now = new Date();
    const updated = await this.prisma.$transaction(async (tx) => {
      // The status guard in the WHERE makes concurrent decisions race-safe.
      const claimed = await tx.manualPaymentRequest.updateMany({
        where: { id, status: ManualPaymentStatus.PENDING },
        data: { status: ManualPaymentStatus.APPROVED, approvedById: approverId, approvedAt: now },
      });
      if (claimed.count !== 1) throw new BadRequestException('Request has already been decided');

      if (request.saleId) {
        await tx.payment.create({
          data: {
            saleId: request.saleId,
            method: PaymentMethod.MANUAL,
            amount: request.amount,
            status: PaymentStatus.COMPLETED,
            transactionId: request.requestNumber,
            providerResponse: { source: 'manual_payment_request', approvedById: approverId } as Prisma.InputJsonValue,
            paidAt: now,
          },
        });
        await tx.manualPaymentRequest.update({
          where: { id },
          data: { status: ManualPaymentStatus.COMPLETED, completedAt: now },
        });
      }
      return tx.manualPaymentRequest.findUniqueOrThrow({ where: { id }, include: this.include });
    });
    await this.auditService.record({
      userId: approverId,
      action: 'APPROVE',
      entityType: 'manual_payment_request',
      entityId: id,
      newValues: { status: updated.status, amount: Number(updated.amount), saleId: updated.saleId },
    });
    return this.format(updated);
  }

  async reject(approverId: string, tenantId: string, id: string, dto: RejectManualPaymentDto) {
    await this.findPendingForDecision(approverId, tenantId, id);
    const claimed = await this.prisma.manualPaymentRequest.updateMany({
      where: { id, status: ManualPaymentStatus.PENDING },
      data: {
        status: ManualPaymentStatus.REJECTED,
        approvedById: approverId,
        approvedAt: new Date(),
        rejectionReason: dto.rejectionReason.trim(),
      },
    });
    if (claimed.count !== 1) throw new BadRequestException('Request has already been decided');
    const updated = await this.prisma.manualPaymentRequest.findUniqueOrThrow({ where: { id }, include: this.include });
    await this.auditService.record({
      userId: approverId,
      action: 'REJECT',
      entityType: 'manual_payment_request',
      entityId: id,
      newValues: { rejectionReason: dto.rejectionReason },
    });
    return this.format(updated);
  }

  private async findPendingForDecision(approverId: string, tenantId: string, id: string) {
    const request = await this.prisma.manualPaymentRequest.findFirst({
      where: { id, branch: { tenantId } },
    });
    if (!request) throw new NotFoundException('Manual payment request not found');
    if (request.status !== ManualPaymentStatus.PENDING) {
      throw new BadRequestException('Request has already been decided');
    }
    if (request.requestedById === approverId) {
      throw new ForbiddenException('You cannot approve or reject your own request');
    }
    return request;
  }

  private async assertBranch(tenantId: string, branchId: string) {
    const branch = await this.prisma.branch.findFirst({ where: { id: branchId, tenantId } });
    if (!branch) throw new NotFoundException('Branch not found');
  }

  private newRequestNumber(): string {
    const d = new Date();
    const ymd = `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}${String(d.getUTCDate()).padStart(2, '0')}`;
    return `MPR-${ymd}-${randomBytes(3).toString('hex').toUpperCase()}`;
  }

  private readonly include = {
    requestedBy: { select: { id: true, firstName: true, lastName: true } },
    approvedBy: { select: { id: true, firstName: true, lastName: true } },
    sale: { select: { id: true, receiptNumber: true, totalAmount: true } },
  } satisfies Prisma.ManualPaymentRequestInclude;

  private format(row: any) {
    const name = (u: any) => (u ? `${u.firstName ?? ''} ${u.lastName ?? ''}`.trim() : null);
    return {
      id: row.id,
      requestNumber: row.requestNumber,
      branchId: row.branchId,
      saleId: row.saleId ?? null,
      receiptNumber: row.sale?.receiptNumber ?? null,
      paymentMethod: row.paymentMethod,
      amount: Number(row.amount),
      reason: row.reason,
      notes: row.notes ?? null,
      status: row.status,
      rejectionReason: row.rejectionReason ?? null,
      requestedBy: name(row.requestedBy),
      requestedById: row.requestedById,
      approvedBy: name(row.approvedBy),
      approvedAt: row.approvedAt ?? null,
      completedAt: row.completedAt ?? null,
      createdAt: row.createdAt,
    };
  }
}
