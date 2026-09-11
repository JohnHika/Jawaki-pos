import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import {
  Prisma,
  ReceivablePaymentMethod,
  ReceivableStatus,
  SupplierInvoiceStatus,
} from '@prisma/client';
import { AuditService } from '../audit/audit.service';
import { CashFlowService } from '../cash-flow/cash-flow.service';
import { CashEntryType } from '../cash-flow/dto/cash-flow.dto';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  CreatePeerDebtorDto,
  CreatePeerReceivableDto,
  RecordReceivablePaymentDto,
} from './dto/finance.dto';

export interface CreateRetailReceivableForSaleParams {
  tenantId: string;
  branchId: string;
  saleId: string;
  customerId?: string;
  originalAmount: number;
  dueDate?: Date;
  offlineId?: string;
  createdById: string;
}

@Injectable()
export class FinanceService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditService: AuditService,
    private readonly cashFlowService: CashFlowService,
  ) {}

  /** Creates the obligation inside the caller-owned sale transaction. */
  async createRetailReceivableForSale(
    tx: Prisma.TransactionClient,
    params: CreateRetailReceivableForSaleParams,
  ) {
    if (params.originalAmount <= 0) return null;
    return tx.retailReceivable.create({
      data: {
        tenantId: params.tenantId,
        branchId: params.branchId,
        saleId: params.saleId,
        customerId: params.customerId ?? null,
        originalAmount: params.originalAmount,
        outstandingAmount: params.originalAmount,
        dueDate: params.dueDate ?? null,
        status: ReceivableStatus.OPEN,
        offlineId: params.offlineId ?? null,
        createdById: params.createdById,
      },
    });
  }

  async getOverview(tenantId: string, branchId: string) {
    await this.assertBranch(tenantId, branchId);
    const [supplier, retail, peer] = await Promise.all([
      this.prisma.supplierInvoice.aggregate({
        where: { tenantId, branchId, status: { not: SupplierInvoiceStatus.PAID } },
        _sum: { dueAmount: true },
      }),
      this.prisma.retailReceivable.aggregate({
        where: { tenantId, branchId, status: { in: [ReceivableStatus.OPEN, ReceivableStatus.PARTIAL] } },
        _sum: { outstandingAmount: true },
      }),
      this.prisma.peerReceivable.aggregate({
        where: { tenantId, branchId, status: { in: [ReceivableStatus.OPEN, ReceivableStatus.PARTIAL] } },
        _sum: { outstandingAmount: true },
      }),
    ]);
    return {
      branchId,
      supplierPayablesOutstanding: this.money(supplier._sum.dueAmount),
      retailReceivablesOutstanding: this.money(retail._sum.outstandingAmount),
      peerReceivablesOutstanding: this.money(peer._sum.outstandingAmount),
    };
  }

  async getPayables(tenantId: string, branchId: string, status?: SupplierInvoiceStatus) {
    await this.assertBranch(tenantId, branchId);
    const invoices = await this.prisma.supplierInvoice.findMany({
      where: { tenantId, branchId, ...(status ? { status } : {}) },
      include: { supplier: { select: { id: true, name: true, phone: true } }, payments: true },
      orderBy: [{ dueDate: 'asc' }, { createdAt: 'desc' }],
    });
    return invoices.map((invoice) => ({
      id: invoice.id,
      supplier: invoice.supplier,
      invoiceNumber: invoice.invoiceNumber,
      totalAmount: this.money(invoice.totalAmount),
      paidAmount: this.money(invoice.paidAmount),
      outstandingAmount: this.money(invoice.dueAmount),
      dueDate: invoice.dueDate,
      status: invoice.status,
      createdAt: invoice.createdAt,
    }));
  }

  async getRetailReceivables(tenantId: string, branchId: string, status?: ReceivableStatus) {
    await this.assertBranch(tenantId, branchId);
    const rows = await this.prisma.retailReceivable.findMany({
      where: { tenantId, branchId, ...(status ? { status } : {}) },
      include: {
        sale: { select: { id: true, receiptNumber: true, customer: { select: { id: true, name: true } } } },
        payments: { orderBy: { paidAt: 'desc' } },
      },
      orderBy: [{ dueDate: 'asc' }, { createdAt: 'desc' }],
    });
    return rows.map((row) => this.formatRetailReceivable(row));
  }

  async getPeerDebtors(tenantId: string) {
    const debtors = await this.prisma.peerDebtor.findMany({
      where: { tenantId, isActive: true },
      orderBy: { name: 'asc' },
    });
    return debtors;
  }

  async createPeerDebtor(tenantId: string, dto: CreatePeerDebtorDto) {
    const name = dto.name.trim();
    if (!name) throw new BadRequestException('Debtor name is required');
    return this.prisma.peerDebtor.upsert({
      where: { tenantId_name: { tenantId, name } },
      create: { tenantId, ...dto, name },
      update: {
        contactName: dto.contactName,
        phone: dto.phone,
        email: dto.email,
        address: dto.address,
        notes: dto.notes,
        isActive: true,
      },
    });
  }

  async getPeerReceivables(tenantId: string, branchId: string, status?: ReceivableStatus) {
    await this.assertBranch(tenantId, branchId);
    const rows = await this.prisma.peerReceivable.findMany({
      where: { tenantId, branchId, ...(status ? { status } : {}) },
      include: { debtor: true, payments: { orderBy: { paidAt: 'desc' } } },
      orderBy: [{ dueDate: 'asc' }, { createdAt: 'desc' }],
    });
    return rows.map((row) => this.formatPeerReceivable(row));
  }

  async createPeerReceivable(userId: string, tenantId: string, dto: CreatePeerReceivableDto) {
    await this.assertBranch(tenantId, dto.branchId);
    if (dto.offlineId) {
      const existing = await this.prisma.peerReceivable.findUnique({ where: { offlineId: dto.offlineId } });
      if (existing) {
        if (existing.tenantId !== tenantId || existing.branchId !== dto.branchId) {
          throw new NotFoundException('Peer receivable not found');
        }
        return this.getPeerReceivable(tenantId, existing.id);
      }
    }
    const debtor = await this.prisma.peerDebtor.findFirst({ where: { id: dto.debtorId, tenantId, isActive: true } });
    if (!debtor) throw new NotFoundException('Peer debtor not found');

    const receivable = await this.prisma.peerReceivable.create({
      data: {
        tenantId,
        branchId: dto.branchId,
        debtorId: dto.debtorId,
        reference: dto.reference,
        description: dto.description,
        originalAmount: dto.amount,
        outstandingAmount: dto.amount,
        dueDate: dto.dueDate ? new Date(dto.dueDate) : null,
        offlineId: dto.offlineId,
        createdById: userId,
      },
    });
    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'peer_receivable',
      entityId: receivable.id,
      newValues: { branchId: dto.branchId, debtorId: dto.debtorId, originalAmount: dto.amount },
    });
    return this.getPeerReceivable(tenantId, receivable.id);
  }

  async recordRetailPayment(userId: string, tenantId: string, receivableId: string, dto: RecordReceivablePaymentDto) {
    await this.assertBranch(tenantId, dto.branchId);
    if (dto.amount <= 0) throw new BadRequestException('Payment amount must be greater than zero');
    if (dto.offlineId) {
      const existing = await this.prisma.retailReceivablePayment.findUnique({
        where: { offlineId: dto.offlineId },
        include: { receivable: true },
      });
      if (existing) {
        this.assertExistingPaymentScope(existing, tenantId, dto.branchId, receivableId);
        return this.formatPayment(existing);
      }
    }
    let payment: any;
    try {
      payment = await this.prisma.$transaction((tx) =>
        this.recordPaymentInTransaction(tx, 'retail', userId, tenantId, receivableId, dto),
      );
    } catch (error) {
      if (!dto.offlineId || !this.isUniqueConstraint(error)) throw error;
      const existing = await this.prisma.retailReceivablePayment.findUnique({
        where: { offlineId: dto.offlineId },
        include: { receivable: true },
      });
      if (!existing) throw error;
      this.assertExistingPaymentScope(existing, tenantId, dto.branchId, receivableId);
      return this.formatPayment(existing);
    }
    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'retail_receivable_payment',
      entityId: payment.id,
      newValues: { receivableId, branchId: dto.branchId, amount: dto.amount, method: dto.method },
    });
    return this.formatPayment(payment);
  }

  async recordPeerPayment(userId: string, tenantId: string, receivableId: string, dto: RecordReceivablePaymentDto) {
    await this.assertBranch(tenantId, dto.branchId);
    if (dto.amount <= 0) throw new BadRequestException('Payment amount must be greater than zero');
    if (dto.offlineId) {
      const existing = await this.prisma.peerReceivablePayment.findUnique({
        where: { offlineId: dto.offlineId },
        include: { receivable: true },
      });
      if (existing) {
        this.assertExistingPaymentScope(existing, tenantId, dto.branchId, receivableId);
        return this.formatPayment(existing);
      }
    }
    let payment: any;
    try {
      payment = await this.prisma.$transaction((tx) =>
        this.recordPaymentInTransaction(tx, 'peer', userId, tenantId, receivableId, dto),
      );
    } catch (error) {
      if (!dto.offlineId || !this.isUniqueConstraint(error)) throw error;
      const existing = await this.prisma.peerReceivablePayment.findUnique({
        where: { offlineId: dto.offlineId },
        include: { receivable: true },
      });
      if (!existing) throw error;
      this.assertExistingPaymentScope(existing, tenantId, dto.branchId, receivableId);
      return this.formatPayment(existing);
    }
    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'peer_receivable_payment',
      entityId: payment.id,
      newValues: { receivableId, branchId: dto.branchId, amount: dto.amount, method: dto.method },
    });
    return this.formatPayment(payment);
  }

  private async recordPaymentInTransaction(
    tx: Prisma.TransactionClient,
    type: 'retail' | 'peer',
    userId: string,
    tenantId: string,
    receivableId: string,
    dto: RecordReceivablePaymentDto,
  ): Promise<any> {
    if (type === 'retail') {
      await tx.$executeRaw`SELECT id FROM retail_receivables WHERE id = ${receivableId} FOR UPDATE`;
    } else {
      await tx.$executeRaw`SELECT id FROM peer_receivables WHERE id = ${receivableId} FOR UPDATE`;
    }

    const delegate: any = type === 'retail' ? tx.retailReceivable : tx.peerReceivable;
    const receivable = await delegate.findFirst({ where: { id: receivableId, tenantId, branchId: dto.branchId } });
    if (!receivable) throw new NotFoundException('Receivable not found');
    if (receivable.status === ReceivableStatus.WRITTEN_OFF || receivable.status === ReceivableStatus.PAID) {
      throw new BadRequestException('Receivable is not open for payment');
    }
    const outstanding = this.money(receivable.outstandingAmount);
    if (dto.amount > outstanding) throw new BadRequestException('Payment amount exceeds outstanding balance');

    const newOutstanding = Math.round((outstanding - dto.amount) * 100) / 100;
    const status = newOutstanding === 0 ? ReceivableStatus.PAID : ReceivableStatus.PARTIAL;
    await delegate.update({ where: { id: receivable.id }, data: { outstandingAmount: newOutstanding, status } });

    const paymentDelegate: any = type === 'retail' ? tx.retailReceivablePayment : tx.peerReceivablePayment;
    const payment = await paymentDelegate.create({
      data: {
        receivableId: receivable.id,
        tenantId,
        branchId: dto.branchId,
        amount: dto.amount,
        method: dto.method,
        reference: dto.reference,
        notes: dto.notes,
        offlineId: dto.offlineId,
        createdById: userId,
      },
    });
    if (dto.method === ReceivablePaymentMethod.CASH) {
      await this.cashFlowService.recordEntry({
        tx,
        branchId: dto.branchId,
        type: CashEntryType.RECEIVABLE_COLLECTION_IN,
        amount: dto.amount,
        referenceType: `${type}_receivable_payment`,
        referenceId: payment.id,
        note: dto.notes,
        createdById: userId,
      });
    }
    return payment;
  }

  private async getPeerReceivable(tenantId: string, id: string) {
    const row = await this.prisma.peerReceivable.findFirst({
      where: { id, tenantId },
      include: { debtor: true, payments: { orderBy: { paidAt: 'desc' } } },
    });
    if (!row) throw new NotFoundException('Peer receivable not found');
    return this.formatPeerReceivable(row);
  }

  private async assertBranch(tenantId: string, branchId: string) {
    const branch = await this.prisma.branch.findFirst({ where: { id: branchId, tenantId } });
    if (!branch) throw new NotFoundException('Branch not found');
    return branch;
  }

  private assertExistingPaymentScope(existing: any, tenantId: string, branchId: string, receivableId: string) {
    if (
      existing.receivableId !== receivableId ||
      existing.tenantId !== tenantId ||
      existing.branchId !== branchId ||
      existing.receivable?.tenantId !== tenantId ||
      existing.receivable?.branchId !== branchId
    ) {
      throw new NotFoundException('Receivable payment not found');
    }
  }

  private isUniqueConstraint(error: unknown): boolean {
    return error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002';
  }

  private formatRetailReceivable(row: any) {
    return {
      id: row.id,
      saleId: row.saleId,
      receiptNumber: row.sale?.receiptNumber ?? null,
      customer: row.sale?.customer ?? null,
      originalAmount: this.money(row.originalAmount),
      outstandingAmount: this.money(row.outstandingAmount),
      dueDate: row.dueDate,
      status: row.status,
      createdAt: row.createdAt,
      payments: row.payments?.map((payment: any) => this.formatPayment(payment)) ?? [],
    };
  }

  private formatPeerReceivable(row: any) {
    return {
      id: row.id,
      debtor: row.debtor,
      reference: row.reference,
      description: row.description,
      originalAmount: this.money(row.originalAmount),
      outstandingAmount: this.money(row.outstandingAmount),
      dueDate: row.dueDate,
      status: row.status,
      createdAt: row.createdAt,
      payments: row.payments?.map((payment: any) => this.formatPayment(payment)) ?? [],
    };
  }

  private formatPayment(payment: any) {
    return {
      id: payment.id,
      receivableId: payment.receivableId,
      amount: this.money(payment.amount),
      method: payment.method,
      reference: payment.reference ?? null,
      notes: payment.notes ?? null,
      paidAt: payment.paidAt ?? payment.createdAt,
      createdAt: payment.createdAt,
    };
  }

  private money(value: Prisma.Decimal | number | null | undefined): number {
    return Number(value ?? 0);
  }
}
