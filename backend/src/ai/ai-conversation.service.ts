import { Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

/**
 * Shared, per-shop AI conversation history. A conversation is scoped to a
 * tenant (+ optional branch) so every staff member of that shop sees and
 * continues the same thread — the AI history is a shop asset, not a
 * per-device silo.
 */
@Injectable()
export class AiConversationService {
  constructor(private readonly prisma: PrismaService) {}

  /** The active shared thread for this tenant/branch, creating one if none. */
  async getOrCreateActive(tenantId: string, branchId?: string | null) {
    const existing = await this.prisma.aiConversation.findFirst({
      where: { tenantId, branchId: branchId ?? null, status: 'active' },
      orderBy: { createdAt: 'desc' },
    });
    if (existing) return existing;
    return this.prisma.aiConversation.create({
      data: { tenantId, branchId: branchId ?? null, status: 'active' },
    });
  }

  /** Load the shared thread's messages (oldest first), most recent [limit]. */
  async getMessages(
    tenantId: string,
    branchId: string | null | undefined,
    limit = 100,
  ) {
    const conversation = await this.prisma.aiConversation.findFirst({
      where: { tenantId, branchId: branchId ?? null, status: 'active' },
      orderBy: { createdAt: 'desc' },
    });
    if (!conversation) return { conversationId: null, messages: [] as any[] };

    const rows = await this.prisma.aiMessage.findMany({
      where: { conversationId: conversation.id },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    // Return oldest-first for display.
    const messages = rows.reverse().map((m) => ({
      id: m.id,
      role: m.role,
      content: m.content,
      attachments: m.attachments,
      createdByName: m.createdByName,
      createdAt: m.createdAt,
    }));
    return { conversationId: conversation.id, messages };
  }

  /** Append one message to the shared thread. */
  async appendMessage(params: {
    tenantId: string;
    branchId?: string | null;
    role: 'user' | 'assistant';
    content: string;
    attachments?: any;
    createdById?: string | null;
    createdByName?: string | null;
  }) {
    const conversation = await this.getOrCreateActive(
      params.tenantId,
      params.branchId,
    );
    const message = await this.prisma.aiMessage.create({
      data: {
        conversationId: conversation.id,
        role: params.role,
        content: params.content,
        attachments: params.attachments ?? [],
        createdById: params.createdById ?? null,
        createdByName: params.createdByName ?? null,
      },
    });
    // Bump the conversation's updatedAt so "latest" ordering stays correct.
    await this.prisma.aiConversation.update({
      where: { id: conversation.id },
      data: { updatedAt: new Date() },
    });
    return message;
  }

  /** Archive the active thread and start a fresh one ("New conversation"). */
  async startNew(tenantId: string, branchId?: string | null) {
    await this.prisma.aiConversation.updateMany({
      where: { tenantId, branchId: branchId ?? null, status: 'active' },
      data: { status: 'archived' },
    });
    return this.prisma.aiConversation.create({
      data: { tenantId, branchId: branchId ?? null, status: 'active' },
    });
  }

  /** Truncate the shared thread back to (and excluding) a given message —
   *  used by "edit & resubmit" so the edited turn and everything after it
   *  is removed from the shared history. */
  async truncateFromMessage(
    tenantId: string,
    branchId: string | null | undefined,
    messageId: string,
  ) {
    const conversation = await this.prisma.aiConversation.findFirst({
      where: { tenantId, branchId: branchId ?? null, status: 'active' },
      orderBy: { createdAt: 'desc' },
    });
    if (!conversation) return;
    const anchor = await this.prisma.aiMessage.findFirst({
      where: { id: messageId, conversationId: conversation.id },
    });
    if (!anchor) return;
    await this.prisma.aiMessage.deleteMany({
      where: {
        conversationId: conversation.id,
        createdAt: { gte: anchor.createdAt },
      },
    });
  }
}
