import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { StockMovementType } from '@prisma/client';
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
    const now = new Date();
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
}
