import { Injectable, Logger, BadRequestException, ConflictException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { SalesService } from '../sales/sales.service';
import { InventoryService } from '../inventory/inventory.service';
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

@Injectable()
export class SyncService {
  private readonly logger = new Logger(SyncService.name);

  constructor(
    private prisma: PrismaService,
    private redis: RedisService,
    private salesService: SalesService,
    private inventoryService: InventoryService,
  ) {}

  /**
   * Push events from offline device to server
   * Processes events idempotently to handle duplicate submissions
   */
  async pushEvents(
    deviceId: string,
    branchId: string,
    dto: PushSyncEventsDto,
  ): Promise<PushSyncResponseDto> {
    const results: SyncResultDto[] = [];
    let successCount = 0;
    let failureCount = 0;

    // Sort events by sequence number if provided
    const sortedEvents = [...dto.events].sort(
      (a, b) => (a.sequenceNumber || 0) - (b.sequenceNumber || 0),
    );

    for (const event of sortedEvents) {
      try {
        // Check if event was already processed (idempotency)
        const existingEvent = await this.prisma.syncEvent.findUnique({
          where: { id: event.eventId },
        });

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
        const result = await this.processEvent(event, branchId, deviceId);
        
        // Get userId from payload or use default
        const userId = event.payload.cashierId || event.payload.createdById || event.payload.userId || '';
        
        // Record the sync event
        await this.prisma.syncEvent.create({
          data: {
            deviceId,
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

        results.push({
          eventId: event.eventId,
          success: true,
          serverId: result.serverId,
          serverTimestamp: new Date(),
        });
        successCount++;
      } catch (error) {
        this.logger.error(`Failed to process event ${event.eventId}:`, error);
        
        // Get userId from payload or use default
        const errorUserId = event.payload.cashierId || event.payload.createdById || event.payload.userId || '';
        
        // Record failed event for retry using eventId for uniqueness
        await this.prisma.syncEvent.upsert({
          where: { 
            deviceId_eventId: { deviceId, eventId: event.eventId }
          },
          create: {
            deviceId,
            branchId,
            userId: errorUserId,
            eventId: event.eventId,
            eventType: event.eventType as unknown as PrismaSyncEventType,
            payload: event.payload,
            entityType: this.getEntityType(event.eventType),
            status: SyncEventStatus.FAILED,
            errorMessage: error.message,
            deviceTimestamp: new Date(event.createdAt),
          },
          update: {
            status: SyncEventStatus.FAILED,
            errorMessage: error.message,
            retryCount: { increment: 1 },
          },
        });

        results.push({
          eventId: event.eventId,
          success: false,
          error: error.message,
        });
        failureCount++;
      }
    }

    // Update device last sync timestamp
    await this.updateDeviceSyncStatus(deviceId, 'push');

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
  async pullEvents(
    deviceId: string,
    branchId: string,
    dto: PullSyncRequestDto,
  ): Promise<PullSyncResponseDto> {
    const limit = dto.limit || 100;
    const since = dto.since ? new Date(dto.since) : new Date(0);

    // Build query for changed entities
    const events: any[] = [];

    // Pull product updates
    if (!dto.eventTypes || dto.eventTypes.includes(SyncEventType.PRODUCT_UPDATED)) {
      const products = await this.prisma.product.findMany({
        where: {
          updatedAt: { gt: since },
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
        },
        take: limit,
        orderBy: { updatedAt: 'asc' },
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
          updatedAt: { gt: since },
          tenantId: await this.getTenantIdForBranch(branchId),
        },
        take: limit,
        orderBy: { updatedAt: 'asc' },
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
          updatedAt: { gt: since },
        },
        include: {
          product: true,
        },
        take: limit,
        orderBy: { updatedAt: 'asc' },
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

    // Pull stock updates
    const stockUpdates = await this.prisma.stockMovement.findMany({
      where: {
        branchId,
        createdAt: { gt: since },
      },
      include: {
        product: true,
      },
      take: limit,
      orderBy: { createdAt: 'asc' },
    });

    events.push(
      ...stockUpdates.map((s) => ({
        eventType: SyncEventType.STOCK_ADJUSTED,
        entityId: s.id,
        payload: s,
        timestamp: s.createdAt,
      })),
    );

    // Sort all events by timestamp
    events.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

    // Limit total results
    const limitedEvents = events.slice(0, limit);

    // Update device last sync timestamp
    await this.updateDeviceSyncStatus(deviceId, 'pull');

    return {
      events: limitedEvents,
      hasMore: events.length > limit,
      serverTimestamp: new Date(),
      nextCursor: limitedEvents.length > 0
        ? limitedEvents[limitedEvents.length - 1].timestamp.toISOString()
        : undefined,
    };
  }

  /**
   * Get sync status for a device
   */
  async getSyncStatus(deviceId: string): Promise<SyncStatusDto> {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
    });

    if (!device) {
      throw new BadRequestException('Device not found');
    }

    // Get pending events count
    const pendingEvents = await this.prisma.syncEvent.count({
      where: {
        deviceId,
        status: SyncEventStatus.PENDING,
      },
    });

    // Check if device is online (pinged in last 5 minutes)
    const lastPing = await this.redis.get(`device:ping:${deviceId}`);
    const isOnline = lastPing
      ? Date.now() - parseInt(lastPing) < 5 * 60 * 1000
      : false;

    return {
      deviceId,
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
  async registerHeartbeat(deviceId: string): Promise<void> {
    await this.redis.set(`device:ping:${deviceId}`, Date.now().toString(), 600);
    
    await this.prisma.device.update({
      where: { id: deviceId },
      data: { lastActiveAt: new Date() },
    });
  }

  /**
   * Get failed events for retry
   */
  async getFailedEvents(deviceId: string): Promise<any[]> {
    return this.prisma.syncEvent.findMany({
      where: {
        deviceId,
        status: SyncEventStatus.FAILED,
        retryCount: { lt: 5 }, // Max 5 retries
      },
      orderBy: { createdAt: 'asc' },
    });
  }

  /**
   * Retry failed events
   */
  async retryFailedEvents(deviceId: string, branchId: string): Promise<PushSyncResponseDto> {
    const failedEvents = await this.getFailedEvents(deviceId);
    
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
      deviceId: e.deviceId,
      createdAt: e.createdAt.toISOString(),
    }));

    return this.pushEvents(deviceId, branchId, { events });
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
          notes: payload.notes,
          offlineId: event.eventId,
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
    };
    return mapping[eventType] || 'Unknown';
  }

  private async updateDeviceSyncStatus(
    deviceId: string,
    type: 'push' | 'pull',
  ): Promise<void> {
    await this.prisma.device.update({
      where: { id: deviceId },
      data: {
        lastSyncAt: new Date(),
        lastActiveAt: new Date(),
      },
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
