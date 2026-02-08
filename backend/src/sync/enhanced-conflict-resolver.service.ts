import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

export enum ConflictType {
  CONCURRENT_UPDATE = 'CONCURRENT_UPDATE',
  DELETED_ON_SERVER = 'DELETED_ON_SERVER',
  NEWER_VERSION_EXISTS = 'NEWER_VERSION_EXISTS',
  DUPLICATE_CREATE = 'DUPLICATE_CREATE',
}

export enum ConflictResolution {
  SERVER_WINS = 'SERVER_WINS',
  CLIENT_WINS = 'CLIENT_WINS',
  MERGE = 'MERGE',
  MANUAL = 'MANUAL',
}

export interface ConflictDetectionResult {
  hasConflict: boolean;
  conflictType?: ConflictType;
  serverData?: any;
  clientData?: any;
  conflictDetails?: string;
}

export interface ConflictResolutionResult {
  resolution: ConflictResolution;
  resolvedData: any;
  conflictDetails?: string;
}

/**
 * Enhanced Conflict Resolver Service
 * Detects and resolves data conflicts for offline sync
 */
@Injectable()
export class EnhancedConflictResolverService {
  private readonly logger = new Logger(EnhancedConflictResolverService.name);

  constructor(private prisma: PrismaService) {}

  /**
   * Detect conflicts for a sync event
   */
  async detectConflict(
    tableName: string,
    recordId: string,
    clientData: any,
    clientTimestamp: Date,
  ): Promise<ConflictDetectionResult> {
    try {
      // Get current server data
      const serverData = await this.getServerRecord(tableName, recordId);

      // Record doesn't exist on server
      if (!serverData) {
        // Check if it was deleted
        const deletionLog = await this.checkDeletionLog(tableName, recordId);
        if (deletionLog) {
          return {
            hasConflict: true,
            conflictType: ConflictType.DELETED_ON_SERVER,
            serverData: null,
            clientData,
            conflictDetails: `Record was deleted on server at ${deletionLog.deletedAt}`,
          };
        }
        // New record, no conflict
        return { hasConflict: false };
      }

      // Check for concurrent updates
      const serverUpdatedAt = serverData.updatedAt;
      if (serverUpdatedAt > clientTimestamp) {
        // Server has newer data
        const hasDataConflict = this.hasDataDifferences(serverData, clientData);
        
        if (hasDataConflict) {
          return {
            hasConflict: true,
            conflictType: ConflictType.CONCURRENT_UPDATE,
            serverData,
            clientData,
            conflictDetails: `Server record updated at ${serverUpdatedAt}, client timestamp: ${clientTimestamp}`,
          };
        }
      }

      // No conflict detected
      return { hasConflict: false };
    } catch (error) {
      this.logger.error(`Conflict detection failed: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Auto-resolve conflicts based on rules
   */
  async autoResolveConflict(
    tableName: string,
    conflictDetection: ConflictDetectionResult,
  ): Promise<ConflictResolutionResult> {
    if (!conflictDetection.hasConflict) {
      return {
        resolution: ConflictResolution.CLIENT_WINS,
        resolvedData: conflictDetection.clientData,
      };
    }

    const { conflictType, serverData, clientData } = conflictDetection;

    switch (conflictType) {
      case ConflictType.DELETED_ON_SERVER:
        // Server wins - record was deliberately deleted
        return {
          resolution: ConflictResolution.SERVER_WINS,
          resolvedData: null,
          conflictDetails: 'Record was deleted on server',
        };

      case ConflictType.CONCURRENT_UPDATE:
        // Try to merge non-conflicting fields
        const mergedData = await this.attemptMerge(
          tableName,
          serverData,
          clientData,
        );
        
        if (mergedData) {
          return {
            resolution: ConflictResolution.MERGE,
            resolvedData: mergedData,
            conflictDetails: 'Successfully merged non-conflicting fields',
          };
        }
        
        // Cannot auto-merge, requires manual intervention
        return {
          resolution: ConflictResolution.MANUAL,
          resolvedData: null,
          conflictDetails: 'Conflicting changes detected, manual resolution required',
        };

      case ConflictType.DUPLICATE_CREATE:
        // Server wins - use existing record
        return {
          resolution: ConflictResolution.SERVER_WINS,
          resolvedData: serverData,
          conflictDetails: 'Duplicate record, using existing server record',
        };

      default:
        // Default to client wins for unknown conflict types
        return {
          resolution: ConflictResolution.CLIENT_WINS,
          resolvedData: clientData,
        };
    }
  }

  /**
   * Attempt to merge server and client data
   */
  private async attemptMerge(
    tableName: string,
    serverData: any,
    clientData: any,
  ): Promise<any | null> {
    const mergedData = { ...serverData };
    const immutableFields = ['id', 'createdAt', 'tenantId'];
    const conflicts: string[] = [];

    // Compare each field
    for (const key of Object.keys(clientData)) {
      // Skip immutable fields
      if (immutableFields.includes(key)) continue;

      // Skip unchanged fields
      if (JSON.stringify(serverData[key]) === JSON.stringify(clientData[key])) {
        continue;
      }

      // Detect conflict
      if (
        serverData[key] !== undefined &&
        serverData[key] !== null &&
        clientData[key] !== serverData[key]
      ) {
        // Field-specific merge rules
        const mergeStrategy = this.getFieldMergeStrategy(tableName, key);
        
        switch (mergeStrategy) {
          case 'client-wins':
            mergedData[key] = clientData[key];
            break;
          case 'server-wins':
            mergedData[key] = serverData[key];
            break;
          case 'sum':
            // For numeric fields like quantities
            mergedData[key] = (serverData[key] || 0) + (clientData[key] || 0);
            break;
          case 'newer-wins':
            // Use the newer timestamp to decide
            if (clientData.updatedAt > serverData.updatedAt) {
              mergedData[key] = clientData[key];
            }
            break;
          default:
            // Cannot auto-merge this field
            conflicts.push(key);
        }
      } else {
        // No conflict, use client data
        mergedData[key] = clientData[key];
      }
    }

    // If there are unresolved conflicts, return null
    if (conflicts.length > 0) {
      this.logger.warn(`Cannot auto-merge fields: ${conflicts.join(', ')}`);
      return null;
    }

    return mergedData;
  }

  /**
   * Get merge strategy for specific field
   */
  private getFieldMergeStrategy(
    tableName: string,
    fieldName: string,
  ): 'client-wins' | 'server-wins' | 'newer-wins' | 'sum' | 'manual' {
    // Table-specific rules
    const rules: Record<string, Record<string, string>> = {
      products: {
        price: 'server-wins', // Server manages pricing
        name: 'newer-wins',
        description: 'newer-wins',
        stock: 'manual', // Stock requires special handling
      },
      sales: {
        status: 'server-wins', // Server manages sale status
        totalAmount: 'newer-wins',
      },
      stock_movements: {
        quantity: 'sum', // Can sum adjustments
      },
    };

    return (rules[tableName]?.[fieldName] as any) || 'manual';
  }

  /**
   * Check if record was deleted
   */
  private async checkDeletionLog(
    tableName: string,
    recordId: string,
  ): Promise<any> {
    // Check deletion audit log
    return this.prisma.auditLog.findFirst({
      where: {
        entityType: tableName,
        entityId: recordId,
        action: 'DELETE',
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  /**
   * Get server record by table and ID
   */
  private async getServerRecord(
    tableName: string,
    recordId: string,
  ): Promise<any> {
    const modelMap: Record<string, any> = {
      products: this.prisma.product,
      categories: this.prisma.category,
      sales: this.prisma.sale,
      stock_movements: this.prisma.stockMovement,
      price_overrides: this.prisma.branchPriceOverride,
    };

    const model = modelMap[tableName];
    if (!model) {
      throw new Error(`Unknown table: ${tableName}`);
    }

    return model.findUnique({ where: { id: recordId } });
  }

  /**
   * Check if server and client data have differences
   */
  private hasDataDifferences(serverData: any, clientData: any): boolean {
    const keysToCompare = Object.keys(clientData).filter(
      (key) => !['updatedAt', 'createdAt', 'id'].includes(key),
    );

    return keysToCompare.some(
      (key) =>
        JSON.stringify(serverData[key]) !== JSON.stringify(clientData[key]),
    );
  }

  /**
   * Log conflict for audit trail
   */
  async logConflict(
    tableName: string,
    recordId: string,
    conflictType: ConflictType,
    resolution: ConflictResolution,
    details: any,
  ): Promise<void> {
    await this.prisma.conflictLog.create({
      data: {
        tableName,
        recordId,
        conflictType,
        resolution,
        serverData: details.serverData,
        clientData: details.clientData,
        resolvedData: details.resolvedData,
        notes: details.conflictDetails,
      },
    });
  }
}
