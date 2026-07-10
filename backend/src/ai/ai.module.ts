import { Module } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { AiWebService } from './ai-web.service';
import { AiCognitiveService } from './ai-cognitive.service';
import { AiConversationService } from './ai-conversation.service';
import { AiMemoryService } from './ai-memory.service';
import { AiDailyBriefTask } from './ai-daily-brief.task';
import { AiBillingModule } from '../ai-billing/ai-billing.module';
import { ReportingModule } from '../reporting/reporting.module';
import { PrismaModule } from '../common/prisma/prisma.module';

@Module({
  imports: [AiBillingModule, ReportingModule, PrismaModule],
  controllers: [AiController],
  providers: [
    AiService,
    AiWebService,
    AiCognitiveService,
    AiConversationService,
    AiMemoryService,
    AiDailyBriefTask,
  ],
  exports: [AiService, AiWebService, AiCognitiveService],
})
export class AiModule {}
