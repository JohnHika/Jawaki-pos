import { Module } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { AiWebService } from './ai-web.service';
import { AiCognitiveService } from './ai-cognitive.service';
import { GithubIntegrationService } from './github-integration.service';

@Module({
  controllers: [AiController],
  providers: [AiService, AiWebService, AiCognitiveService, GithubIntegrationService],
  exports: [AiService, AiWebService, AiCognitiveService, GithubIntegrationService],
})
export class AiModule {}
