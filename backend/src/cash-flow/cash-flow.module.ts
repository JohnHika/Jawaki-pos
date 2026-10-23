import { Module } from '@nestjs/common';
import { CashFlowController } from './cash-flow.controller';
import { CashFlowService } from './cash-flow.service';
import { CashReconciliationController } from './cash-reconciliation.controller';
import { CashReconciliationService } from './cash-reconciliation.service';
import { AuditModule } from '../audit/audit.module';
import { AccountabilityModule } from '../accountability/accountability.module';

@Module({
  imports: [AuditModule, AccountabilityModule],
  controllers: [CashFlowController, CashReconciliationController],
  providers: [CashFlowService, CashReconciliationService],
  exports: [CashFlowService, CashReconciliationService],
})
export class CashFlowModule {}
