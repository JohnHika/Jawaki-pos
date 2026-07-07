import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { ScheduleModule } from '@nestjs/schedule';
import { PrismaModule } from './common/prisma/prisma.module';
import { RedisModule } from './common/redis/redis.module';
import { AuthModule } from './auth/auth.module';
import { BranchesModule } from './branches/branches.module';
import { CatalogModule } from './catalog/catalog.module';
import { SalesModule } from './sales/sales.module';
import { InventoryModule } from './inventory/inventory.module';
import { SyncModule } from './sync/sync.module';
import { ReportingModule } from './reporting/reporting.module';
import { ExpensesModule } from './expenses/expenses.module';
import { AiModule } from './ai/ai.module';
import { AiBillingModule } from './ai-billing/ai-billing.module';
import { UploadsModule } from './uploads/uploads.module';
import { AppUpdatesModule } from './app-updates/app-updates.module';
import { ApiV1Module } from './api-v1/api-v1.module';
import { PaymentsModule } from './payments/payments.module';
import { AuditModule } from './audit/audit.module';
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

    // Scheduled tasks (AI subscription auto-renewal, etc.)
    ScheduleModule.forRoot(),

    // Core Modules
    PrismaModule,
    RedisModule,

    // Feature Modules
    AuthModule,
    BranchesModule,
    CatalogModule,
    SalesModule,
    InventoryModule,
    SyncModule,
    ReportingModule,
    ExpensesModule,
    AiModule,
    AiBillingModule,
    UploadsModule,
    AppUpdatesModule,
    ApiV1Module,
    PaymentsModule,
    AuditModule,
  ],
  controllers: [AppController],
})
export class AppModule {}
