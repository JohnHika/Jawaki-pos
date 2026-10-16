import { AiConversationService } from './ai-conversation.service';

describe('AiConversationService.getMessages', () => {
  const briefPrompt =
    "Give me a short 2-3 sentence brief on today's business performance and one concrete suggestion.";

  it("hides the dashboard brief's canned prompt and its answer", async () => {
    const rows = [
      { id: '4', role: 'assistant', content: 'Sales are up.', createdAt: new Date(4) },
      { id: '3', role: 'user', content: 'How much stock do I have?', createdAt: new Date(3) },
      { id: '2', role: 'assistant', content: 'Brief reply', createdAt: new Date(2) },
      { id: '1', role: 'user', content: briefPrompt, createdAt: new Date(1) },
    ];
    const prisma: any = {
      aiConversation: { findFirst: jest.fn().mockResolvedValue({ id: 'c1' }) },
      aiMessage: { findMany: jest.fn().mockResolvedValue(rows) },
    };
    const service = new AiConversationService(prisma);

    const { messages } = await service.getMessages('t1', null);

    expect(messages.map((m: any) => m.id)).toEqual(['3', '4']);
  });
});
