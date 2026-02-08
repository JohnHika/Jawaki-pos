import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    super({
      log: process.env.NODE_ENV === 'development' 
        ? ['query', 'info', 'warn', 'error']
        : ['error'],
    });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }

  async cleanDatabase() {
    if (process.env.NODE_ENV !== 'production') {
      // For testing purposes - order matters due to foreign keys
      const models = [
        'auditLog',
        'syncEvent',
        'refundItem',
        'refund',
        'payment',
        'mpesaTransaction',
        'pesapalTransaction',
        'touristTapTransaction',
        'saleItem',
        'sale',
        'customer',
        'stockTransferItem',
        'stockTransfer',
        'stockMovement',
        'stock',
        'branchPriceOverride',
        'productCategory',
        'product',
        'category',
        'refreshToken',
        'userBranch',
        'user',
        'device',
        'branch',
        'tenant',
      ];

      for (const model of models) {
        await (this as any)[model].deleteMany();
      }
    }
  }
}
