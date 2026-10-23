import { Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { DebtCollectionService } from './debt-collection.service';
import { DebtorCandidate, Suggestion, rankCandidates } from './mpesa.match';
import { parseMpesaText } from './mpesa.parse';
import { ApplyMpesaDto, IgnoreMpesaDto } from './dto/mpesa.dto';

export interface MpesaPreviewEntry {
  code: string;
  amount: number;
  senderName: string | null;
  senderPhone: string | null;
  paidAt: Date | null;
  state: 'NEW' | 'RECORDED' | 'IGNORED';
  claimId: string | null;
  suggestions: Suggestion[];
}

@Injectable()
export class MpesaService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly collections: DebtCollectionService,
  ) {}

  /** Everyone who currently owes this company money, with their phone for matching. */
  private async candidates(tenantId: string): Promise<DebtorCandidate[]> {
    const [retail, peer] = await Promise.all([
      this.prisma.retailReceivable.groupBy({
        by: ['customerId'],
        where: { tenantId, customerId: { not: null }, status: { in: ['OPEN', 'PARTIAL'] } },
        _sum: { outstandingAmount: true },
      }),
      this.prisma.peerReceivable.groupBy({
        by: ['debtorId'],
        where: { tenantId, status: { in: ['OPEN', 'PARTIAL'] } },
        _sum: { outstandingAmount: true },
      }),
    ]);
    const [customers, debtors] = await Promise.all([
      this.prisma.customer.findMany({
        where: { tenantId, id: { in: retail.map((r) => r.customerId as string) } },
        select: { id: true, name: true, phone: true },
      }),
      this.prisma.peerDebtor.findMany({
        where: { tenantId, id: { in: peer.map((p) => p.debtorId) } },
        select: { id: true, name: true, phone: true },
      }),
    ]);
    const owedByCustomer = new Map(retail.map((r) => [r.customerId as string, Number(r._sum.outstandingAmount ?? 0)]));
    const owedByDebtor = new Map(peer.map((p) => [p.debtorId, Number(p._sum.outstandingAmount ?? 0)]));
    return [
      ...customers.map((c) => ({
        kind: 'CUSTOMER' as const,
        id: c.id,
        name: c.name,
        phone: c.phone,
        outstanding: owedByCustomer.get(c.id) ?? 0,
      })),
      ...debtors.map((d) => ({
        kind: 'SHOP' as const,
        id: d.id,
        name: d.name,
        phone: d.phone,
        outstanding: owedByDebtor.get(d.id) ?? 0,
      })),
    ];
  }

  /** Reads pasted messages and suggests who each payment belongs to. Writes nothing. */
  async preview(tenantId: string, text: string) {
    const parsed = parseMpesaText(text);
    if (parsed.entries.length === 0) {
      return { entries: [] as MpesaPreviewEntry[], skipped: parsed.skipped };
    }
    const codes = parsed.entries.map((e) => e.code);
    const [known, claims, candidates] = await Promise.all([
      this.prisma.mpesaEntry.findMany({ where: { tenantId, code: { in: codes } }, select: { code: true, status: true } }),
      this.prisma.statementClaim.findMany({
        where: { tenantId, status: 'PENDING', mpesaCode: { in: codes } },
        include: { link: { select: { customerId: true, debtorId: true } } },
      }),
      this.candidates(tenantId),
    ]);
    const knownBy = new Map(known.map((k) => [k.code, k.status]));
    const claimBy = new Map(claims.map((c) => [c.mpesaCode as string, c]));

    const entries: MpesaPreviewEntry[] = parsed.entries.map((entry) => {
      const status = knownBy.get(entry.code);
      const claim = claimBy.get(entry.code);
      const claimTarget = claim
        ? claim.link.customerId
          ? { kind: 'CUSTOMER' as const, id: claim.link.customerId }
          : { kind: 'SHOP' as const, id: claim.link.debtorId as string }
        : null;
      return {
        ...entry,
        state: status === 'MATCHED' ? 'RECORDED' : status === 'IGNORED' ? 'IGNORED' : 'NEW',
        claimId: claim?.id ?? null,
        suggestions: status ? [] : rankCandidates(entry, candidates, claimTarget),
      };
    });
    return { entries, skipped: parsed.skipped };
  }

  /** Records the payments the owner confirmed. Each item succeeds or fails on its own. */
  async apply(userId: string, tenantId: string, dto: ApplyMpesaDto) {
    const results: {
      code: string;
      ok: boolean;
      applied: number;
      unallocated: number;
      message: string | null;
    }[] = [];

    for (const item of dto.items) {
      const code = item.code.toUpperCase();
      if (!item.customerId === !item.debtorId) {
        results.push({ code, ok: false, applied: 0, unallocated: 0, message: 'Pick a customer or a shop' });
        continue;
      }
      const outstanding = await this.collections.outstandingFor(tenantId, {
        customerId: item.customerId,
        debtorId: item.debtorId,
      });
      if (outstanding <= 0) {
        results.push({ code, ok: false, applied: 0, unallocated: item.amount, message: 'Nothing is owed by them' });
        continue;
      }

      // Claiming the code first is what stops one payment clearing two debts.
      try {
        await this.prisma.mpesaEntry.create({
          data: {
            tenantId,
            code,
            amount: item.amount,
            senderName: item.senderName?.trim() || null,
            senderPhone: item.senderPhone?.trim() || null,
            paidAt: item.paidAt ? new Date(item.paidAt) : null,
            status: 'MATCHED',
            matchedCustomerId: item.customerId ?? null,
            matchedDebtorId: item.debtorId ?? null,
            createdById: userId,
          },
        });
      } catch (error: any) {
        if (error?.code === 'P2002') {
          results.push({ code, ok: false, applied: 0, unallocated: 0, message: 'This M-Pesa code was already recorded' });
          continue;
        }
        throw error;
      }

      try {
        const paid = await this.collections.applyPayment({
          tenantId,
          userId,
          target: { customerId: item.customerId, debtorId: item.debtorId },
          amount: item.amount,
          method: 'MPESA',
          reference: code,
          notes: 'Matched from pasted M-Pesa messages',
          idempotencyKey: `mpesa:${code}`,
        });
        await this.prisma.statementClaim.updateMany({
          where: { tenantId, mpesaCode: code, status: 'PENDING' },
          data: { status: 'CONFIRMED', decidedAt: new Date(), decidedById: userId, amount: paid.applied },
        });
        await this.audit.record({
          userId,
          action: 'MPESA_PAYMENT_MATCHED',
          entityType: 'MpesaEntry',
          entityId: code,
          newValues: { code, applied: paid.applied, customerId: item.customerId, debtorId: item.debtorId },
        });
        results.push({
          code,
          ok: true,
          applied: paid.applied,
          unallocated: paid.unallocated,
          message: paid.unallocated > 0 ? `KES ${paid.unallocated} was more than they owed` : null,
        });
      } catch (error) {
        // Give the code back so the owner can try again.
        await this.prisma.mpesaEntry.deleteMany({ where: { tenantId, code, status: 'MATCHED' } });
        results.push({ code, ok: false, applied: 0, unallocated: 0, message: 'Could not record the payment. Try again.' });
      }
    }
    return { results };
  }

  /** Marks payments that are not debt payments (a sale, a deposit) so they stop appearing. */
  async ignore(userId: string, tenantId: string, dto: IgnoreMpesaDto) {
    let ignored = 0;
    for (const item of dto.items) {
      try {
        await this.prisma.mpesaEntry.create({
          data: {
            tenantId,
            code: item.code.toUpperCase(),
            amount: item.amount,
            senderName: item.senderName?.trim() || null,
            senderPhone: item.senderPhone?.trim() || null,
            status: 'IGNORED',
            createdById: userId,
          },
        });
        ignored++;
      } catch (error: any) {
        if (error?.code !== 'P2002') throw error;
      }
    }
    return { ignored };
  }

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
