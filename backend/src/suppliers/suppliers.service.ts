import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CashFlowService } from '../cash-flow/cash-flow.service';
import { CashEntryType } from '../cash-flow/dto/cash-flow.dto';
import {
  CreateSupplierDto,
  CreateSupplierInvoiceDto,
  RecordSupplierPaymentDto,
  SupplierInvoiceStatus,
  CashFundingSource,
} from './dto/suppliers.dto';
import { StockMovementType } from '@prisma/client';

@Injectable()
export class SuppliersService {
  constructor(
    private prisma: PrismaService,
    private auditService: AuditService,
    private cashFlowService: CashFlowService,
  ) {}

  async createSupplier(tenantId: string, dto: CreateSupplierDto) {
    const supplier = await this.prisma.supplier.upsert({
      where: { tenantId_name: { tenantId, name: dto.name } },
      create: { tenantId, ...dto },
      update: {
        contactName: dto.contactName,
        phone: dto.phone,
        email: dto.email,
        address: dto.address,
      },
    });
    return supplier;
  }

  async getSuppliers(tenantId: string) {
    return this.prisma.supplier.findMany({
      where: { tenantId, isActive: true },
      orderBy: { name: 'asc' },
    });
  }

  /**
   * Mirrors the aggregate query the mobile Finance screen used to run
   * locally against its own Drift database — now a single source of
   * truth per tenant instead of one private ledger per phone.
   */
  async getSupplierDebts(tenantId: string) {
    const suppliers = await this.prisma.supplier.findMany({
      where: { tenantId, isActive: true },
      include: {
        invoices: { select: { totalAmount: true, paidAmount: true, status: true, dueDate: true } },
        payments: { select: { amount: true, paidAt: true } },
      },
      orderBy: { name: 'asc' },
    });

    const now = new Date();
    return suppliers.map((s) => {
      const totalInvoiced = s.invoices.reduce((sum, inv) => sum + Number(inv.totalAmount), 0);
      const totalPaid = s.payments.reduce((sum, p) => sum + Number(p.amount), 0);
      const overdueCount = s.invoices.filter(
        (inv) => inv.status !== SupplierInvoiceStatus.PAID && inv.dueDate && inv.dueDate < now,
      ).length;
      const lastPayment = s.payments.reduce<Date | null>(
        (latest, p) => (!latest || p.paidAt > latest ? p.paidAt : latest),
        null,
      );

      return {
        id: s.id,
        name: s.name,
        phone: s.phone ?? '',
        email: s.email ?? '',
        totalInvoiced,
        totalPaid,
        totalOwed: Math.max(totalInvoiced - totalPaid, 0),
        invoiceCount: s.invoices.length,
        overdueCount,
        lastPaymentDate: lastPayment,
      };
    });
  }

  async getSupplierInvoices(tenantId: string, supplierId: string) {
    const supplier = await this.prisma.supplier.findFirst({ where: { id: supplierId, tenantId } });
    if (!supplier) throw new NotFoundException('Supplier not found');

    const invoices = await this.prisma.supplierInvoice.findMany({
      where: { supplierId },
      include: { items: true },
      orderBy: { createdAt: 'desc' },
    });

    return invoices.map((invoice) => this.formatInvoice(invoice));
  }

  /**
   * Prisma Decimal fields serialize to JSON as strings, not numbers — every
   * other service in this codebase calls Number() before returning money
   * fields to clients (see ExpensesService.formatExpense) so mobile can
   * read them as plain numbers without defensive parsing.
   */
  private formatInvoice(invoice: any) {
    return {
      ...invoice,
      subtotal: Number(invoice.subtotal),
      paidAmount: Number(invoice.paidAmount),
      totalAmount: Number(invoice.totalAmount),
      dueAmount: Number(invoice.dueAmount),
      items: invoice.items?.map((item: any) => ({
        ...item,
        quantity: Number(item.quantity),
        unitCost: Number(item.unitCost),
        lineTotal: Number(item.lineTotal),
      })),
    };
  }

  /**
   * The one entry point for "I bought stock from a supplier." Unlike the
   * old device-local mobile flow, this always writes a real StockMovement
   * and bumps Stock.quantity for any line matched to a productId — the
   * same effect batch_receive_screen.dart already gets via receiveBatches().
   * If fundingSource is CASH_TILL, the paid portion is also logged as a
   * RESTOCK_OUT cash ledger entry; unpaid balance just sits in dueAmount
   * until a later SupplierPayment is recorded against it.
   */
  async createInvoice(userId: string, tenantId: string, dto: CreateSupplierInvoiceDto) {
    const branch = await this.prisma.branch.findFirst({ where: { id: dto.branchId, tenantId } });
    if (!branch) throw new NotFoundException('Branch not found');

    if (dto.offlineId) {
      const existing = await this.prisma.supplierInvoice.findUnique({ where: { offlineId: dto.offlineId } });
      if (existing) return this.getInvoice(existing.id, tenantId);
    }

    const subtotal = dto.items.reduce((sum, item) => sum + item.quantity * item.unitCost, 0);
    const totalAmount = subtotal;
    const paidAmount = dto.paidAmount ?? 0;
    if (paidAmount > totalAmount) {
      throw new BadRequestException('Paid amount cannot exceed invoice total');
    }
    const dueAmount = totalAmount - paidAmount;
    const status =
      dueAmount <= 0 ? SupplierInvoiceStatus.PAID : paidAmount > 0 ? SupplierInvoiceStatus.PARTIAL : SupplierInvoiceStatus.OPEN;
    const fundingSource = dto.fundingSource ?? CashFundingSource.CASH_TILL;

    const invoice = await this.prisma.$transaction(async (tx) => {
      const supplier = await tx.supplier.upsert({
        where: { tenantId_name: { tenantId, name: dto.supplierName } },
        create: { tenantId, name: dto.supplierName, phone: dto.supplierPhone },
        update: dto.supplierPhone ? { phone: dto.supplierPhone } : {},
      });

      const newInvoice = await tx.supplierInvoice.create({
        data: {
          tenantId,
          branchId: dto.branchId,
          supplierId: supplier.id,
          invoiceNumber: dto.invoiceNumber,
          receiptImageUrl: dto.receiptImageUrl,
          subtotal,
          paidAmount,
          totalAmount,
          dueAmount,
          dueDate: dto.dueDate ? new Date(dto.dueDate) : null,
          status,
          fundingSource,
          offlineId: dto.offlineId,
          createdById: userId,
        },
      });

      await tx.supplierInvoiceItem.createMany({
        data: dto.items.map((item) => ({
          invoiceId: newInvoice.id,
          productId: item.productId,
          productName: item.productName,
          quantity: item.quantity,
          unit: item.unit ?? 'piece',
          unitCost: item.unitCost,
          lineTotal: item.quantity * item.unitCost,
        })),
      });

      // Bump real stock + record a StockMovement for every line matched to a
      // catalog product. Unmatched lines (e.g. brand-new items from OCR) are
      // still recorded on the invoice but don't move inventory until the
      // product is created and reconciled separately.
      for (const item of dto.items) {
        if (!item.productId) continue;

        const stock = await tx.stock.upsert({
          where: { branchId_productId: { branchId: dto.branchId, productId: item.productId } },
          create: { branchId: dto.branchId, productId: item.productId, quantity: item.quantity },
          update: { quantity: { increment: item.quantity } },
        });
        const previousQty = Number(stock.quantity) - item.quantity;

        await tx.stockMovement.create({
          data: {
            branchId: dto.branchId,
            productId: item.productId,
            type: StockMovementType.PURCHASE,
            quantity: item.quantity,
            previousQty,
            newQty: Number(stock.quantity),
            reference: newInvoice.id,
            notes: `Supplier invoice from ${dto.supplierName}`,
            createdById: userId,
          },
        });
      }

      if (paidAmount > 0) {
        await tx.supplierPayment.create({
          data: {
            supplierId: supplier.id,
            invoiceId: newInvoice.id,
            amount: paidAmount,
            notes: `Initial payment for invoice ${dto.invoiceNumber ?? newInvoice.id}`,
            createdById: userId,
          },
        });
      }

      return newInvoice;
    });

    if (paidAmount > 0 && fundingSource === CashFundingSource.CASH_TILL) {
      await this.cashFlowService.recordEntry({
        branchId: dto.branchId,
        type: CashEntryType.RESTOCK_OUT,
        amount: -paidAmount,
        referenceType: 'supplier_invoice',
        referenceId: invoice.id,
        note: `Restock from ${dto.supplierName}`,
        createdById: userId,
      });
    }

    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'supplier_invoice',
      entityId: invoice.id,
      newValues: { totalAmount, paidAmount, dueAmount, fundingSource },
    });

    return this.getInvoice(invoice.id, tenantId);
  }

  async getInvoice(invoiceId: string, tenantId: string) {
    const invoice = await this.prisma.supplierInvoice.findFirst({
      where: { id: invoiceId, tenantId },
      include: { items: true, supplier: true },
    });
    if (!invoice) throw new NotFoundException('Supplier invoice not found');
    return this.formatInvoice(invoice);
  }

  /**
   * Records a payment against an invoice's outstanding balance. Only this
   * later payment — not the invoice creation — moves cash when the invoice
   * was originally taken on credit (fundingSource CREDIT_SUPPLIER).
   */
  async recordPayment(userId: string, tenantId: string, invoiceId: string, dto: RecordSupplierPaymentDto) {
    const invoice = await this.prisma.supplierInvoice.findFirst({ where: { id: invoiceId, tenantId } });
    if (!invoice) throw new NotFoundException('Supplier invoice not found');

    const currentDue = Number(invoice.dueAmount);
    if (dto.amount > currentDue) {
      throw new BadRequestException('Payment amount exceeds outstanding balance');
    }

    const newPaidAmount = Number(invoice.paidAmount) + dto.amount;
    const newDueAmount = currentDue - dto.amount;
    const newStatus =
      newDueAmount <= 0 ? SupplierInvoiceStatus.PAID : SupplierInvoiceStatus.PARTIAL;

    const payment = await this.prisma.$transaction(async (tx) => {
      const created = await tx.supplierPayment.create({
        data: {
          supplierId: invoice.supplierId,
          invoiceId: invoice.id,
          amount: dto.amount,
          notes: dto.notes,
          createdById: userId,
        },
      });

      await tx.supplierInvoice.update({
        where: { id: invoice.id },
        data: { paidAmount: newPaidAmount, dueAmount: newDueAmount, status: newStatus },
      });

      return created;
    });

    const fundingSource = dto.fundingSource ?? CashFundingSource.CASH_TILL;
    if (fundingSource === CashFundingSource.CASH_TILL) {
      await this.cashFlowService.recordEntry({
        branchId: invoice.branchId,
        type: CashEntryType.RESTOCK_OUT,
        amount: -dto.amount,
        referenceType: 'supplier_payment',
        referenceId: payment.id,
        note: dto.notes,
        createdById: userId,
      });
    }

    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'supplier_payment',
      entityId: payment.id,
      newValues: { amount: dto.amount, invoiceId: invoice.id, fundingSource },
    });

    return payment;
  }
}
