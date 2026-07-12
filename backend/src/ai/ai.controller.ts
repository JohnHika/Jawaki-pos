import { Controller, Post, Body, HttpCode, HttpStatus, Get, Query, UseGuards, Request } from '@nestjs/common';
import { AiService } from './ai.service';
import { AiWebService } from './ai-web.service';
import { AiCognitiveService } from './ai-cognitive.service';
import { AiConversationService } from './ai-conversation.service';
import { AiMemoryService } from './ai-memory.service';
import { ChatRequestDto } from './dto/chat.dto';
import { ScanReceiptDto } from './dto/receipt-scan.dto';
import { VisionChatRequestDto } from './dto/vision-chat.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { OptionalJwtAuthGuard } from '../auth/guards/optional-jwt-auth.guard';
import { AiAccessGuard } from '../ai-billing/ai-billing.guard';
import { PrismaService } from '../common/prisma/prisma.service';
import { normalizeOperatingHours, computeOpenStatus } from '../common/operating-hours';

@Controller('ai')
export class AiController {
  constructor(
    private readonly aiService: AiService,
    private readonly aiWebService: AiWebService,
    private readonly aiCognitiveService: AiCognitiveService,
    private readonly conversations: AiConversationService,
    private readonly memories: AiMemoryService,
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
  @UseGuards(OptionalJwtAuthGuard, AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async chat(@Body() dto: ChatRequestDto, @Request() req: any) {
    const user = req.user || {};
    const tenantId = user.tenantId as string | undefined;
    const branchId = (dto.branchId || user.branchId) as string | undefined;

    // Web search grounding when the user enabled the toggle in the
    // "Add to chat" sheet — injects live web results into the context.
    let workingDto = dto;
    if (dto.web_search) {
      try {
        workingDto = await this.aiWebService.enhanceWithWebInsights(dto);
      } catch {
        workingDto = dto; // best-effort; never block the reply
      }
    }

    // Inject durable shop memories relevant to this question so the AI
    // recalls owner preferences / policies / customer notes across sessions.
    if (tenantId) {
      try {
        const relevant = await this.memories.selectRelevant(
          tenantId,
          workingDto.user_question || '',
        );
        if (relevant.length > 0) {
          workingDto.data_context = {
            ...(workingDto.data_context || {}),
            shop_memories: relevant,
          };
        }
      } catch {
        // memory is best-effort context, never block the reply
      }
    }

    // Inject the branch's user-configured operating hours + live open/closed
    // status so the assistant reasons over the real trading window (e.g.
    // "you close in 90 minutes", "closed today") instead of guessing or
    // relying on a freeform memory. Best-effort.
    if (tenantId && branchId) {
      try {
        const branch = await this.prisma.branch.findFirst({
          where: { id: branchId, tenantId },
          select: { settings: true, timezone: true },
        });
        const rawHours = (branch?.settings as Record<string, any>)?.operatingHours;
        const hours = normalizeOperatingHours(rawHours);
        if (hours) {
          const status = computeOpenStatus(hours, branch?.timezone || 'Africa/Nairobi');
          workingDto.data_context = {
            ...(workingDto.data_context || {}),
            operating_hours: hours,
            open_status: status,
          };
        }
      } catch {
        // hours are best-effort context, never block the reply
      }
    }

    const toolCtx = tenantId ? { tenantId, branchId, userId: user.sub as string | undefined } : undefined;
    const result = await this.aiService.chat(workingDto, toolCtx);

    // Persist turns to the shop's shared thread so every staff member sees
    // the same conversation. Best-effort: a persistence hiccup must never
    // fail the actual AI reply. Only persist the user's question on the
    // *initial* ask, not when resuming a paused tool turn (that question
    // was already appended) — and only persist an assistant turn once we
    // have real reply text (a pending question/confirmation has none yet).
    // Message ids of the turn(s) just persisted — returned to the client so
    // it can later target this exact turn for regenerate/rewind without
    // guessing positions in a list that may differ from the server's.
    let userMessageId: string | null = null;
    let assistantMessageId: string | null = null;
    if (tenantId) {
      try {
        const userName = (user.email as string | undefined) || null;
        if (dto.user_question && !dto.pending_tool_call) {
          const saved = await this.conversations.appendMessage({
            tenantId,
            branchId,
            role: 'user',
            content: dto.user_question,
            createdById: user.sub ?? null,
            createdByName: userName,
          });
          userMessageId = saved.id;
        }
        if (result.kind === 'reply') {
          const saved = await this.conversations.appendMessage({
            tenantId,
            branchId,
            role: 'assistant',
            content: result.reply,
          });
          assistantMessageId = saved.id;
        }
      } catch {
        // swallow — reply already produced
      }
    }

    if (result.kind === 'pending_question') {
      return {
        success: true,
        data: {
          reply: null,
          model: result.model,
          userMessageId,
          pending: {
            type: 'question',
            tool_call: result.pendingToolCall,
            questions: result.questions,
          },
        },
      };
    }

    if (result.kind === 'pending_confirmation') {
      return {
        success: true,
        data: {
          reply: null,
          model: result.model,
          userMessageId,
          pending: {
            type: 'confirmation',
            tool_call: result.pendingToolCall,
            summary: result.summary,
          },
        },
      };
    }

    if (result.kind === 'pending_plan') {
      return {
        success: true,
        data: {
          reply: null,
          model: result.model,
          userMessageId,
          pending: {
            type: 'plan',
            tool_call: result.pendingToolCall,
            plan: result.plan,
          },
        },
      };
    }

    return {
      success: true,
      data: {
        reply: result.reply,
        model: result.model,
        userMessageId,
        assistantMessageId,
        todos: result.todos,
      },
    };
  }

  // The shop's shared AI conversation — every staff member loads and
  // continues the same thread.
  @Get('conversation')
  @UseGuards(JwtAuthGuard, AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async getConversation(
    @Request() req: any,
    @Query('branchId') branchId?: string,
  ) {
    const tenantId = req.user?.tenantId as string | undefined;
    if (!tenantId) return { success: true, data: { messages: [] } };
    const resolvedBranch = branchId || req.user?.branchId || null;
    const data = await this.conversations.getMessages(tenantId, resolvedBranch);
    return { success: true, data };
  }

  @Post('conversation/new')
  @UseGuards(JwtAuthGuard, AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async newConversation(
    @Request() req: any,
    @Body() body: { branchId?: string },
  ) {
    const tenantId = req.user?.tenantId as string | undefined;
    if (!tenantId) return { success: true };
    const resolvedBranch = body?.branchId || req.user?.branchId || null;
    await this.conversations.startNew(tenantId, resolvedBranch);
    return { success: true };
  }

  // Truncates the shared thread back to (and excluding) a given message —
  // backs both "edit & resubmit" and "rewind": removing an earlier message
  // and everything after it so every staff member's view stays in sync,
  // not just the device that triggered it.
  @Post('conversation/truncate')
  @UseGuards(JwtAuthGuard, AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async truncateConversation(
    @Request() req: any,
    @Body() body: { branchId?: string; messageId?: string },
  ) {
    const tenantId = req.user?.tenantId as string | undefined;
    if (!tenantId || !body?.messageId) return { success: false };
    const resolvedBranch = body.branchId || req.user?.branchId || null;
    await this.conversations.truncateFromMessage(tenantId, resolvedBranch, body.messageId);
    return { success: true };
  }

  // Durable shop memory the AI recalls across sessions (owner preferences,
  // policies, customer notes). Tenant-scoped and shared per shop.
  @Get('memory')
  @UseGuards(JwtAuthGuard, AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async listMemories(@Request() req: any) {
    const tenantId = req.user?.tenantId as string | undefined;
    if (!tenantId) return { success: true, data: [] };
    const data = await this.memories.list(tenantId);
    return { success: true, data };
  }

  @Post('memory')
  @UseGuards(JwtAuthGuard, AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async saveMemory(
    @Request() req: any,
    @Body() body: { type?: string; title?: string; content?: string },
  ) {
    const tenantId = req.user?.tenantId as string | undefined;
    if (!tenantId || !body?.content) {
      return { success: false };
    }
    const memory = await this.memories.save({
      tenantId,
      type: body.type || 'fact',
      title: body.title || body.content.slice(0, 60),
      content: body.content,
    });
    return { success: true, data: memory };
  }

  @Post('memory/delete')
  @UseGuards(JwtAuthGuard, AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async deleteMemory(@Request() req: any, @Body() body: { id?: string }) {
    const tenantId = req.user?.tenantId as string | undefined;
    if (!tenantId || !body?.id) return { success: false };
    await this.memories.remove(tenantId, body.id);
    return { success: true };
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

    // Process with AI service. No tenant context is passed here, so the
    // tool-calling agent path never engages and the result is always a
    // plain reply.
    const result = await this.aiService.chat(enhancedDto);
    const reply = result.kind === 'reply' ? result.reply : null;

    return {
      success: true,
      data: {
        reply,
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

  @Post('vision')
  @UseGuards(OptionalJwtAuthGuard, AiAccessGuard)
  @HttpCode(HttpStatus.OK)
  async analyzeImage(@Body() dto: VisionChatRequestDto) {
    const data = await this.aiService.analyzeImage(dto.imageBase64, dto.prompt);
    return { success: true, data };
  }
}
