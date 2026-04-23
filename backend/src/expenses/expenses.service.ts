import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import {
  CreateExpenseDto,
  UpdateExpenseDto,
  ExpenseQueryDto,
  CreateExpenseWithItemsDto,
  ExpenseStatus,
  ExpenseCategory,
} from './dto/expenses.dto';

@Injectable()
export class ExpensesService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
  ) {}

  async createExpense(userId: string, tenantId: string, dto: CreateExpenseDto) {
    // Validate branch belongs to tenant
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    // Check for duplicate offline ID
    if (dto.offlineId) {
      const existing = await this.prisma.expense.findUnique({
        where: { offlineId: dto.offlineId },
      });
      if (existing) {
        return this.getExpense(existing.id, tenantId);
      }
    }

    // Generate expense number
    const expenseNumber = await this.generateExpenseNumber(dto.branchId);

    // Create expense
    const expense = await this.prisma.expense.create({
      data: {
        expenseNumber,
        category: dto.category,
        amount: dto.amount,
        branchId: dto.branchId,
        supplier: dto.supplier,
        reference: dto.reference,
        description: dto.description,
        date: new Date(dto.date),
        paymentMethod: dto.paymentMethod,
        notes: dto.notes,
        receiptImages: dto.receiptImages,
        status: ExpenseStatus.PENDING,
        createdById: userId,
        offlineId: dto.offlineId,
      },
      include: {
        branch: { select: { name: true } },
        createdBy: { select: { firstName: true, lastName: true } },
      },
    });

    return this.formatExpense(expense);
  }

  async createExpenseWithItems(
    userId: string,
    tenantId: string,
    dto: CreateExpenseWithItemsDto,
  ) {
    // Validate branch
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    // Calculate total from items
    const totalAmount = dto.items.reduce(
      (sum, item) => sum + item.quantity * item.unitPrice,
      0,
    );

    // Generate expense number
    const expenseNumber = await this.generateExpenseNumber(dto.branchId);

    // Create expense with items
    const expense = await this.prisma.$transaction(async (tx) => {
      const newExpense = await tx.expense.create({
        data: {
          expenseNumber,
          category: dto.category,
          amount: totalAmount,
          branchId: dto.branchId,
          supplier: dto.supplier,
          reference: dto.reference,
          description: `${dto.items.length} items from ${dto.supplier}`,
          date: new Date(dto.date),
          paymentMethod: dto.paymentMethod,
          notes: dto.notes,
          status: ExpenseStatus.PENDING,
          createdById: userId,
          offlineId: dto.offlineId,
        },
        include: {
          branch: { select: { name: true } },
          createdBy: { select: { firstName: true, lastName: true } },
        },
      });

      // Create expense items
      await tx.expenseItem.createMany({
        data: dto.items.map((item) => ({
          expenseId: newExpense.id,
          description: item.description,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          total: item.quantity * item.unitPrice,
        })),
      });

      return tx.expense.findUnique({
        where: { id: newExpense.id },
        include: {
          branch: { select: { name: true } },
          createdBy: { select: { firstName: true, lastName: true } },
          items: true,
        },
      });
    });

    return this.formatExpense(expense, true);
  }

  async getExpenses(tenantId: string, query: ExpenseQueryDto) {
    const { branchId, category, status, startDate, endDate, page = 1, limit = 50 } = query;
    const skip = (page - 1) * limit;

    const where: any = {
      branch: { tenantId },
    };

    if (branchId) where.branchId = branchId;
    if (category) where.category = category;
    if (status) where.status = status;

    if (startDate || endDate) {
      where.date = {};
      if (startDate) where.date.gte = new Date(startDate);
      if (endDate) where.date.lte = new Date(endDate);
    }

    const [expenses, total] = await Promise.all([
      this.prisma.expense.findMany({
        where,
        include: {
          branch: { select: { name: true } },
          createdBy: { select: { firstName: true, lastName: true } },
          approvedBy: { select: { firstName: true, lastName: true } },
        },
        orderBy: { date: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.expense.count({ where }),
    ]);

    return {
      items: expenses.map((e) => this.formatExpense(e)),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async getExpense(expenseId: string, tenantId: string) {
    const expense = await this.prisma.expense.findFirst({
      where: {
        id: expenseId,
        branch: { tenantId },
      },
      include: {
        branch: { select: { name: true, code: true } },
        createdBy: { select: { firstName: true, lastName: true, email: true } },
        approvedBy: { select: { firstName: true, lastName: true } },
        items: true,
      },
    });

    if (!expense) {
      throw new NotFoundException('Expense not found');
    }

    return this.formatExpense(expense, true);
  }

  async updateExpense(
    expenseId: string,
    userId: string,
    tenantId: string,
    dto: UpdateExpenseDto,
  ) {
    const expense = await this.prisma.expense.findFirst({
      where: {
        id: expenseId,
        branch: { tenantId },
      },
    });

    if (!expense) {
      throw new NotFoundException('Expense not found');
    }

    // Only allow updates to pending expenses
    if (expense.status !== ExpenseStatus.PENDING) {
      throw new BadRequestException(
        'Cannot update approved, paid, or rejected expenses',
      );
    }

    // Validate supplier if changed
    if (dto.supplier && dto.supplier !== expense.supplier) {
      // Could add supplier validation here
    }

    const updated = await this.prisma.expense.update({
      where: { id: expenseId },
      data: {
        ...dto,
        date: dto.date ? new Date(dto.date) : undefined,
      },
      include: {
        branch: { select: { name: true } },
        createdBy: { select: { firstName: true, lastName: true } },
      },
    });

    return this.formatExpense(updated);
  }

  async approveExpense(
    expenseId: string,
    userId: string,
    tenantId: string,
    notes?: string,
  ) {
    const expense = await this.prisma.expense.findFirst({
      where: {
        id: expenseId,
        branch: { tenantId },
      },
    });

    if (!expense) {
      throw new NotFoundException('Expense not found');
    }

    if (expense.status !== ExpenseStatus.PENDING) {
      throw new BadRequestException('Only pending expenses can be approved');
    }

    const updated = await this.prisma.expense.update({
      where: { id: expenseId },
      data: {
        status: ExpenseStatus.APPROVED,
        approvedById: userId,
        approvedAt: new Date(),
        notes: notes ? `${expense.notes || ''}\nApproved: ${notes}` : expense.notes,
      },
      include: {
        branch: { select: { name: true } },
        createdBy: { select: { firstName: true, lastName: true } },
        approvedBy: { select: { firstName: true, lastName: true } },
      },
    });

    return this.formatExpense(updated);
  }

  async rejectExpense(
    expenseId: string,
    userId: string,
    tenantId: string,
    reason: string,
  ) {
    const expense = await this.prisma.expense.findFirst({
      where: {
        id: expenseId,
        branch: { tenantId },
      },
    });

    if (!expense) {
      throw new NotFoundException('Expense not found');
    }

    if (expense.status !== ExpenseStatus.PENDING) {
      throw new BadRequestException('Only pending expenses can be rejected');
    }

    const updated = await this.prisma.expense.update({
      where: { id: expenseId },
      data: {
        status: ExpenseStatus.REJECTED,
        approvedById: userId,
        approvedAt: new Date(),
        notes: `${expense.notes || ''}\nRejected: ${reason}`,
      },
      include: {
        branch: { select: { name: true } },
        createdBy: { select: { firstName: true, lastName: true } },
        approvedBy: { select: { firstName: true, lastName: true } },
      },
    });

    return this.formatExpense(updated);
  }

  async markAsPaid(expenseId: string, userId: string, tenantId: string) {
    const expense = await this.prisma.expense.findFirst({
      where: {
        id: expenseId,
        branch: { tenantId },
      },
    });

    if (!expense) {
      throw new NotFoundException('Expense not found');
    }

    if (expense.status !== ExpenseStatus.APPROVED) {
      throw new BadRequestException('Only approved expenses can be marked as paid');
    }

    const updated = await this.prisma.expense.update({
      where: { id: expenseId },
      data: {
        status: ExpenseStatus.PAID,
      },
      include: {
        branch: { select: { name: true } },
        createdBy: { select: { firstName: true, lastName: true } },
      },
    });

    return this.formatExpense(updated);
  }

  async deleteExpense(expenseId: string, userId: string, tenantId: string) {
    const expense = await this.prisma.expense.findFirst({
      where: {
        id: expenseId,
        branch: { tenantId },
      },
    });

    if (!expense) {
      throw new NotFoundException('Expense not found');
    }

    // Only allow deletion of pending expenses
    if (expense.status !== ExpenseStatus.PENDING) {
      throw new BadRequestException('Cannot delete non-pending expenses');
    }

    // Check if user created this expense or has admin role
    if (expense.createdById !== userId) {
      // Could add role-based check here
    }

    await this.prisma.expense.delete({
      where: { id: expenseId },
    });

    return { success: true, message: 'Expense deleted successfully' };
  }

  async getSummary(tenantId: string, branchId?: string, startDate?: string, endDate?: string) {
    const branchFilter = branchId ? { branchId } : { branch: { tenantId } };

    const where: any = { ...branchFilter };

    if (startDate || endDate) {
      where.date = {};
      if (startDate) where.date.gte = new Date(startDate);
      if (endDate) where.date.lte = new Date(endDate);
    }

    // Get summary by status
    const statusSummary = await this.prisma.expense.groupBy({
      by: ['status'],
      where,
      _count: { id: true },
      _sum: { amount: true },
    });

    // Get summary by category
    const categorySummary = await this.prisma.expense.groupBy({
      by: ['category'],
      where,
      _count: { id: true },
      _sum: { amount: true },
    });

    // Get summary by branch
    const branchSummary = await this.prisma.expense.groupBy({
      by: ['branchId'],
      where: branchId ? { branchId } : { branch: { tenantId } },
      _count: { id: true },
      _sum: { amount: true },
    });

    // Fetch branch names
    const branchIds = branchSummary.map((b) => b.branchId);
    const branches = await this.prisma.branch.findMany({
      where: { id: { in: branchIds } },
    });
    const branchMap = new Map(branches.map((b) => [b.id, b.name]));

    const totalAmount = statusSummary.reduce(
      (sum, s) => sum + (Number(s._sum.amount) || 0),
      0,
    );

    const statusMap = new Map(
      statusSummary.map((s) => [s.status, { count: s._count.id, amount: Number(s._sum.amount) || 0 }]),
    );

    return {
      totalExpenses: totalAmount,
      pendingCount: statusMap.get(ExpenseStatus.PENDING)?.count || 0,
      pendingAmount: statusMap.get(ExpenseStatus.PENDING)?.amount || 0,
      approvedCount: statusMap.get(ExpenseStatus.APPROVED)?.count || 0,
      approvedAmount: statusMap.get(ExpenseStatus.APPROVED)?.amount || 0,
      paidCount: statusMap.get(ExpenseStatus.PAID)?.count || 0,
      paidAmount: statusMap.get(ExpenseStatus.PAID)?.amount || 0,
      rejectedCount: statusMap.get(ExpenseStatus.REJECTED)?.count || 0,
      rejectedAmount: statusMap.get(ExpenseStatus.REJECTED)?.amount || 0,
      byCategory: categorySummary.map((c) => ({
        category: c.category,
        count: c._count.id,
        amount: Number(c._sum.amount) || 0,
        percentage: totalAmount > 0 ? ((Number(c._sum.amount) || 0) / totalAmount) * 100 : 0,
      })),
      byBranch: branchSummary.map((b) => ({
        branchId: b.branchId,
        branchName: branchMap.get(b.branchId) || 'Unknown',
        amount: Number(b._sum.amount) || 0,
        percentage: totalAmount > 0 ? ((Number(b._sum.amount) || 0) / totalAmount) * 100 : 0,
      })),
    };
  }

  async getTrend(
    tenantId: string,
    startDate: string,
    endDate: string,
    groupBy: 'day' | 'week' | 'month' = 'day',
  ) {
    const expenses = await this.prisma.expense.findMany({
      where: {
        branch: { tenantId },
        date: {
          gte: new Date(startDate),
          lte: new Date(endDate),
        },
      },
      orderBy: { date: 'asc' },
    });

    const groupedData = new Map<string, { amount: number; count: number }>();

    for (const expense of expenses) {
      let periodKey: string;
      const date = new Date(expense.date);

      switch (groupBy) {
        case 'hour':
          periodKey = `${date.toISOString().split('T')[0]} ${date.getHours()}:00`;
          break;
        case 'day':
          periodKey = date.toISOString().split('T')[0];
          break;
        case 'week':
          const weekStart = new Date(date);
          weekStart.setDate(weekStart.getDate() - weekStart.getDay());
          periodKey = `Week of ${weekStart.toISOString().split('T')[0]}`;
          break;
        case 'month':
          periodKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
          break;
        default:
          periodKey = date.toISOString().split('T')[0];
      }

      const existing = groupedData.get(periodKey) || { amount: 0, count: 0 };
      existing.amount += Number(expense.amount);
      existing.count++;
      groupedData.set(periodKey, existing);
    }

    return Array.from(groupedData.entries()).map(([period, data]) => ({
      period,
      amount: data.amount,
      count: data.count,
    }));
  }

  // ==================== HELPERS ====================

  private async generateExpenseNumber(branchId: string): Promise<string> {
    const branch = await this.prisma.branch.findUnique({
      where: { id: branchId },
      select: { code: true },
    });

    const today = new Date();
    const datePrefix = today.toISOString().slice(0, 10).replace(/-/g, '');
    const prefix = `${branch?.code || 'EXP'}-${datePrefix}`;

    // Get count for today
    const key = `expense:${prefix}`;
    let count = await this.redisService.get(key);

    if (!count) {
      // Count from database
      const startOfDay = new Date(today);
      startOfDay.setHours(0, 0, 0, 0);

      const existingCount = await this.prisma.expense.count({
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

  private formatExpense(expense: any, includeItems = false) {
    const result: any = {
      id: expense.id,
      expenseNumber: expense.expenseNumber,
      category: expense.category,
      branchId: expense.branchId,
      branchName: expense.branch?.name,
      supplier: expense.supplier,
      reference: expense.reference,
      description: expense.description,
      amount: Number(expense.amount),
      status: expense.status,
      date: expense.date,
      paymentMethod: expense.paymentMethod,
      notes: expense.notes,
      receiptImages: expense.receiptImages,
      createdById: expense.createdById,
      createdBy: expense.createdBy
        ? `${expense.createdBy.firstName} ${expense.createdBy.lastName}`
        : undefined,
      approvedById: expense.approvedById,
      approvedBy: expense.approvedBy
        ? `${expense.approvedBy.firstName} ${expense.approvedBy.lastName}`
        : undefined,
      approvedAt: expense.approvedAt,
      createdAt: expense.createdAt,
      updatedAt: expense.updatedAt,
    };

    if (includeItems && expense.items) {
      result.items = expense.items.map((item: any) => ({
        id: item.id,
        expenseId: item.expenseId,
        description: item.description,
        quantity: Number(item.quantity),
        unitPrice: Number(item.unitPrice),
        total: Number(item.total),
      }));
    }

    return result;
  }
}
