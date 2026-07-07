import { Module } from '@nestjs/common';
import { InventoryController } from './inventory.controller';
import { InventoryService } from './inventory.service';
import { CashFlowModule } from '../cash-flow/cash-flow.module';
import { AiModule } from '../ai/ai.module';

@Module({
  imports: [CashFlowModule, AiModule],
  controllers: [InventoryController],
  providers: [InventoryService],
  exports: [InventoryService],
})
export class InventoryModule {}
