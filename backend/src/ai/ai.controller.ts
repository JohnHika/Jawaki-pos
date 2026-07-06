import { Controller, Post, Body, HttpCode, HttpStatus, Get, UseGuards } from '@nestjs/common';
import { AiService } from './ai.service';
import { AiWebService } from './ai-web.service';
import { AiCognitiveService } from './ai-cognitive.service';
import { ChatRequestDto } from './dto/chat.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@Controller('ai')
export class AiController {
  constructor(
    private readonly aiService: AiService,
    private readonly aiWebService: AiWebService,
    private readonly aiCognitiveService: AiCognitiveService,
  ) {}

  @Get('chat')
  @HttpCode(HttpStatus.OK)
  async getChatInfo() {
    return {
      success: true,
      data: {
        currentModel: this.aiService.getCurrentModel(),
        status: 'connected',
        capabilities: ['sales-analysis', 'inventory-optimization', 'customer-insights', 'profit-optimization'],
      },
    };
  }

  @Post('chat')
  @HttpCode(HttpStatus.OK)
  async chat(@Body() dto: ChatRequestDto) {
    const result = await this.aiService.chat(dto);
    return {
      success: true,
      data: {
        reply: result.reply,
        model: result.model,
      },
    };
  }

  @Post('chat/web-enhanced')
  @HttpCode(HttpStatus.OK)
  async chatWithWebEnhancement(@Body() dto: ChatRequestDto) {
    // Enhance the request with current web insights
    const enhancedDto = await this.aiWebService.enhanceWithWebInsights(dto);

    // Process with AI service
    const result = await this.aiService.chat(enhancedDto);

    return {
      success: true,
      data: {
        reply: result.reply,
        model: result.model,
        web_insights: enhancedDto.data_context?.web_insights,
        web_sources: enhancedDto.data_context?.web_sources,
      },
    };
  }

  @Get('trends/kenya-retail')
  @HttpCode(HttpStatus.OK)
  async getKenyaRetailTrends() {
    const trends = await this.aiWebService.getCurrentKenyaRetailTrends();
    return {
      success: true,
      data: trends,
    };
  }

  @Post('cognitive/analyze')
  @HttpCode(HttpStatus.OK)
  async cognitiveAnalysis(@Body() dto: ChatRequestDto) {
    const result = await this.aiCognitiveService.cognitiveBusinessAnalysis(dto);
    return {
      success: true,
      data: result,
    };
  }

  @Post('cognitive/monitor')
  @HttpCode(HttpStatus.OK)
  async cognitiveMonitor(@Body() dto: ChatRequestDto) {
    const result = await this.aiCognitiveService.proactiveMonitor(dto);
    return {
      success: true,
      data: result,
    };
  }

  @Post('cognitive/advisor')
  @HttpCode(HttpStatus.OK)
  async cognitiveAdvisor(@Body() dto: ChatRequestDto) {
    const result = await this.aiCognitiveService.cognitiveBusinessAdvisor(dto);
    return {
      success: true,
      data: result,
    };
  }

  @Get('models')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async listModels() {
    const result = await this.aiService.listAvailableModels();
    return {
      success: true,
      data: {
        availableModels: result.models,
        currentModel: result.currentModel,
      },
    };
  }

  @Post('set-model')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async setModel(@Body('model') model: string) {
    this.aiService.setCurrentModel(model);
    return {
      success: true,
      message: `AI model set to ${model}`,
    };
  }
}
