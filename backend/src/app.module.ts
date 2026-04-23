import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { PrismaModule } from './common/prisma/prisma.module';
import { RedisModule } from './common/redis/redis.module';
import { AuthModule } from './auth/auth.module';
import { BranchesModule } from './branches/branches.module';
import { CatalogModule } from './catalog/catalog.module';
import { SalesModule } from './sales/sales.module';
import { InventoryModule } from './inventory/inventory.module';
import { PaymentsModule } from './payments/payments.module';
import { SyncModule } from './sync/sync.module';
import { ReportingModule } from './reporting/reporting.module';
import { ExpensesModule } from './expenses/expenses.module';
import { AppController } from './app.controller';

@Module({
  imports: [
    // Configuration
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env.local', '.env'],
    }),

    // Rate Limiting
    ThrottlerModule.forRoot([
      {
        ttl: 60000,
        limit: 100,
      },
    ]),

    // Core Modules
    PrismaModule,
    RedisModule,

    // Feature Modules
    AuthModule,
    BranchesModule,
    CatalogModule,
    SalesModule,
    InventoryModule,
    PaymentsModule,
    SyncModule,
    ReportingModule,
    ExpensesModule,
  ],
  controllers: [AppController],
})
export class AppModule {}
