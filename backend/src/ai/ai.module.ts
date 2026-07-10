import { Module, forwardRef } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { AiWebService } from './ai-web.service';
import { AiCognitiveService } from './ai-cognitive.service';
import { AiConversationService } from './ai-conversation.service';
import { AiMemoryService } from './ai-memory.service';
import { AiToolsService } from './ai-tools.service';
import { AiDailyBriefTask } from './ai-daily-brief.task';
import { AiBillingModule } from '../ai-billing/ai-billing.module';
import { ReportingModule } from '../reporting/reporting.module';
import { InventoryModule } from '../inventory/inventory.module';
import { PrismaModule } from '../common/prisma/prisma.module';

@Module({
  imports: [
    AiBillingModule,
    ReportingModule,
    PrismaModule,
    // InventoryModule already imports AiModule (InventoryService uses
    // AiService.explainRestockPlan) — forwardRef on both sides breaks the
    // cycle so AiToolsService can call InventoryService.getLowStockAlerts /
    // createStockRequest.
    forwardRef(() => InventoryModule),
  ],
  controllers: [AiController],
  providers: [
    AiService,
    AiWebService,
    AiCognitiveService,
    AiConversationService,
    AiMemoryService,
    AiToolsService,
    AiDailyBriefTask,
  ],
  exports: [AiService, AiWebService, AiCognitiveService],
})
export class AiModule {}
