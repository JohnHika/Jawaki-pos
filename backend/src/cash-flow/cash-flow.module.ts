import { Module } from '@nestjs/common';
import { CashFlowController } from './cash-flow.controller';
import { CashFlowService } from './cash-flow.service';
import { CashReconciliationController } from './cash-reconciliation.controller';
import { CashReconciliationService } from './cash-reconciliation.service';
import { AuditModule } from '../audit/audit.module';

@Module({
  imports: [AuditModule],
  controllers: [CashFlowController, CashReconciliationController],
  providers: [CashFlowService, CashReconciliationService],
  exports: [CashFlowService, CashReconciliationService],
})
export class CashFlowModule {}
