import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { SaleStatus } from '@prisma/client';
import { ReportFilterDto, ReportPeriod } from '../reporting/dto/reporting.dto';
import { nowInTimezone } from '../common/operating-hours';

@Injectable()
export class CustomersService {
  constructor(private prisma: PrismaService) {}

  /**
   * Minimal start/end computation mirroring ReportingService.getDateRange
   * (getDateRange is private on ReportingService, so it's replicated here).
   */
  private resolveDateRange(filter: ReportFilterDto): { start: Date; end: Date } {
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

    switch (filter.period || ReportPeriod.THIS_MONTH) {
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
      case ReportPeriod.THIS_QUARTER: {
        const quarter = Math.floor(now.getMonth() / 3);
        start = new Date(now.getFullYear(), quarter * 3, 1);
        break;
      }
      case ReportPeriod.THIS_YEAR:
        start = new Date(now.getFullYear(), 0, 1);
        break;
      default:
        start = new Date(now.getFullYear(), now.getMonth(), 1);
    }

    return { start, end };
  }

  /**
   * Top customers by total spend over the period (COMPLETED sales linked to a customer).
   */
  async getTopCustomers(
    tenantId: string,
    filter: ReportFilterDto,
    limit = 10,
  ): Promise<
    Array<{
      customer_id: string;
      name: string;
      phone: string | null;
      total_spent: number;
      order_count: number;
      last_purchase_date: string | null;
    }>
  > {
    const { start, end } = this.resolveDateRange(filter);
    const branchFilter = filter.branchId ? { branchId: filter.branchId } : {};

    const spend = await this.prisma.sale.groupBy({
      by: ['customerId'],
      where: {
        branch: { tenantId },
        ...branchFilter,
        status: SaleStatus.COMPLETED,
        customerId: { not: null },
        createdAt: { gte: start, lte: end },
      },
      _sum: { totalAmount: true },
      _count: { id: true },
      _max: { createdAt: true },
      orderBy: { _sum: { totalAmount: 'desc' } },
      take: limit,
    });

    const customerIds = spend
      .map((s) => s.customerId)
      .filter((id): id is string => id !== null);

    const customers = await this.prisma.customer.findMany({
      where: { id: { in: customerIds }, tenantId },
      select: { id: true, name: true, phone: true },
    });

    const customerMap = new Map(customers.map((c) => [c.id, c]));

    return spend.map((s) => {
      const customer = s.customerId ? customerMap.get(s.customerId) : undefined;
      return {
        customer_id: s.customerId as string,
        name: customer?.name || 'Unknown',
        phone: customer?.phone ?? null,
        total_spent: Number(s._sum.totalAmount) || 0,
        order_count: (s._count as any)?.id ?? 0,
        last_purchase_date: s._max.createdAt
          ? s._max.createdAt.toISOString()
          : null,
      };
    });
  }

  /**
   * Customers whose most recent COMPLETED sale is older than inactiveDays
   * (or who have a customer record but have not purchased within the window).
   */
  async getInactiveCustomers(
    tenantId: string,
    inactiveDays = 60,
    limit = 20,
  ): Promise<
    Array<{
      customer_id: string;
      name: string;
      phone: string | null;
      last_purchase_date: string | null;
      days_since_last_purchase: number | null;
      total_spent: number;
    }>
  > {
    const now = new Date();
    const cutoff = new Date(now);
    cutoff.setDate(cutoff.getDate() - inactiveDays);

    const customers = await this.prisma.customer.findMany({
      where: { tenantId, isActive: true },
      select: { id: true, name: true, phone: true },
    });

    if (customers.length === 0) {
      return [];
    }

    const salesAgg = await this.prisma.sale.groupBy({
      by: ['customerId'],
      where: {
        branch: { tenantId },
        status: SaleStatus.COMPLETED,
        customerId: { in: customers.map((c) => c.id) },
      },
      _max: { createdAt: true },
      _sum: { totalAmount: true },
    });

    const aggMap = new Map(
      salesAgg
        .filter((a) => a.customerId !== null)
        .map((a) => [a.customerId as string, a]),
    );

    return customers
      .map((c) => {
        const agg = aggMap.get(c.id);
        const lastPurchase = agg?._max.createdAt ?? null;
        const daysSinceLastPurchase = lastPurchase
          ? Math.floor(
              (now.getTime() - lastPurchase.getTime()) / (1000 * 60 * 60 * 24),
            )
          : null;
        return {
          customer_id: c.id,
          name: c.name,
          phone: c.phone ?? null,
          last_purchase_date: lastPurchase ? lastPurchase.toISOString() : null,
          days_since_last_purchase: daysSinceLastPurchase,
          total_spent: Number(agg?._sum.totalAmount) || 0,
        };
      })
      // Inactive: never purchased, or last purchase before the cutoff
      .filter(
        (c) =>
          c.last_purchase_date === null ||
          new Date(c.last_purchase_date) < cutoff,
      )
      // Most stale first: never-purchased before recently-purchased, then days desc
      .sort((a, b) => {
        if (
          a.days_since_last_purchase === null &&
          b.days_since_last_purchase === null
        )
          return 0;
        if (a.days_since_last_purchase === null) return -1;
        if (b.days_since_last_purchase === null) return 1;
        return b.days_since_last_purchase - a.days_since_last_purchase;
      })
      .slice(0, limit);
  }

  /**
   * Recent purchase history for a single customer (date, total, item count, payment method).
   */
  async getCustomerPurchaseHistory(
    tenantId: string,
    customerId: string,
    limit = 20,
  ): Promise<{
    customer_id: string;
    name: string;
    phone: string | null;
    email: string | null;
    loyalty_points: number;
    total_spent: number;
    order_count: number;
    recent_sales: Array<{
      sale_id: string;
      date: string;
      total: number;
      item_count: number;
      payment_method: string;
    }>;
  }> {
    const customer = await this.prisma.customer.findFirst({
      where: { id: customerId, tenantId },
      select: {
        id: true,
        name: true,
        phone: true,
        email: true,
        loyaltyPoints: true,
      },
    });

    if (!customer) {
      throw new NotFoundException('Customer not found');
    }

    // Lifetime totals across COMPLETED sales
    const totals = await this.prisma.sale.aggregate({
      where: {
        branch: { tenantId },
        customerId,
        status: SaleStatus.COMPLETED,
      },
      _sum: { totalAmount: true },
      _count: { id: true },
    });

    // Recent sales (any status) with item counts
    const sales = await this.prisma.sale.findMany({
      where: {
        branch: { tenantId },
        customerId,
      },
      include: {
        _count: { select: { items: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    return {
      customer_id: customer.id,
      name: customer.name,
      phone: customer.phone ?? null,
      email: customer.email ?? null,
      loyalty_points: customer.loyaltyPoints,
      total_spent: Number(totals._sum.totalAmount) || 0,
      order_count: (totals._count as any)?.id ?? 0,
      recent_sales: sales.map((s) => ({
        sale_id: s.id,
        date: s.createdAt.toISOString(),
        total: Number(s.totalAmount),
        item_count: s._count.items,
        payment_method: s.paymentMethod,
      })),
    };
  }
}
