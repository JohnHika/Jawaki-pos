import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';

export type AuditCategory = 'AUTH' | 'TEAM' | 'TENANT' | 'BILLING' | 'LICENSE' | 'SECURITY';
export type AuditSeverity = 'INFO' | 'WARN' | 'CRITICAL';

export interface RequestContext {
  ip?: string;
  userAgent?: string;
}

export interface PlatformActor {
  id: string;
  email: string;
  name?: string;
  role: string;
  permissions: string[];
  sessionId: string;
}

export interface PlatformAuditEntry {
  action: string;
  category: AuditCategory;
  severity?: AuditSeverity;
  actor?: { id?: string | null; email?: string | null; role?: string | null } | null;
  targetType?: string | null;
  targetId?: string | null;
  tenantId?: string | null;
  summary?: string | null;
  metadata?: Record<string, unknown> | null;
  ctx?: RequestContext;
}

export function contextFromRequest(req: any): RequestContext {
  const fwd = req?.headers?.['x-forwarded-for'];
  const first = typeof fwd === 'string' ? fwd.split(',')[0].trim() : undefined;
  const ua = req?.headers?.['user-agent'];
  return {
    ip: first || req?.ip || req?.socket?.remoteAddress || undefined,
    userAgent: typeof ua === 'string' ? ua.slice(0, 300) : undefined,
  };
}

export interface AuditQuery {
  category?: string;
  severity?: string;
  actorId?: string;
  tenantId?: string;
  action?: string;
  search?: string;
  since?: string;
  page?: number;
  pageSize?: number;
}

@Injectable()
export class PlatformAuditService {
  private readonly logger = new Logger(PlatformAuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  /** Never throws: a failed audit write must not break the action it describes. */
  async log(entry: PlatformAuditEntry): Promise<void> {
    try {
      await this.prisma.platformAuditLog.create({
        data: {
          action: entry.action,
          category: entry.category,
          severity: entry.severity ?? 'INFO',
          actorId: entry.actor?.id ?? null,
          actorEmail: entry.actor?.email ?? null,
          actorRole: entry.actor?.role ?? null,
          targetType: entry.targetType ?? null,
          targetId: entry.targetId ?? null,
          tenantId: entry.tenantId ?? null,
          summary: entry.summary ?? null,
          metadata: (entry.metadata ?? undefined) as any,
          ipAddress: entry.ctx?.ip ?? null,
          userAgent: entry.ctx?.userAgent ?? null,
        },
      });
    } catch (error) {
      this.logger.error(
        `Failed to write platform audit (${entry.action}): ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  async list(query: AuditQuery) {
    const page = Math.max(query.page ?? 1, 1);
    const pageSize = Math.min(Math.max(query.pageSize ?? 30, 1), 100);
    const where: any = {};
    if (query.category) where.category = query.category;
    if (query.severity) where.severity = query.severity;
    if (query.actorId) where.actorId = query.actorId;
    if (query.tenantId) where.tenantId = query.tenantId;
    if (query.action) where.action = query.action;
    if (query.since) {
      const d = new Date(query.since);
      if (!Number.isNaN(d.getTime())) where.createdAt = { gte: d };
    }
    if (query.search) {
      where.OR = [
        { summary: { contains: query.search, mode: 'insensitive' } },
        { actorEmail: { contains: query.search, mode: 'insensitive' } },
        { action: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    const [items, total] = await Promise.all([
      this.prisma.platformAuditLog.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.platformAuditLog.count({ where }),
    ]);

    return { items, total, page, pageSize, totalPages: Math.ceil(total / pageSize) };
  }
}
