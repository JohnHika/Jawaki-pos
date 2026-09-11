import { Module } from '@nestjs/common';
import { SalesController } from './sales.controller';
import { SalesService } from './sales.service';
import { DailyCloseController } from './daily-close.controller';
import { DailyCloseService } from './daily-close.service';
import { CashFlowModule } from '../cash-flow/cash-flow.module';
import { AuditModule } from '../audit/audit.module';
import { FinanceModule } from '../finance/finance.module';
import { SubscriptionGuard } from '../billing/subscription.guard';

@Module({
  imports: [CashFlowModule, AuditModule, FinanceModule],
  controllers: [SalesController, DailyCloseController],
  // SubscriptionGuard is provided locally (not imported from BillingModule)
  // to avoid a module cycle: BillingModule's RecurringBillingService depends
  // on PaymentsModule/JengaPaymentService, and the guard is stateless
  // (Reflector + PrismaService only), so a local instance is equivalent.
  providers: [SalesService, DailyCloseService, SubscriptionGuard],
  exports: [SalesService, DailyCloseService],
})
export class SalesModule {}
