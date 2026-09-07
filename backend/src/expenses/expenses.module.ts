import { Module } from '@nestjs/common';
import { ExpensesController } from './expenses.controller';
import { ExpensesService } from './expenses.service';
import { CashFlowModule } from '../cash-flow/cash-flow.module';
import { SubscriptionGuard } from '../billing/subscription.guard';

@Module({
  imports: [CashFlowModule],
  controllers: [ExpensesController],
  // SubscriptionGuard provided locally (stateless; see sales.module.ts note).
  providers: [ExpensesService, SubscriptionGuard],
  exports: [ExpensesService],
})
export class ExpensesModule {}
