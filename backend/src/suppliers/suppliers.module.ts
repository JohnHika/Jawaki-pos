import { Module } from '@nestjs/common';
import { SuppliersController } from './suppliers.controller';
import { SuppliersService } from './suppliers.service';
import { AuditModule } from '../audit/audit.module';
import { CashFlowModule } from '../cash-flow/cash-flow.module';

@Module({
  imports: [AuditModule, CashFlowModule],
  controllers: [SuppliersController],
  providers: [SuppliersService],
  exports: [SuppliersService],
})
export class SuppliersModule {}
