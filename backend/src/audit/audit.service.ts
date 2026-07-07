import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditLogQueryDto } from './dto/audit.dto';

export interface RecordAuditParams {
  userId?: string | null;
  action: string;
  entityType: string;
  entityId?: string | null;
  oldValues?: Record<string, unknown> | null;
  newValues?: Record<string, unknown> | null;
}

@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Writes one audit log row. Never throws — a failed audit write must
   * not block the real action it's describing (e.g. a branch update
   * should still succeed even if the audit insert fails for some reason).
   */
  async record(params: RecordAuditParams): Promise<void> {
    try {
      await this.prisma.auditLog.create({
        data: {
          userId: params.userId ?? null,
          action: params.action,
          entityType: params.entityType,
          entityId: params.entityId ?? null,
          oldValues: params.oldValues ? (params.oldValues as any) : undefined,
          newValues: params.newValues ? (params.newValues as any) : undefined,
        },
      });
    } catch (error) {
      this.logger.error(
        `Failed to record audit log (${params.action} ${params.entityType}): ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  /**
   * Lists audit entries for a tenant, newest first. AuditLog has no
   * tenantId column directly — it's scoped by joining through the
   * (optional) user relation, so system-initiated entries with no
   * userId are intentionally excluded from a tenant's view (there's no
   * way to attribute them to a tenant).
   */
  async findAll(tenantId: string, query: AuditLogQueryDto) {
    const { entityType, action, page = 1, limit = 50 } = query;
    const skip = (page - 1) * limit;

    const where: any = {
      user: { tenantId },
    };
    if (entityType) where.entityType = entityType;
    if (action) where.action = action;

    const [entries, total] = await Promise.all([
      this.prisma.auditLog.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
        include: { user: { select: { firstName: true, lastName: true } } },
      }),
      this.prisma.auditLog.count({ where }),
    ]);

    return {
      items: entries.map((entry) => ({
        id: entry.id,
        action: entry.action,
        entityType: entry.entityType,
        entityId: entry.entityId,
        userName: entry.user
          ? `${entry.user.firstName} ${entry.user.lastName}`.trim()
          : null,
        createdAt: entry.createdAt,
      })),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }
}
