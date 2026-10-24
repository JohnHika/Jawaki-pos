import { Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

@Injectable()
export class MpesaService {
  constructor(private readonly prisma: PrismaService) {}

  async history(tenantId: string) {
    const rows = await this.prisma.mpesaEntry.findMany({
      where: { tenantId, status: 'MATCHED' },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return rows.map((r) => ({
      code: r.code,
      amount: Number(r.amount),
      senderName: r.senderName,
      paidAt: r.paidAt,
      createdAt: r.createdAt,
      customerId: r.matchedCustomerId,
      debtorId: r.matchedDebtorId,
    }));
  }
}
