import { Module } from '@nestjs/common';
import { SalesController } from './sales.controller';
import { SalesService } from './sales.service';
import { DailyCloseController } from './daily-close.controller';
import { DailyCloseService } from './daily-close.service';
import { CashFlowModule } from '../cash-flow/cash-flow.module';
import { AuditModule } from '../audit/audit.module';

@Module({
  imports: [CashFlowModule, AuditModule],
  controllers: [SalesController, DailyCloseController],
  providers: [SalesService, DailyCloseService],
  exports: [SalesService],
})
export class SalesModule {}
