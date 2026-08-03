import { ConfigService } from '@nestjs/config';
import { ServiceUnavailableException } from '@nestjs/common';
import { EmailOtpService } from './email-otp.service';

describe('EmailOtpService', () => {
  const delivery = { sendOtp: jest.fn().mockResolvedValue(undefined) };
  const config = { get: jest.fn((key: string) => (key === 'OTP_PEPPER' ? 'test-pepper-which-is-long-enough' : undefined)) } as unknown as ConfigService;
  let prisma: any;

  beforeEach(() => {
    jest.clearAllMocks();
    prisma = {
      emailOtpChallenge: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockImplementation(({ data }: any) => Promise.resolve({
          id: 'challenge-opaque-id',
          ...data,
        })),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
  });

  it('stores only a peppered HMAC, sends the raw code once, and never returns it', async () => {
    const service = new EmailOtpService(prisma, config, delivery as any);

    const result = await service.request({
      purpose: 'WORKSPACE_CREATION',
      email: 'Owner@Example.test',
    });

    expect(result).toEqual({ accepted: true, challengeId: 'challenge-opaque-id' });
    const stored = prisma.emailOtpChallenge.create.mock.calls[0][0].data;
    expect(stored.email).toBe('owner@example.test');
    expect(stored.codeHash).toMatch(/^[a-f0-9]{64}$/);
    expect(Object.values(stored)).not.toContain(expect.stringMatching(/^\d{6,8}$/));
    expect(delivery.sendOtp).toHaveBeenCalledWith(expect.objectContaining({
      to: 'owner@example.test',
      code: expect.stringMatching(/^\d{8}$/),
    }));
  });

  it('atomically consumes a matching unexpired challenge once', async () => {
    const service = new EmailOtpService(prisma, config, delivery as any);
    await service.request({ purpose: 'WORKSPACE_CREATION', email: 'owner@example.test' });
    const code = delivery.sendOtp.mock.calls[0][0].code;

    await expect(service.consume({
      challengeId: 'challenge-opaque-id',
      purpose: 'WORKSPACE_CREATION',
      email: 'owner@example.test',
      code,
    })).resolves.toEqual({ consumed: true });

    expect(prisma.emailOtpChallenge.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({
        id: 'challenge-opaque-id',
        purpose: 'WORKSPACE_CREATION',
        consumedAt: null,
        attempts: { lt: 5 },
      }),
      data: { consumedAt: expect.any(Date) },
    }));
  });

  it('fails clearly rather than pretending delivery worked when OTP configuration is missing', async () => {
    const unavailableConfig = { get: jest.fn().mockReturnValue(undefined) } as unknown as ConfigService;
    const service = new EmailOtpService(prisma, unavailableConfig, delivery as any);

    await expect(service.request({ purpose: 'WORKSPACE_CREATION', email: 'owner@example.test' }))
      .rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(prisma.emailOtpChallenge.create).not.toHaveBeenCalled();
  });
});
