import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { getDayBoundsInTimezone, nowInTimezone, todayInTimezone } from '../common/operating-hours';
import { StockMovementType, ExpenseStatus } from '@prisma/client';
import {
  ReportFilterDto,
  ReportPeriod,
  ReportGroupBy,
  SalesSummaryDto,
  SalesTrendDto,
  TopProductDto,
  CategorySalesDto,
  CashierPerformanceDto,
  PaymentMethodBreakdownDto,
  BranchComparisonDto,
  InventoryReportDto,
  StockMovementSummaryDto,
  DashboardSummaryDto,
  DailyProfitAndLossDto,
} from './dto/reporting.dto';

@Injectable()
export class ReportingService {
  private readonly logger = new Logger(ReportingService.name);

  constructor(
    private prisma: PrismaService,
    private redis: RedisService,
  ) {}

  /**
   * Get date range from period or custom dates
   */
  private getDateRange(filter: ReportFilterDto): { start: Date; end: Date } {
    const now = nowInTimezone('Africa/Nairobi');
    let start: Date;
    let end: Date = new Date(now);
    end.setHours(23, 59, 59, 999);

    if (filter.startDate && filter.endDate) {
      return {
        start: new Date(filter.startDate),
        end: new Date(filter.endDate),
      };
    }

    switch (filter.period || ReportPeriod.TODAY) {
      case ReportPeriod.TODAY:
        start = new Date(now);
        start.setHours(0, 0, 0, 0);
        break;
      case ReportPeriod.YESTERDAY:
        start = new Date(now);
        start.setDate(start.getDate() - 1);
        start.setHours(0, 0, 0, 0);
        end = new Date(start);
        end.setHours(23, 59, 59, 999);
        break;
      case ReportPeriod.THIS_WEEK:
        start = new Date(now);
        start.setDate(start.getDate() - start.getDay());
        start.setHours(0, 0, 0, 0);
        break;
      case ReportPeriod.LAST_WEEK:
        start = new Date(now);
        start.setDate(start.getDate() - start.getDay() - 7);
        start.setHours(0, 0, 0, 0);
        end = new Date(start);
        end.setDate(end.getDate() + 6);
        end.setHours(23, 59, 59, 999);
        break;
      case ReportPeriod.THIS_MONTH:
        start = new Date(now.getFullYear(), now.getMonth(), 1);
        break;
      case ReportPeriod.LAST_MONTH:
        start = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        end = new Date(now.getFullYear(), now.getMonth(), 0);
        end.setHours(23, 59, 59, 999);
        break;
      case ReportPeriod.THIS_QUARTER:
        const quarter = Math.floor(now.getMonth() / 3);
        start = new Date(now.getFullYear(), quarter * 3, 1);
        break;
      case ReportPeriod.THIS_YEAR:
        start = new Date(now.getFullYear(), 0, 1);
        break;
      default:
        start = new Date(now);
        start.setHours(0, 0, 0, 0);
    }

    return { start, end };
  }

  /**
   * Get sales summary
   */
  async getSalesSummary(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<SalesSummaryDto> {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId
      ? { branchId: filter.branchId }
      : filter.branchIds
        ? { branchId: { in: filter.branchIds } }
        : {};

    // Get sales aggregates
    const salesAgg = await this.prisma.sale.aggregate({
      where: {
        branch: { tenantId },
        ...branchFilter,
        createdAt: { gte: start, lte: end },
        status: 'COMPLETED',
      },
      _count: { id: true },
      _sum: {
        totalAmount: true,
        discountAmount: true,
        subtotal: true,
      },
      _avg: { totalAmount: true },
    });

    // Get items sold
    const itemsAgg = await this.prisma.saleItem.aggregate({
      where: {
        sale: {
          branch: { tenantId },
          ...branchFilter,
          createdAt: { gte: start, lte: end },
          status: 'COMPLETED',
        },
      },
      _sum: { quantity: true },
    });

    // Get unique customers
    const customersCount = await this.prisma.sale.groupBy({
      by: ['customerId'],
      where: {
        branch: { tenantId },
        ...branchFilter,
        createdAt: { gte: start, lte: end },
        status: 'COMPLETED',
        customerId: { not: null },
      },
    });

    // Get refunds
    const refundsAgg = await this.prisma.sale.aggregate({
      where: {
        branch: { tenantId },
        ...branchFilter,
        createdAt: { gte: start, lte: end },
        status: 'REFUNDED',
      },
      _count: { id: true },
      _sum: { totalAmount: true },
    });

    // Get voided sales
    const voidedAgg = await this.prisma.sale.aggregate({
      where: {
        branch: { tenantId },
        ...branchFilter,
        createdAt: { gte: start, lte: end },
        status: 'VOIDED',
      },
      _count: { id: true },
      _sum: { totalAmount: true },
    });

    return {
      totalSales: (salesAgg._count as any)?.id || salesAgg._count || 0,
      totalRevenue: Number(salesAgg._sum.totalAmount) || 0,
      totalDiscount: Number(salesAgg._sum.discountAmount) || 0,
      netRevenue: Number(salesAgg._sum.subtotal) || 0,
      averageTicket: Number(salesAgg._avg.totalAmount) || 0,
      itemsSold: Number(itemsAgg._sum.quantity) || 0,
      uniqueCustomers: customersCount.length,
      refundsCount: (refundsAgg._count as any)?.id || refundsAgg._count || 0,
      refundsAmount: Number(refundsAgg._sum.totalAmount) || 0,
      voidedSalesCount: (voidedAgg._count as any)?.id || voidedAgg._count || 0,
      voidedSalesAmount: Number(voidedAgg._sum.totalAmount) || 0,
    };
  }

  /**
   * Get sales trend over time
   */
  async getSalesTrend(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<SalesTrendDto[]> {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId ? { branchId: filter.branchId } : {};
    const groupBy = filter.groupBy || ReportGroupBy.DAY;

    // Get all completed sales in date range
    const sales = await this.prisma.sale.findMany({
      where: {
        branch: { tenantId },
        ...branchFilter,
        createdAt: { gte: start, lte: end },
        status: 'COMPLETED',
      },
      include: {
        items: true,
      },
      orderBy: { createdAt: 'asc' },
    });

    // Group by period
    const groupedData = new Map<string, { count: number; revenue: number; items: number }>();

    for (const sale of sales) {
      let periodKey: string;
      const date = new Date(sale.createdAt);

      switch (groupBy) {
        case ReportGroupBy.HOUR:
          periodKey = `${date.toISOString().split('T')[0]} ${date.getHours()}:00`;
          break;
        case ReportGroupBy.DAY:
          periodKey = date.toISOString().split('T')[0];
          break;
        case ReportGroupBy.WEEK:
          const weekStart = new Date(date);
          weekStart.setDate(weekStart.getDate() - weekStart.getDay());
          periodKey = `Week of ${weekStart.toISOString().split('T')[0]}`;
          break;
        case ReportGroupBy.MONTH:
          periodKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
          break;
        default:
          periodKey = date.toISOString().split('T')[0];
      }

      const existing = groupedData.get(periodKey) || { count: 0, revenue: 0, items: 0 };
      existing.count++;
      existing.revenue += Number(sale.totalAmount);
      existing.items += sale.items.reduce((sum, item) => sum + Number(item.quantity), 0);
      groupedData.set(periodKey, existing);
    }

    return Array.from(groupedData.entries()).map(([period, data]) => ({
      period,
      salesCount: data.count,
      revenue: data.revenue,
      itemsSold: data.items,
    }));
  }

  /**
   * Get top selling products
   */
  async getTopProducts(
    tenantId: string,
    filter: ReportFilterDto,
    limit = 10,
  ): Promise<TopProductDto[]> {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId ? { branchId: filter.branchId } : {};

    const topProducts = await this.prisma.saleItem.groupBy({
      by: ['productId'],
      where: {
        sale: {
          branch: { tenantId },
          ...branchFilter,
          createdAt: { gte: start, lte: end },
          status: 'COMPLETED',
        },
      },
      _sum: {
        quantity: true,
        totalAmount: true,
      },
      orderBy: {
        _sum: { totalAmount: 'desc' },
      },
      take: limit,
    });

    // Fetch product details
    const productIds = topProducts.map((p) => p.productId);
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds } },
      include: { categories: { include: { category: true } } },
    });

    const productMap = new Map(products.map((p) => [p.id, p]));

    return topProducts.map((item) => {
      const product = productMap.get(item.productId);
      const firstCategory = product?.categories?.[0]?.category;
      return {
        productId: item.productId,
        productName: product?.name || 'Unknown',
        sku: product?.sku || '',
        categoryName: firstCategory?.name || 'Uncategorized',
        quantitySold: Number(item._sum.quantity) || 0,
        revenue: Number(item._sum.totalAmount) || 0,
        profit: 0, // Would need cost data to calculate
      };
    });
  }

  /**
   * Get sales by category
   */
  async getCategorySales(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<CategorySalesDto[]> {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId ? { branchId: filter.branchId } : {};

    const categorySales = await this.prisma.saleItem.groupBy({
      by: ['productId'],
      where: {
        sale: {
          branch: { tenantId },
          ...branchFilter,
          createdAt: { gte: start, lte: end },
          status: 'COMPLETED',
        },
      },
      _sum: { quantity: true, totalAmount: true },
      _count: { id: true },
    });

    // Get product categories
    const productIds = categorySales.map((s) => s.productId);
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds } },
      include: { categories: { include: { category: true } } },
    });

    const productCategoryMap = new Map(products.map((p) => [p.id, p.categories?.[0]?.category]));

    // Aggregate by category
    const categoryMap = new Map<string, { name: string; count: number; items: number; revenue: number }>();
    let totalRevenue = 0;

    for (const sale of categorySales) {
      const category = productCategoryMap.get(sale.productId);
      const categoryId = category?.id || 'uncategorized';
      const categoryName = category?.name || 'Uncategorized';

      const existing = categoryMap.get(categoryId) || { name: categoryName, count: 0, items: 0, revenue: 0 };
      existing.count += sale._count.id;
      existing.items += Number(sale._sum.quantity) || 0;
      existing.revenue += Number(sale._sum.totalAmount) || 0;
      totalRevenue += Number(sale._sum.totalAmount) || 0;
      categoryMap.set(categoryId, existing);
    }

    return Array.from(categoryMap.entries()).map(([categoryId, data]) => ({
      categoryId,
      categoryName: data.name,
      salesCount: data.count,
      itemsSold: data.items,
      revenue: data.revenue,
      percentage: totalRevenue > 0 ? (data.revenue / totalRevenue) * 100 : 0,
    }));
  }

  /**
   * Get cashier performance
   */
  async getCashierPerformance(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<CashierPerformanceDto[]> {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId ? { branchId: filter.branchId } : {};

    const cashierSales = await this.prisma.sale.groupBy({
      by: ['userId'],
      where: {
        branch: { tenantId },
        ...branchFilter,
        createdAt: { gte: start, lte: end },
        status: 'COMPLETED',
      },
      _count: { id: true },
      _sum: { totalAmount: true },
      _avg: { totalAmount: true },
    });

    // Get user details
    const userIds = cashierSales.map((c) => c.userId);
    const users = await this.prisma.user.findMany({
      where: { id: { in: userIds } },
    });

    const userMap = new Map(users.map((u) => [u.id, u]));

    // Get refunds per cashier
    const refunds = await this.prisma.sale.groupBy({
      by: ['userId'],
      where: {
        branch: { tenantId },
        ...branchFilter,
        createdAt: { gte: start, lte: end },
        status: 'REFUNDED',
      },
      _count: { id: true },
    });

    const refundMap = new Map(refunds.map((r) => [r.userId, r._count.id]));

    return cashierSales.map((c) => {
      const user = userMap.get(c.userId);
      return {
        userId: c.userId,
        name: user ? `${user.firstName} ${user.lastName}` : 'Unknown',
        salesCount: c._count.id,
        revenue: Number(c._sum.totalAmount) || 0,
        itemsSold: 0, // Would need a join to calculate properly
        averageTicket: Number(c._avg.totalAmount) || 0,
        refundsCount: refundMap.get(c.userId) || 0,
      };
    });
  }

  /**
   * Get payment method breakdown
   */
  async getPaymentMethodBreakdown(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<PaymentMethodBreakdownDto[]> {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId ? { branchId: filter.branchId } : {};

    const payments = await this.prisma.payment.groupBy({
      by: ['method'],
      where: {
        sale: {
          branch: { tenantId },
          ...branchFilter,
          createdAt: { gte: start, lte: end },
          status: 'COMPLETED',
        },
        status: 'COMPLETED',
      },
      _count: { id: true },
      _sum: { amount: true },
    });

    const totalAmount = payments.reduce((sum, p) => sum + (Number(p._sum.amount) || 0), 0);

    return payments.map((p) => ({
      method: p.method,
      transactionsCount: p._count.id,
      amount: Number(p._sum.amount) || 0,
      percentage: totalAmount > 0 ? ((Number(p._sum.amount) || 0) / totalAmount) * 100 : 0,
    }));
  }

  /**
   * Get branch comparison
   */
  async getBranchComparison(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<BranchComparisonDto[]> {
    const { start, end } = this.getDateRange(filter);

    const branches = await this.prisma.branch.findMany({
      where: { tenantId, isActive: true },
    });

    const results: BranchComparisonDto[] = [];

    for (const branch of branches) {
      const salesAgg = await this.prisma.sale.aggregate({
        where: {
          branchId: branch.id,
          createdAt: { gte: start, lte: end },
          status: 'COMPLETED',
        },
        _count: { id: true },
        _sum: { totalAmount: true },
        _avg: { totalAmount: true },
      });

      // Get top product for branch
      const topProduct = await this.prisma.saleItem.groupBy({
        by: ['productId'],
        where: {
          sale: {
            branchId: branch.id,
            createdAt: { gte: start, lte: end },
            status: 'COMPLETED',
          },
        },
        _sum: { totalAmount: true },
        orderBy: { _sum: { totalAmount: 'desc' } },
        take: 1,
      });

      let topProductName = 'N/A';
      if (topProduct.length > 0) {
        const product = await this.prisma.product.findUnique({
          where: { id: topProduct[0].productId },
        });
        topProductName = product?.name || 'N/A';
      }

      results.push({
        branchId: branch.id,
        branchName: branch.name,
        salesCount: (salesAgg._count as any)?.id || salesAgg._count || 0,
        revenue: Number(salesAgg._sum.totalAmount) || 0,
        averageTicket: Number(salesAgg._avg.totalAmount) || 0,
        topProduct: topProductName,
      });
    }

    return results.sort((a, b) => b.revenue - a.revenue);
  }

  /**
   * Get inventory report
   */
  async getInventoryReport(
    tenantId: string,
    branchId?: string,
  ): Promise<InventoryReportDto> {
    const branchFilter = branchId ? { branchId } : { branch: { tenantId } };

    // Get all stock for branch(es)
    const stocks = await this.prisma.stock.findMany({
      where: branchFilter,
      include: {
        product: true,
      },
    });

    let totalValue = 0;
    let lowStock = 0;
    let outOfStock = 0;
    let overStock = 0;

    for (const stock of stocks) {
      const qty = Number(stock.quantity);
      totalValue += qty * Number(stock.product.basePrice);

      if (qty <= 0) {
        outOfStock++;
      } else if (qty <= stock.product.minStock) {
        lowStock++;
      }
    }

    return {
      totalProducts: stocks.length,
      totalStockValue: totalValue,
      lowStockItems: lowStock,
      outOfStockItems: outOfStock,
      overStockItems: overStock,
    };
  }

  /**
   * Get stock movement summary
   */
  async getStockMovementSummary(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<StockMovementSummaryDto> {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId
      ? { branchId: filter.branchId }
      : { branch: { tenantId } };

    const movements = await this.prisma.stockMovement.groupBy({
      by: ['type'],
      where: {
        ...branchFilter,
        createdAt: { gte: start, lte: end },
      },
      _sum: { quantity: true },
    });

    const movementMap = new Map(movements.map((m) => [m.type, Number(m._sum.quantity) || 0]));

    return {
      adjustmentsIn: movementMap.get(StockMovementType.ADJUSTMENT_IN) || 0,
      adjustmentsOut: movementMap.get(StockMovementType.ADJUSTMENT_OUT) || 0,
      transfersIn: movementMap.get(StockMovementType.TRANSFER_IN) || 0,
      transfersOut: movementMap.get(StockMovementType.TRANSFER_OUT) || 0,
      salesReductions: movementMap.get(StockMovementType.SALE) || 0,
      refundRestores: movementMap.get(StockMovementType.REFUND) || 0,
    };
  }

  /**
   * Get dashboard summary
   */
  async getDashboardSummary(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<DashboardSummaryDto> {
    const [sales, trend, topProducts, paymentMethods, inventory] = await Promise.all([
      this.getSalesSummary(tenantId, filter),
      this.getSalesTrend(tenantId, { ...filter, groupBy: ReportGroupBy.DAY }),
      this.getTopProducts(tenantId, filter, 5),
      this.getPaymentMethodBreakdown(tenantId, filter),
      this.getInventoryReport(tenantId, filter.branchId),
    ]);

    return {
      sales,
      trend,
      topProducts,
      paymentMethods,
      inventory,
    };
  }

  /**
   * Get daily profit and loss report with expense integration
   */
  async getDailyProfitAndLoss(
    branchId: string,
    date: string,
    tenantId: string,
  ): Promise<DailyProfitAndLossDto> {
    // Get branch info
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
      select: { name: true, timezone: true },
    });

    if (!branch) {
      throw new Error('Branch not found');
    }

    const { start: startOfDay, end: endOfDay } = getDayBoundsInTimezone(
      date,
      branch.timezone ?? 'Africa/Nairobi',
    );

    // Get all completed sales for the day
    const sales = await this.prisma.sale.findMany({
      where: {
        branchId,
        createdAt: { gte: startOfDay, lte: endOfDay },
        status: 'COMPLETED',
      },
      include: {
        items: {
          include: {
            product: {
              select: {
                costPrice: true,
                basePrice: true,
              },
            },
          },
        },
      },
    });

    // Get refunds for the day
    const refunds = await this.prisma.refund.findMany({
      where: {
        sale: {
          branchId,
          createdAt: { gte: startOfDay, lte: endOfDay },
        },
      },
    });

    // Get all expenses for the day (approved and paid only for accurate P&L)
    const expenses = await this.prisma.expense.findMany({
      where: {
        branchId,
        date: { gte: startOfDay, lte: endOfDay },
        status: { in: [ExpenseStatus.APPROVED, ExpenseStatus.PAID] },
      },
      include: {
        items: true,
      },
    });

    // Calculate sales metrics
    const grossSales = sales.reduce((sum, s) => sum + Number(s.totalAmount), 0);
    const totalDiscounts = sales.reduce((sum, s) => sum + Number(s.discountAmount), 0);
    const totalTax = sales.reduce((sum, s) => sum + Number(s.taxAmount), 0);
    const netSales = grossSales - totalDiscounts;
    const refundedAmount = refunds.reduce((sum, r) => sum + Number(r.amount), 0);
    const netRevenue = netSales - refundedAmount;

    // Calculate Cost of Goods Sold (COGS)
    let costOfGoodsSold = 0;
    for (const sale of sales) {
      for (const item of sale.items) {
        const productCost = item.product.costPrice
          ? Number(item.product.costPrice)
          : Number(item.product.basePrice) * 0.7; // Fallback: estimate 70% of base price
        costOfGoodsSold += productCost * Number(item.quantity);
      }
    }

    const grossProfit = netRevenue - costOfGoodsSold;
    const grossProfitMargin = netRevenue > 0 ? (grossProfit / netRevenue) * 100 : 0;

    // Calculate expenses by category
    const expensesByCategory: Record<string, number> = {};
    let totalExpenses = 0;

    for (const expense of expenses) {
      totalExpenses += Number(expense.amount);
      const category = expense.category;
      expensesByCategory[category] = (expensesByCategory[category] || 0) + Number(expense.amount);
    }

    // Calculate net profit
    const netProfit = grossProfit - totalExpenses;
    const netProfitMargin = netRevenue > 0 ? (netProfit / netRevenue) * 100 : 0;

    // Transaction metrics
    const transactionCount = sales.length;
    const averageTransactionValue = transactionCount > 0 ? netRevenue / transactionCount : 0;

    return {
      date,
      branchId,
      branchName: branch.name,
      grossSales,
      totalDiscounts,
      totalTax,
      netSales,
      refundedAmount,
      netRevenue,
      costOfGoodsSold,
      grossProfit,
      grossProfitMargin,
      totalExpenses,
      expensesByCategory,
      netProfit,
      netProfitMargin,
      transactionCount,
      averageTransactionValue,
    };
  }

  /**
   * Get profit and loss trend over a date range
   */
  async getProfitAndLossRange(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<DailyProfitAndLossDto[]> {
    const { start, end } = this.getDateRange(filter);

    // Get all branches for the tenant
    const branches = await this.prisma.branch.findMany({
      where: { tenantId, isActive: true },
      select: { id: true },
    });

    const results: DailyProfitAndLossDto[] = [];

    // Iterate through each day in the range
    const currentDate = new Date(start);
    while (currentDate <= end) {
      const dateStr = currentDate.toISOString().split('T')[0];

      // Get aggregated data for all branches for this day
      for (const branch of branches) {
        try {
          const dailyPnL = await this.getDailyProfitAndLoss(
            branch.id,
            dateStr,
            tenantId,
          );
          results.push(dailyPnL);
        } catch (e) {
          // Skip branches/days with no data
        }
      }

      currentDate.setDate(currentDate.getDate() + 1);
    }

    return results;
  }

  /**
   * Get dead / slow-moving stock: products with stock on hand but no sale in the last N days
   */
  async getDeadStock(
    tenantId: string,
    branchId?: string,
    daysWithoutSale = 30,
  ): Promise<
    Array<{
      id: string;
      name: string;
      sku: string;
      currentStock: number;
      stockValue: number;
      lastSoldAt: string | null;
      daysSinceLastSale: number | null;
    }>
  > {
    const now = new Date();
    const cutoff = new Date(now);
    cutoff.setDate(cutoff.getDate() - daysWithoutSale);

    const branchFilter = branchId ? { branchId } : { branch: { tenantId } };

    // Get all stock on hand (quantity > 0) for the branch(es)
    const stocks = await this.prisma.stock.findMany({
      where: {
        ...branchFilter,
        quantity: { gt: 0 },
        product: { tenantId, isActive: true },
      },
      include: {
        product: {
          select: { id: true, name: true, sku: true, basePrice: true },
        },
      },
    });

    // Aggregate stock on hand per product (may span multiple branches)
    const productStock = new Map<
      string,
      { name: string; sku: string; basePrice: number; quantity: number }
    >();

    for (const stock of stocks) {
      const existing = productStock.get(stock.productId);
      if (existing) {
        existing.quantity += Number(stock.quantity);
      } else {
        productStock.set(stock.productId, {
          name: stock.product.name,
          sku: stock.product.sku,
          basePrice: Number(stock.product.basePrice),
          quantity: Number(stock.quantity),
        });
      }
    }

    const productIds = Array.from(productStock.keys());
    if (productIds.length === 0) {
      return [];
    }

    // Find the most recent sale date per product within this tenant.
    // groupBy can't _max a relation field, so read SaleItems newest-first and
    // keep the first (latest) one seen per product.
    const saleFilter = branchId ? { branchId } : { branch: { tenantId } };
    const recentSaleItems = await this.prisma.saleItem.findMany({
      where: {
        productId: { in: productIds },
        sale: {
          ...saleFilter,
          status: 'COMPLETED',
        },
      },
      select: {
        productId: true,
        sale: { select: { createdAt: true } },
      },
      orderBy: { sale: { createdAt: 'desc' } },
    });

    const lastSoldMap = new Map<string, Date>();
    for (const item of recentSaleItems) {
      if (!lastSoldMap.has(item.productId)) {
        lastSoldMap.set(item.productId, item.sale.createdAt);
      }
    }

    // Keep products with no sale in the last N days (never sold, or last sold before cutoff)
    const rows = productIds
      .map((productId) => {
        const info = productStock.get(productId)!;
        const lastSold = lastSoldMap.get(productId) || null;
        const daysSinceLastSale = lastSold
          ? Math.floor((now.getTime() - lastSold.getTime()) / (1000 * 60 * 60 * 24))
          : null;
        return {
          id: productId,
          name: info.name,
          sku: info.sku,
          currentStock: info.quantity,
          stockValue: info.quantity * info.basePrice,
          lastSoldAt: lastSold ? lastSold.toISOString() : null,
          daysSinceLastSale,
        };
      })
      .filter((row) => !lastSoldMap.get(row.id) || lastSoldMap.get(row.id)! < cutoff)
      // Most stale first: never-sold (null) before recently sold, then by daysSinceLastSale desc
      .sort((a, b) => {
        if (a.daysSinceLastSale === null && b.daysSinceLastSale === null) return 0;
        if (a.daysSinceLastSale === null) return -1;
        if (b.daysSinceLastSale === null) return 1;
        return b.daysSinceLastSale - a.daysSinceLastSale;
      })
      .slice(0, 30);

    return rows;
  }

  /**
   * Get profit by product for COMPLETED sales in range (revenue, cost, gross profit, margin)
   */
  async getProfitByProduct(
    tenantId: string,
    filter: ReportFilterDto,
    limit = 10,
  ): Promise<
    Array<{
      productId: string;
      productName: string;
      sku: string;
      quantitySold: number;
      revenue: number;
      cost: number;
      grossProfit: number;
      marginPct: number;
    }>
  > {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId ? { branchId: filter.branchId } : {};

    // Aggregate revenue and quantity per product for completed sales
    const productSales = await this.prisma.saleItem.groupBy({
      by: ['productId'],
      where: {
        sale: {
          branch: { tenantId },
          ...branchFilter,
          createdAt: { gte: start, lte: end },
          status: 'COMPLETED',
        },
      },
      _sum: {
        quantity: true,
        totalAmount: true,
      },
    });

    if (productSales.length === 0) {
      return [];
    }

    // Fetch product cost/base price details
    const productIds = productSales.map((p) => p.productId);
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds } },
      select: { id: true, name: true, sku: true, costPrice: true, basePrice: true },
    });

    const productMap = new Map(products.map((p) => [p.id, p]));

    return productSales
      .map((item) => {
        const product = productMap.get(item.productId);
        const quantitySold = Number(item._sum.quantity) || 0;
        const revenue = Number(item._sum.totalAmount) || 0;
        // Match getDailyProfitAndLoss cost fallback: costPrice, else 70% of base price
        const unitCost = product?.costPrice
          ? Number(product.costPrice)
          : Number(product?.basePrice || 0) * 0.7;
        const cost = unitCost * quantitySold;
        const grossProfit = revenue - cost;
        const marginPct = revenue > 0 ? (grossProfit / revenue) * 100 : 0;
        return {
          productId: item.productId,
          productName: product?.name || 'Unknown',
          sku: product?.sku || '',
          quantitySold,
          revenue,
          cost,
          grossProfit,
          marginPct,
        };
      })
      .sort((a, b) => b.grossProfit - a.grossProfit)
      .slice(0, limit);
  }

  /**
   * Gross profit rolled up by product category. Same COGS convention as
   * getProfitByProduct / getDailyProfitAndLoss (costPrice, else 70% of base
   * price). Products map to their first category via the many-to-many
   * ProductCategory join, falling back to "Uncategorized".
   */
  async getProfitByCategory(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<
    Array<{
      categoryId: string;
      categoryName: string;
      revenue: number;
      cost: number;
      grossProfit: number;
      marginPct: number;
    }>
  > {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId ? { branchId: filter.branchId } : {};

    const productSales = await this.prisma.saleItem.groupBy({
      by: ['productId'],
      where: {
        sale: {
          branch: { tenantId },
          ...branchFilter,
          createdAt: { gte: start, lte: end },
          status: 'COMPLETED',
        },
      },
      _sum: { quantity: true, totalAmount: true },
    });

    if (productSales.length === 0) {
      return [];
    }

    const productIds = productSales.map((s) => s.productId);
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds } },
      select: {
        id: true,
        costPrice: true,
        basePrice: true,
        categories: { include: { category: true } },
      },
    });
    const productMap = new Map(products.map((p) => [p.id, p]));

    const categoryMap = new Map<
      string,
      { name: string; revenue: number; cost: number }
    >();

    for (const item of productSales) {
      const product = productMap.get(item.productId);
      const category = product?.categories?.[0]?.category;
      const categoryId = category?.id || 'uncategorized';
      const categoryName = category?.name || 'Uncategorized';

      const quantitySold = Number(item._sum.quantity) || 0;
      const revenue = Number(item._sum.totalAmount) || 0;
      const unitCost = product?.costPrice
        ? Number(product.costPrice)
        : Number(product?.basePrice || 0) * 0.7;
      const cost = unitCost * quantitySold;

      const existing = categoryMap.get(categoryId) || {
        name: categoryName,
        revenue: 0,
        cost: 0,
      };
      existing.revenue += revenue;
      existing.cost += cost;
      categoryMap.set(categoryId, existing);
    }

    return Array.from(categoryMap.entries())
      .map(([categoryId, data]) => {
        const grossProfit = data.revenue - data.cost;
        return {
          categoryId,
          categoryName: data.name,
          revenue: data.revenue,
          cost: data.cost,
          grossProfit,
          marginPct: data.revenue > 0 ? (grossProfit / data.revenue) * 100 : 0,
        };
      })
      .sort((a, b) => b.grossProfit - a.grossProfit);
  }

  /**
   * Slow-moving / dead stock: products with stock on hand that have NOT sold
   * within `daysWithoutSale` days, sorted by tied-up stock value descending.
   * These are the items quietly holding cash hostage on the shelf.
   */
  async getSlowMovingProducts(
    tenantId: string,
    branchId?: string,
    daysWithoutSale = 30,
    limit = 20,
  ): Promise<
    Array<{
      productId: string;
      name: string;
      sku: string;
      category: string;
      remaining_stock: number;
      stock_value: number;
      idle_at_least_days: number;
    }>
  > {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - daysWithoutSale);

    // Products this tenant tracks that currently have stock on hand.
    const products = await this.prisma.product.findMany({
      where: { tenantId, trackInventory: true, isActive: true },
      select: {
        id: true,
        name: true,
        sku: true,
        costPrice: true,
        basePrice: true,
        categories: { include: { category: true } },
        stock: branchId ? { where: { branchId } } : true,
      },
    });

    // In-stock products only.
    const inStock = products
      .map((p) => ({ product: p, remaining: p.stock.reduce((sum, s) => sum + Number(s.quantity), 0) }))
      .filter((x) => x.remaining > 0);

    // Products that HAVE sold within the window — one batched query over the
    // recent completed sales (SaleItem has no timestamp of its own; the date
    // lives on the parent Sale, so we filter on the relation). Any product
    // appearing here is not slow; everything else in stock is.
    const recentlySold = inStock.length
      ? await this.prisma.saleItem.findMany({
          where: {
            productId: { in: inStock.map((x) => x.product.id) },
            sale: {
              branch: { tenantId },
              ...(branchId ? { branchId } : {}),
              status: 'COMPLETED',
              createdAt: { gte: cutoff },
            },
          },
          select: { productId: true },
        })
      : [];
    const soldRecently = new Set(recentlySold.map((r) => r.productId));

    const results = inStock
      .filter(({ product }) => !soldRecently.has(product.id))
      .map(({ product, remaining: remainingStock }) => {
        const unitCost = product.costPrice
          ? Number(product.costPrice)
          : Number(product.basePrice || 0) * 0.7;
        return {
          productId: product.id,
          name: product.name,
          sku: product.sku,
          category: product.categories?.[0]?.category?.name || 'Uncategorized',
          remaining_stock: remainingStock,
          stock_value: unitCost * remainingStock,
          // These products have NOT sold within the last `daysWithoutSale`
          // days — i.e. idle for at least that long. The exact last-sold date
          // is intentionally omitted (would need a per-product query); the
          // tool's value is surfacing the tied-up cash, not precise idle days.
          idle_at_least_days: daysWithoutSale,
        };
      });

    return results
      .sort((a, b) => b.stock_value - a.stock_value)
      .slice(0, limit);
  }

  /**
   * Get sales heatmap: day-of-week (0-6) x hour (0-23) grid of sales counts and revenue
   */
  async getSalesHeatmap(
    tenantId: string,
    filter: ReportFilterDto,
  ): Promise<
    Array<{
      dayOfWeek: number;
      hour: number;
      salesCount: number;
      revenue: number;
    }>
  > {
    const { start, end } = this.getDateRange(filter);
    const branchFilter = filter.branchId ? { branchId: filter.branchId } : {};

    const sales = await this.prisma.sale.findMany({
      where: {
        branch: { tenantId },
        ...branchFilter,
        createdAt: { gte: start, lte: end },
        status: 'COMPLETED',
      },
      select: { createdAt: true, totalAmount: true },
    });

    // Bucket by dayOfWeek + hour
    const grid = new Map<string, { salesCount: number; revenue: number }>();

    for (const sale of sales) {
      const date = new Date(sale.createdAt);
      const dayOfWeek = date.getDay();
      const hour = date.getHours();
      const key = `${dayOfWeek}-${hour}`;
      const existing = grid.get(key) || { salesCount: 0, revenue: 0 };
      existing.salesCount++;
      existing.revenue += Number(sale.totalAmount);
      grid.set(key, existing);
    }

    return Array.from(grid.entries()).map(([key, data]) => {
      const [dayOfWeek, hour] = key.split('-').map(Number);
      return {
        dayOfWeek,
        hour,
        salesCount: data.salesCount,
        revenue: data.revenue,
      };
    });
  }
}
