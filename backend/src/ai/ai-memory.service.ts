import { Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

/**
 * Durable, tenant-scoped memory the AI recalls across sessions — owner
 * preferences, recurring-customer notes, store policies, facts. Shared per
 * shop like the conversation. Relevance selection is keyword + recency for
 * now (no vector DB); it's cheap and good enough to surface the handful of
 * memories worth injecting for a given question.
 */
@Injectable()
export class AiMemoryService {
  constructor(private readonly prisma: PrismaService) {}

  private static readonly VALID_TYPES = [
    'preference',
    'customer',
    'policy',
    'fact',
  ];

  async list(tenantId: string) {
    return this.prisma.aiMemory.findMany({
      where: { tenantId },
      orderBy: { updatedAt: 'desc' },
    });
  }

  async save(params: {
    tenantId: string;
    type: string;
    title: string;
    content: string;
  }) {
    const type = AiMemoryService.VALID_TYPES.includes(params.type)
      ? params.type
      : 'fact';
    return this.prisma.aiMemory.create({
      data: {
        tenantId: params.tenantId,
        type,
        title: params.title.slice(0, 200),
        content: params.content.slice(0, 2000),
      },
    });
  }

  async remove(tenantId: string, id: string) {
    await this.prisma.aiMemory.deleteMany({ where: { id, tenantId } });
  }

  /**
   * Pick the memories most relevant to [question] to inject as AI context.
   * Scores each memory by how many question keywords appear in its
   * title/content, breaking ties by recency. Always returns at most
   * [limit]; when the question has no useful keywords, returns the most
   * recent memories so the AI still has durable context.
   */
  async selectRelevant(
    tenantId: string,
    question: string,
    limit = 5,
  ): Promise<Array<{ type: string; title: string; content: string }>> {
    const all = await this.prisma.aiMemory.findMany({
      where: { tenantId },
      orderBy: { updatedAt: 'desc' },
      take: 100,
    });
    if (all.length === 0) return [];

    const keywords = (question || '')
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter((w) => w.length > 3);

    const scored = all.map((m, index) => {
      const hay = `${m.title} ${m.content}`.toLowerCase();
      let score = 0;
      for (const kw of keywords) {
        if (hay.includes(kw)) score += 1;
      }
      // Slight recency bias so ties favour newer memories.
      const recency = (all.length - index) / all.length;
      return { m, score: score + recency * 0.1 };
    });

    scored.sort((a, b) => b.score - a.score);
    // If nothing matched keywords at all, fall back to most-recent few.
    const anyMatch = scored.some((s) => s.score >= 1);
    const picked = (anyMatch ? scored.filter((s) => s.score >= 1) : scored)
      .slice(0, limit)
      .map((s) => ({ type: s.m.type, title: s.m.title, content: s.m.content }));
    return picked;
  }
}
