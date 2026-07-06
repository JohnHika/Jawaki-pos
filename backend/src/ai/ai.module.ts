import { Module } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { AiWebService } from './ai-web.service';
import { AiCognitiveService } from './ai-cognitive.service';

@Module({
  controllers: [AiController],
  providers: [AiService, AiWebService, AiCognitiveService],
  exports: [AiService, AiWebService, AiCognitiveService],
})
export class AiModule {}
