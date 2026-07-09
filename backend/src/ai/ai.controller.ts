import { Controller, Post, Body, HttpCode, HttpStatus, Get, Query, UseGuards } from '@nestjs/common';
import { AiService } from './ai.service';
import { AiWebService } from './ai-web.service';
import { AiCognitiveService } from './ai-cognitive.service';
import { ChatRequestDto } from './dto/chat.dto';
import { ScanReceiptDto } from './dto/receipt-scan.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { AiAccessGuard } from '../ai-billing/ai-billing.guard';
import { PrismaService } from '../common/prisma/prisma.service';

@Controller('ai')
export class AiController {
  constructor(
    private readonly aiService: AiService,
    private readonly aiWebService: AiWebService,
    private readonly aiCognitiveService: AiCognitiveService,
    private readonly prisma: PrismaService,
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
  @UseGuards(AiAccessGuard)
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

  // Pre-generated once daily by AiDailyBriefTask — near-instant read for
  // the dashboard's "AI Brief" card. Returns null content when the cron
  // hasn't produced one yet for today (new tenant, or ran before this
  // branch subscribed); the mobile app falls back to a live /ai/chat call
  // in that case.
  @Get('daily-brief')
  @UseGuards(AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async getDailyBrief(@Query('branchId') branchId: string) {
    const today = new Date();
    const date = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));

    const brief = await this.prisma.dailyBrief.findUnique({
      where: { branchId_date: { branchId, date } },
    });

    return {
      success: true,
      data: {
        content: brief?.content ?? null,
        model: brief?.model ?? null,
        date: date.toISOString(),
      },
    };
  }

  @Post('chat/web-enhanced')
  @UseGuards(AiAccessGuard)
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
  @UseGuards(AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async cognitiveAnalysis(@Body() dto: ChatRequestDto) {
    const result = await this.aiCognitiveService.cognitiveBusinessAnalysis(dto);
    return {
      success: true,
      data: result,
    };
  }

  @Post('cognitive/monitor')
  @UseGuards(AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async cognitiveMonitor(@Body() dto: ChatRequestDto) {
    const result = await this.aiCognitiveService.proactiveMonitor(dto);
    return {
      success: true,
      data: result,
    };
  }

  @Post('cognitive/advisor')
  @UseGuards(AiAccessGuard)
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

  @Post('receipts/scan')
  @UseGuards(AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async scanReceipt(@Body() dto: ScanReceiptDto) {
    const data = await this.aiService.parseReceiptImage(dto.imageUrl);
    return { success: true, data };
  }
}
