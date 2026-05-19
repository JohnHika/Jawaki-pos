import { Controller, Post, Body, HttpCode, HttpStatus } from '@nestjs/common';
import { AiService } from './ai.service';
import { ChatRequestDto } from './dto/chat.dto';

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
}
