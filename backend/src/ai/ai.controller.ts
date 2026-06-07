import { Controller, Post, Body, HttpCode, HttpStatus, Get, UseGuards } from '@nestjs/common';
import { AiService } from './ai.service';
import { ChatRequestDto } from './dto/chat.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@Controller('ai')
export class AiController {
  constructor(private readonly aiService: AiService) {}

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
