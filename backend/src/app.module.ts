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
import { MerchantPaymentsModule } from './merchant-payments/merchant-payments.module';
import { AuditModule } from './audit/audit.module';
import { SuppliersModule } from './suppliers/suppliers.module';
import { CashFlowModule } from './cash-flow/cash-flow.module';
import { FinanceModule } from './finance/finance.module';
import { PermissionsModule } from './permissions/permissions.module';
import { RolesModule } from './roles/roles.module';
import { UsersManagementModule } from './users/users-management.module';
import { NotificationsModule } from './notifications/notifications.module';
import { CustomersModule } from './customers/customers.module';
import { PrintingModule } from './printing/printing.module';
import { TenantActivationModule } from './tenant-activation/tenant-activation.module';
import { TenantOnboardingModule } from './tenant-onboarding/tenant-onboarding.module';
import { SubscriptionModule } from './subscription/subscription.module';
import { BugReportModule } from './bug-report/bug-report.module';
import { PlatformAdminModule } from './platform-admin/platform-admin.module';
import { CardBillingModule } from './billing/card-billing.module';
import { BillingModule } from './billing/billing.module';
import { PartnersModule } from './partners/partners.module';
import { LicenseModule } from './license/license.module';
import { LegalPolicyModule } from './legal/legal-policy.module';
import { AccountabilityModule } from './accountability/accountability.module';
import { StocktakeModule } from './stocktake/stocktake.module';
import { ImportsModule } from './imports/imports.module';
import { NewsModule } from './news/news.module';
import { CouponsModule } from './coupons/coupons.module';
import { ReferralsModule } from './referrals/referrals.module';
import { StatementsModule } from './statements/statements.module';
import { ExchangeRatesModule } from './exchange-rates/exchange-rates.module';
import { AppController } from './app.controller';
import { VercelCronController } from './vercel-cron.controller';

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
        name: 'default',
        ttl: 60000,
        limit: 100,
      },
      {
        name: 'bug-report',
        ttl: 60000,
        limit: 5,
      },
    ]),

    // Vercel functions do not stay alive between requests. Use Vercel Cron
    // to trigger the protected HTTP routes instead of starting in-process
    // timers in each warm function instance.
    ...(process.env.VERCEL ? [] : [ScheduleModule.forRoot()]),

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
    MerchantPaymentsModule,
    AuditModule,
    SuppliersModule,
    CashFlowModule,
    FinanceModule,
    PermissionsModule,
    RolesModule,
    UsersManagementModule,
    NotificationsModule,
    CustomersModule,
    PrintingModule,
    TenantActivationModule,
    TenantOnboardingModule,
    SubscriptionModule,
    BugReportModule,
    PlatformAdminModule,
    CardBillingModule,
    BillingModule,
    LicenseModule,
    LegalPolicyModule,
    PartnersModule,
    AccountabilityModule,
    StocktakeModule,
    ImportsModule,
    NewsModule,
    CouponsModule,
    ReferralsModule,
    StatementsModule,
    ExchangeRatesModule,
  ],
  controllers: [AppController, VercelCronController],
})
export class AppModule {}
