import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { FinanceModule } from '../finance/finance.module';
import { ReferralsModule } from '../referrals/referrals.module';
import { PermissionsModule } from '../permissions/permissions.module';
import { ThrottlerProvidersModule } from '../common/throttler/throttler-providers.module';
import { DebtCollectionService } from './debt-collection.service';
import { MpesaController } from './mpesa.controller';
import { MpesaService } from './mpesa.service';
import { StatementsController } from './statements.controller';
import { StatementsPublicController } from './statements-public.controller';
import { StatementsService } from './statements.service';

/**
 * Debt statements: a shareable link and PDF for a customer or shop that owes,
 * their "I have paid" replies, and matching pasted M-Pesa messages to debts.
 */
@Module({
  imports: [
    AuditModule,
    NotificationsModule,
    FinanceModule,
    ReferralsModule,
    PermissionsModule,
    ThrottlerProvidersModule,
  ],
  controllers: [StatementsController, StatementsPublicController, MpesaController],
  providers: [StatementsService, DebtCollectionService, MpesaService],
  exports: [StatementsService, DebtCollectionService],
})
export class StatementsModule {}
