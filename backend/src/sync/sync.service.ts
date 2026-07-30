import { Injectable, Logger, BadRequestException, ConflictException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { SalesService } from '../sales/sales.service';
import { InventoryService } from '../inventory/inventory.service';
import { SuppliersService } from '../suppliers/suppliers.service';
import { SyncEventStatus, SyncEventType as PrismaSyncEventType } from '@prisma/client';
import {
  SyncEventDto,
  SyncEventType,
  PushSyncEventsDto,
  PushSyncResponseDto,
  SyncResultDto,
  PullSyncRequestDto,
  PullSyncResponseDto,
  SyncStatusDto,
  ConflictResolutionDto,
} from './dto/sync.dto';

type PullCursor = {
  timestamp: Date;
  cutoff: Date;
  eventType?: string;
  entityId?: string;
  composite: boolean;
};

@Injectable()
export class SyncService {
  private readonly logger = new Logger(SyncService.name);

  constructor(
    private prisma: PrismaService,
    private redis: RedisService,
    private salesService: SalesService,
    private inventoryService: InventoryService,
    private suppliersService: SuppliersService,
  ) {}

  /**
   * Push events from offline device to server
   * Processes events idempotently to handle duplicate submissions
   */
  async pushEvents(
    deviceUuid: string | undefined,
    branchId: string,
    dto: PushSyncEventsDto,
  ): Promise<PushSyncResponseDto> {
    const results: SyncResultDto[] = [];
    let successCount = 0;
    let failureCount = 0;
    const normalizedDeviceUuid = this.normalizeDeviceUuid(deviceUuid);
    const device = await this.findDeviceByUuid(normalizedDeviceUuid);
    const deviceRecordId = device?.id;

    if (!normalizedDeviceUuid) {
      this.logger.warn('Sync request received without device UUID; device-level sync tracking will be skipped.');
    } else if (!deviceRecordId) {
      this.logger.warn(`Sync request received for unregistered device UUID ${normalizedDeviceUuid}; device-level sync tracking will be skipped.`);
    }

    // Sort events by sequence number if provided
    const sortedEvents = [...dto.events].sort(
      (a, b) => (a.sequenceNumber || 0) - (b.sequenceNumber || 0),
    );

    for (const event of sortedEvents) {
      try {
        // Check if event was already processed (idempotency)
        const existingEvent = deviceRecordId
          ? await this.prisma.syncEvent.findUnique({
              where: {
                deviceId_eventId: {
                  deviceId: deviceRecordId,
                  eventId: event.eventId,
                },
              },
            })
          : null;

        if (existingEvent) {
          // Event already processed, return success with existing data
          results.push({
            eventId: event.eventId,
            success: true,
            serverId: existingEvent.entityId || undefined,
            serverTimestamp: existingEvent.processedAt || undefined,
          });
          successCount++;
          continue;
        }

        // Process the event based on type
        const result = await this.processEvent(event, branchId, normalizedDeviceUuid || '');
        
        // Get userId from payload or use default
        const userId = event.payload.cashierId || event.payload.createdById || event.payload.userId || '';

        if (deviceRecordId) {
          // Record the sync event when the device is registered
          await this.prisma.syncEvent.create({
            data: {
              deviceId: deviceRecordId,
              branchId,
              userId,
              eventId: event.eventId,
              eventType: event.eventType as unknown as PrismaSyncEventType,
              payload: event.payload,
              entityId: result.serverId,
              entityType: this.getEntityType(event.eventType),
              status: SyncEventStatus.PROCESSED,
              processedAt: new Date(),
              deviceTimestamp: new Date(event.createdAt),
            },
          });
        }

        results.push({
          eventId: event.eventId,
          success: true,
          serverId: result.serverId,
          serverTimestamp: new Date(),
        });
        successCount++;
      } catch (error) {
        this.logger.error(`Failed to process event ${event.eventId}:`, error);
        const errorMessage = error instanceof Error ? error.message : 'Unknown sync processing error';
        
        // Get userId from payload or use default
        const errorUserId = event.payload.cashierId || event.payload.createdById || event.payload.userId || '';

        if (deviceRecordId) {
          // Record failed event for retry using eventId for uniqueness
          await this.prisma.syncEvent.upsert({
            where: {
              deviceId_eventId: { deviceId: deviceRecordId, eventId: event.eventId }
            },
            create: {
              deviceId: deviceRecordId,
              branchId,
              userId: errorUserId,
              eventId: event.eventId,
              eventType: event.eventType as unknown as PrismaSyncEventType,
              payload: event.payload,
              entityType: this.getEntityType(event.eventType),
              status: SyncEventStatus.FAILED,
              errorMessage,
              deviceTimestamp: new Date(event.createdAt),
            },
            update: {
              status: SyncEventStatus.FAILED,
              errorMessage,
              retryCount: { increment: 1 },
            },
          });
        }

        results.push({
          eventId: event.eventId,
          success: false,
          error: errorMessage,
        });
        failureCount++;
      }
    }

    // Update device last sync timestamp
    await this.updateDeviceSyncStatus(normalizedDeviceUuid, 'push');

    return {
      results,
      successCount,
      failureCount,
      serverTimestamp: new Date(),
    };
  }

  /**
   * Pull events from server for offline device
   */
  private parsePullCursor(rawCursor?: string): PullCursor {
    if (!rawCursor) {
      return {
        timestamp: new Date(0),
        cutoff: new Date(),
        composite: false,
      };
    }

    if (rawCursor.startsWith('v1|')) {
      const parts = rawCursor.split('|');
      if (parts.length !== 5) {
        throw new BadRequestException('Invalid sync cursor');
      }

      const cutoff = new Date(parts[1]);
      const timestamp = new Date(parts[2]);
      if (
        Number.isNaN(cutoff.getTime()) ||
        Number.isNaN(timestamp.getTime()) ||
        timestamp > cutoff
      ) {
        throw new BadRequestException('Invalid sync cursor');
      }

      let eventType: string;
      let entityId: string;
      try {
        eventType = decodeURIComponent(parts[3]);
        entityId = decodeURIComponent(parts[4]);
      } catch {
        throw new BadRequestException('Invalid sync cursor');
      }
      if (
        !Object.values(SyncEventType).includes(eventType as SyncEventType) ||
        entityId.length === 0 ||
        entityId.length > 200
      ) {
        throw new BadRequestException('Invalid sync cursor');
      }

      return {
        cutoff,
        timestamp,
        eventType,
        entityId,
        composite: true,
      };
    }

    const timestamp = new Date(rawCursor);
    if (Number.isNaN(timestamp.getTime())) {
      throw new BadRequestException('Invalid sync timestamp');
    }

    return {
      timestamp,
      cutoff: new Date(),
      composite: false,
    };
  }

  private buildCursorWhere(
    timestampField: 'createdAt' | 'updatedAt',
    eventType: SyncEventType,
    cursor: PullCursor,
  ): any[] {
    const afterTimestamp = {
      [timestampField]: { gt: cursor.timestamp, lte: cursor.cutoff },
    };

    if (!cursor.composite) return [afterTimestamp];

    const eventTypeOrder = eventType.localeCompare(cursor.eventType!);
    if (eventTypeOrder < 0) return [afterTimestamp];

    const atBoundary =
      eventTypeOrder > 0
        ? { [timestampField]: cursor.timestamp }
        : {
            [timestampField]: cursor.timestamp,
            id: { gt: cursor.entityId! },
          };

    return [afterTimestamp, atBoundary];
  }

  private encodePullCursor(
    cutoff: Date,
    event: { timestamp: Date; eventType: SyncEventType; entityId: string },
  ): string {
    return [
      'v1',
      cutoff.toISOString(),
      event.timestamp.toISOString(),
      encodeURIComponent(event.eventType),
      encodeURIComponent(event.entityId),
    ].join('|');
  }

  async pullEvents(
    deviceUuid: string | undefined,
    branchId: string,
    dto: PullSyncRequestDto,
  ): Promise<PullSyncResponseDto> {
    const limit = dto.limit || 100;
    const cursor = this.parsePullCursor(dto.since);
    // The encoded cursor carries the original cutoff through every page.
    // Events created during this pull remain newer than that fixed watermark
    // and are collected by the next pull.
    const syncCutoff = cursor.cutoff;

    // Build query for changed entities
    const events: any[] = [];


    // Pull product updates
    if (!dto.eventTypes || dto.eventTypes.includes(SyncEventType.PRODUCT_UPDATED)) {
      const products = await this.prisma.product.findMany({
        where: {
          OR: this.buildCursorWhere(
            'updatedAt',
            SyncEventType.PRODUCT_UPDATED,
            cursor,
          ),
          stock: {
            some: { branchId },
          },
        },
        include: {
          categories: {
            include: { category: true },
          },
          stock: {
            where: { branchId },
          },
          pricingTiers: { orderBy: { sortOrder: 'asc' } },
        },
        take: limit + 1,
        orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
      });

      events.push(
        ...products.map((p) => ({
          eventType: SyncEventType.PRODUCT_UPDATED,
          entityId: p.id,
          payload: p,
          timestamp: p.updatedAt,
        })),
      );
    }

    // Pull category updates
    if (!dto.eventTypes || dto.eventTypes.includes(SyncEventType.CATEGORY_UPDATED)) {
      const categories = await this.prisma.category.findMany({
        where: {
          OR: this.buildCursorWhere(
            'updatedAt',
            SyncEventType.CATEGORY_UPDATED,
            cursor,
          ),
          tenantId: await this.getTenantIdForBranch(branchId),
        },
        take: limit + 1,
        orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
      });

      events.push(
        ...categories.map((c) => ({
          eventType: SyncEventType.CATEGORY_UPDATED,
          entityId: c.id,
          payload: c,
          timestamp: c.updatedAt,
        })),
      );
    }

    // Pull price override updates
    if (!dto.eventTypes || dto.eventTypes.includes(SyncEventType.PRICE_OVERRIDE_UPDATED)) {
      const priceOverrides = await this.prisma.branchPriceOverride.findMany({
        where: {
          branchId,
          OR: this.buildCursorWhere(
            'updatedAt',
            SyncEventType.PRICE_OVERRIDE_UPDATED,
            cursor,
          ),
        },
        include: {
          product: true,
        },
        take: limit + 1,
        orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
      });

      events.push(
        ...priceOverrides.map((p) => ({
          eventType: SyncEventType.PRICE_OVERRIDE_UPDATED,
          entityId: p.id,
          payload: p,
          timestamp: p.updatedAt,
        })),
      );
    }

    // Pull stock updates. Include the current stock row so every movement in
    // the page carries one authoritative quantity, even when tied movement
    // timestamps are ordered by UUID rather than insertion order.
    const stockUpdates = await this.prisma.stockMovement.findMany({
      where: {
        branchId,
        OR: this.buildCursorWhere(
          'createdAt',
          SyncEventType.STOCK_ADJUSTED,
          cursor,
        ),
      },
      include: {
        product: {
          include: {
            stock: {
              where: { branchId },
              select: { quantity: true },
            },
          },
        },
      },
      take: limit + 1,
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });

    events.push(
      ...stockUpdates.map((s) => ({
        eventType: SyncEventType.STOCK_ADJUSTED,
        entityId: s.id,
        payload: {
          ...s,
          currentQuantity: s.product.stock[0]?.quantity ?? s.newQty,
        },
        timestamp: s.createdAt,
      })),
    );

    // Pull sales (push-only gap fix: Device B never saw sales made on Device A)
    if (!dto.eventTypes || dto.eventTypes.includes(SyncEventType.SALE_CREATED)) {
      const sales = await this.prisma.sale.findMany({
        where: {
          branchId,
          OR: this.buildCursorWhere(
            'createdAt',
            SyncEventType.SALE_CREATED,
            cursor,
          ),
        },
        include: {
          items: {
            include: {
              product: { select: { sku: true } },
            },
          },
        },
        take: limit + 1,
        orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      });

      events.push(
        ...sales.map((s) => ({
          eventType: SyncEventType.SALE_CREATED,
          entityId: s.id,
          payload: s,
          timestamp: s.createdAt,
        })),
      );
    }

    // Pull customer updates
    if (!dto.eventTypes || dto.eventTypes.includes(SyncEventType.CUSTOMER_UPDATED)) {
      const customerTenantId = await this.getTenantIdForBranch(branchId);
      const customers = await this.prisma.customer.findMany({
        where: {
          tenantId: customerTenantId,
          OR: this.buildCursorWhere(
            'updatedAt',
            SyncEventType.CUSTOMER_UPDATED,
            cursor,
          ),
        },
        take: limit + 1,
        orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
      });

      events.push(
        ...customers.map((c) => ({
          eventType: SyncEventType.CUSTOMER_UPDATED,
          entityId: c.id,
          payload: c,
          timestamp: c.updatedAt,
        })),
      );
    }

    // Stable global ordering makes timestamp ties safe across pages.
    events.sort(
      (a, b) =>
        a.timestamp.getTime() - b.timestamp.getTime() ||
        a.eventType.localeCompare(b.eventType) ||
        a.entityId.localeCompare(b.entityId),
    );

    // Limit total results
    const limitedEvents = events.slice(0, limit);

    // Update device last sync timestamp
    await this.updateDeviceSyncStatus(deviceUuid, 'pull');

    return {
      events: limitedEvents,
      hasMore: events.length > limit,
      serverTimestamp: syncCutoff,
      nextCursor: limitedEvents.length > 0
        ? this.encodePullCursor(
            syncCutoff,
            limitedEvents[limitedEvents.length - 1],
          )
        : undefined,
    };
  }

  /**
   * Get sync status for a device
   */
  async getSyncStatus(deviceUuid: string | undefined): Promise<SyncStatusDto> {
    const normalizedDeviceUuid = this.normalizeDeviceUuid(deviceUuid);
    if (!normalizedDeviceUuid) {
      return {
        deviceId: '',
        lastPushAt: new Date(0),
        lastPullAt: new Date(0),
        pendingEvents: 0,
        isOnline: false,
      };
    }

    const device = await this.prisma.device.findUnique({
      where: { deviceUuid: normalizedDeviceUuid },
    });

    if (!device) {
      return {
        deviceId: normalizedDeviceUuid,
        lastPushAt: new Date(0),
        lastPullAt: new Date(0),
        pendingEvents: 0,
        isOnline: false,
      };
    }

    // Get pending events count
    const pendingEvents = await this.prisma.syncEvent.count({
      where: {
        deviceId: device.id,
        status: SyncEventStatus.PENDING,
      },
    });

    // Check if device is online (pinged in last 5 minutes)
    const lastPing = await this.redis.get(`device:ping:${normalizedDeviceUuid}`);
    const isOnline = lastPing
      ? Date.now() - parseInt(lastPing) < 5 * 60 * 1000
      : false;

    return {
      deviceId: normalizedDeviceUuid,
      lastPushAt: device.lastSyncAt || new Date(0),
      lastPullAt: device.lastSyncAt || new Date(0),
      pendingEvents,
      isOnline,
    };
  }

  /**
   * Handle conflict resolution
   */
  async resolveConflict(
    deviceId: string,
    conflicts: ConflictResolutionDto[],
  ): Promise<SyncResultDto[]> {
    const results: SyncResultDto[] = [];

    for (const conflict of conflicts) {
      try {
        const event = await this.prisma.syncEvent.findUnique({
          where: { id: conflict.eventId },
        });

        if (!event) {
          results.push({
            eventId: conflict.eventId,
            success: false,
            error: 'Event not found',
          });
          continue;
        }

        switch (conflict.resolution) {
          case 'SERVER_WINS':
            // Mark event as resolved, server data takes precedence
            await this.prisma.syncEvent.update({
              where: { id: conflict.eventId },
              data: {
                status: SyncEventStatus.RESOLVED,
                resolution: 'SERVER_WINS',
              },
            });
            break;

          case 'CLIENT_WINS':
            // Reprocess the event with client data
            await this.prisma.syncEvent.update({
              where: { id: conflict.eventId },
              data: {
                status: SyncEventStatus.PENDING,
                resolution: 'CLIENT_WINS',
              },
            });
            // Re-queue for processing
            break;

          case 'MERGE':
            if (!conflict.mergedPayload) {
              throw new BadRequestException('Merged payload required for MERGE resolution');
            }
            // Update event with merged data
            await this.prisma.syncEvent.update({
              where: { id: conflict.eventId },
              data: {
                status: SyncEventStatus.PENDING,
                resolution: 'MERGE',
                payload: conflict.mergedPayload,
              },
            });
            break;
        }

        results.push({
          eventId: conflict.eventId,
          success: true,
          serverTimestamp: new Date(),
        });
      } catch (error) {
        results.push({
          eventId: conflict.eventId,
          success: false,
          error: error.message,
        });
      }
    }

    return results;
  }

  /**
   * Register device heartbeat
   */
  async registerHeartbeat(deviceUuid: string | undefined): Promise<void> {
    const normalizedDeviceUuid = this.normalizeDeviceUuid(deviceUuid);
    if (!normalizedDeviceUuid) {
      this.logger.warn('Skipping heartbeat registration because the request has no device UUID.');
      return;
    }

    await this.redis.set(`device:ping:${normalizedDeviceUuid}`, Date.now().toString(), 600);

    const result = await this.prisma.device.updateMany({
      where: { deviceUuid: normalizedDeviceUuid },
      data: { lastActiveAt: new Date() },
    });

    if (result.count === 0) {
      this.logger.warn(`Heartbeat received for unregistered device UUID ${normalizedDeviceUuid}.`);
    }
  }

  /**
   * Get failed events for retry
   */
  async getFailedEvents(deviceUuid: string | undefined): Promise<any[]> {
    const device = await this.findDeviceByUuid(deviceUuid);
    if (!device) {
      return [];
    }

    return this.prisma.syncEvent.findMany({
      where: {
        deviceId: device.id,
        status: SyncEventStatus.FAILED,
        retryCount: { lt: 5 }, // Max 5 retries
      },
      orderBy: { createdAt: 'asc' },
    });
  }

  /**
   * Retry failed events
   */
  async retryFailedEvents(deviceUuid: string | undefined, branchId: string): Promise<PushSyncResponseDto> {
    const failedEvents = await this.getFailedEvents(deviceUuid);
    
    if (failedEvents.length === 0) {
      return {
        results: [],
        successCount: 0,
        failureCount: 0,
        serverTimestamp: new Date(),
      };
    }

    const events: SyncEventDto[] = failedEvents.map((e) => ({
      eventId: e.id,
      eventType: e.eventType as SyncEventType,
      payload: e.payload as Record<string, any>,
      deviceId: this.normalizeDeviceUuid(deviceUuid) || '',
      createdAt: e.createdAt.toISOString(),
    }));

    return this.pushEvents(deviceUuid, branchId, { events });
  }

  // Private helper methods

  private async processEvent(
    event: SyncEventDto,
    branchId: string,
    deviceId: string,
  ): Promise<{ serverId: string }> {
    const payload = event.payload;
    const tenantId = await this.getTenantIdForBranch(branchId);
    const userId = payload.cashierId || payload.createdById || payload.voidedById || payload.refundedById || payload.adjustedById || '';

    switch (event.eventType) {
      case SyncEventType.SALE_CREATED:
        const sale = await this.salesService.createSale(userId, tenantId, {
          branchId,
          items: payload.items,
          customerId: payload.customerId,
          paymentMethod: payload.paymentMethod,
          discountAmount: payload.discount || payload.discountAmount,
          paidAmount: payload.paidAmount || payload.totalAmount || 0,
          tenders: payload.tenders,
          notes: payload.notes,
          offlineId: payload.offlineId || payload.id || event.eventId,
        });
        return { serverId: sale.id };

      case SyncEventType.SALE_VOIDED:
        await this.salesService.voidSale(
          payload.saleId,
          payload.voidedById,
          tenantId,
          payload.reason,
        );
        return { serverId: payload.saleId };

      case SyncEventType.REFUND_CREATED:
        const refund = await this.salesService.createRefund(userId, tenantId, {
          saleId: payload.saleId,
          items: payload.items,
          reason: payload.reason,
        });
        return { serverId: refund.id };

      case SyncEventType.STOCK_ADJUSTED:
        await this.inventoryService.adjustStock(userId, tenantId, {
          branchId,
          type: payload.type,
          items: payload.items || [{ productId: payload.productId, quantity: payload.quantity }],
          notes: payload.reason || payload.notes,
        });
        return { serverId: event.eventId };

      case SyncEventType.STOCK_TRANSFER_CREATED:
        const transfer = await this.inventoryService.createTransfer(userId, tenantId, {
          fromBranchId: branchId,
          toBranchId: payload.toBranchId,
          items: payload.items,
          notes: payload.notes,
        });
        return { serverId: transfer.id };

      case SyncEventType.SUPPLIER_INVOICE_CREATED:
        const invoice = await this.suppliersService.createInvoice(userId, tenantId, {
          branchId,
          supplierName: payload.supplierName,
          supplierPhone: payload.supplierPhone,
          invoiceNumber: payload.invoiceNumber,
          receiptImageUrl: payload.receiptImageUrl,
          items: payload.items,
          paidAmount: payload.paidAmount,
          fundingSource: payload.fundingSource,
          dueDate: payload.dueDate,
          offlineId: event.eventId,
        });
        return { serverId: invoice.id };

      case SyncEventType.SUPPLIER_PAYMENT_RECORDED:
        const payment = await this.suppliersService.recordPayment(
          userId,
          tenantId,
          payload.invoiceId,
          {
            amount: payload.amount,
            fundingSource: payload.fundingSource,
            notes: payload.notes,
          },
        );
        return { serverId: payment.id };

      case SyncEventType.CUSTOMER_CREATED:
        const newCustomer = await this.prisma.customer.create({
          data: {
            id: payload.id || undefined,
            tenantId,
            name: payload.name,
            phone: payload.phone || null,
            email: payload.email || null,
            address: payload.address || null,
          },
        });
        return { serverId: newCustomer.id };

      case SyncEventType.CUSTOMER_UPDATED:
        await this.prisma.customer.update({
          where: { id: payload.id },
          data: {
            name: payload.name,
            phone: payload.phone ?? undefined,
            email: payload.email ?? undefined,
            address: payload.address ?? undefined,
          },
        });
        return { serverId: payload.id };

      default:
        throw new BadRequestException(`Unknown event type: ${event.eventType}`);
    }
  }

  private getEntityType(eventType: SyncEventType): string {
    const mapping: Record<SyncEventType, string> = {
      [SyncEventType.SALE_CREATED]: 'Sale',
      [SyncEventType.SALE_VOIDED]: 'Sale',
      [SyncEventType.REFUND_CREATED]: 'Refund',
      [SyncEventType.STOCK_ADJUSTED]: 'StockMovement',
      [SyncEventType.STOCK_TRANSFER_CREATED]: 'StockTransfer',
      [SyncEventType.PRODUCT_UPDATED]: 'Product',
      [SyncEventType.CATEGORY_UPDATED]: 'Category',
      [SyncEventType.PRICE_OVERRIDE_UPDATED]: 'BranchProductPrice',
      [SyncEventType.USER_UPDATED]: 'User',
      [SyncEventType.SUPPLIER_INVOICE_CREATED]: 'SupplierInvoice',
      [SyncEventType.SUPPLIER_PAYMENT_RECORDED]: 'SupplierPayment',
      [SyncEventType.CUSTOMER_CREATED]: 'Customer',
      [SyncEventType.CUSTOMER_UPDATED]: 'Customer',
    };
    return mapping[eventType] || 'Unknown';
  }

  private async updateDeviceSyncStatus(
    deviceUuid: string | undefined,
    type: 'push' | 'pull',
  ): Promise<void> {
    const normalizedDeviceUuid = this.normalizeDeviceUuid(deviceUuid);
    if (!normalizedDeviceUuid) {
      this.logger.warn(`Skipping ${type} sync status update because the request has no device UUID.`);
      return;
    }

    const result = await this.prisma.device.updateMany({
      where: { deviceUuid: normalizedDeviceUuid },
      data: {
        lastSyncAt: new Date(),
        lastActiveAt: new Date(),
      },
    });

    if (result.count === 0) {
      this.logger.warn(`Skipping ${type} sync status update because device UUID ${normalizedDeviceUuid} is not registered.`);
    }
  }

  private normalizeDeviceUuid(deviceUuid: string | undefined): string | null {
    if (typeof deviceUuid !== 'string') {
      return null;
    }

    const trimmedDeviceUuid = deviceUuid.trim();
    return trimmedDeviceUuid.length > 0 ? trimmedDeviceUuid : null;
  }

  private async findDeviceByUuid(deviceUuid: string | undefined) {
    const normalizedDeviceUuid = this.normalizeDeviceUuid(deviceUuid);
    if (!normalizedDeviceUuid) {
      return null;
    }

    return this.prisma.device.findUnique({
      where: { deviceUuid: normalizedDeviceUuid },
      select: { id: true, deviceUuid: true },
    });
  }

  private async getTenantIdForBranch(branchId: string): Promise<string> {
    const branch = await this.prisma.branch.findUnique({
      where: { id: branchId },
      select: { tenantId: true },
    });
    return branch?.tenantId || '';
  }
}
