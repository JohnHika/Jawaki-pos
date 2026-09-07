import { Module } from '@nestjs/common';
import { SuppliersController } from './suppliers.controller';
import { SuppliersService } from './suppliers.service';
import { AuditModule } from '../audit/audit.module';
import { CashFlowModule } from '../cash-flow/cash-flow.module';
import { SubscriptionGuard } from '../billing/subscription.guard';

@Module({
  imports: [AuditModule, CashFlowModule],
  controllers: [SuppliersController],
  // SubscriptionGuard provided locally (stateless; see sales.module.ts note).
  providers: [SuppliersService, SubscriptionGuard],
  exports: [SuppliersService],
})
export class SuppliersModule {}
