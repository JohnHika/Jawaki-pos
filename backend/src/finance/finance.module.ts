import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { CashFlowModule } from '../cash-flow/cash-flow.module';
import { FinanceController } from './finance.controller';
import { FinanceService } from './finance.service';

@Module({
  imports: [AuditModule, CashFlowModule],
  controllers: [FinanceController],
  providers: [FinanceService],
  exports: [FinanceService],
})
export class FinanceModule {}
