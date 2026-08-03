import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, randomInt } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { TransactionalEmailService } from './transactional-email.service';

export const OTP_TTL_MS = 10 * 60 * 1000;
export const OTP_RESEND_MS = 60 * 1000;
export const OTP_MAX_ATTEMPTS = 5;

export type EmailOtpPurpose = 'WORKSPACE_CREATION' | 'STAFF_INVITE';

@Injectable()
export class EmailOtpService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly delivery: TransactionalEmailService,
  ) {}

  async request(input: { purpose: EmailOtpPurpose; email: string; tenantId?: string }) {
    const pepper = this.requirePepper();
    const email = this.normalizeEmail(input.email);
    const now = new Date();
    const existing = await this.prisma.emailOtpChallenge.findFirst({
      where: { purpose: input.purpose, email, tenantId: input.tenantId ?? null, consumedAt: null, expiresAt: { gt: now } },
      orderBy: { createdAt: 'desc' },
    });

    // Return the same generic acceptance response while the send cooldown is
    // active. This avoids turning the endpoint into an account oracle.
    if (existing && existing.resendAvailableAt > now) {
      return { accepted: true, challengeId: existing.id };
    }

    const code = String(randomInt(10_000_000, 100_000_000));
    const challenge = await this.prisma.emailOtpChallenge.create({
      data: {
        purpose: input.purpose,
        email,
        tenantId: input.tenantId,
        codeHash: this.hashCode(pepper, code),
        expiresAt: new Date(now.getTime() + OTP_TTL_MS),
        resendAvailableAt: new Date(now.getTime() + OTP_RESEND_MS),
      },
    });

    try {
      await this.delivery.sendOtp({ to: email, code, purpose: input.purpose });
    } catch (error) {
      // Persist no usable challenge when transport is unavailable. Do not leak
      // provider details or claim a message was sent.
      await this.prisma.emailOtpChallenge.updateMany({
        where: { id: challenge.id, consumedAt: null },
        data: { consumedAt: new Date() },
      });
      if (error instanceof ServiceUnavailableException) throw error;
      throw new ServiceUnavailableException('Email verification is temporarily unavailable');
    }

    return { accepted: true, challengeId: challenge.id };
  }

  async consume(input: { challengeId: string; purpose: EmailOtpPurpose; email: string; tenantId?: string; code: string }) {
    const pepper = this.requirePepper();
    const now = new Date();
    const email = this.normalizeEmail(input.email);
    const codeHash = this.hashCode(pepper, input.code);
    const consumed = await this.prisma.emailOtpChallenge.updateMany({
      where: {
        id: input.challengeId,
        purpose: input.purpose,
        email,
        tenantId: input.tenantId ?? null,
        codeHash,
        consumedAt: null,
        expiresAt: { gt: now },
        attempts: { lt: OTP_MAX_ATTEMPTS },
      },
      data: { consumedAt: now },
    });
    if (consumed.count === 1) return { consumed: true };

    // A failed code consumes an attempt only while the challenge is still
    // viable. The matching consume update above is the single atomic winner.
    await this.prisma.emailOtpChallenge.updateMany({
      where: {
        id: input.challengeId,
        purpose: input.purpose,
        email,
        tenantId: input.tenantId ?? null,
        consumedAt: null,
        expiresAt: { gt: now },
        attempts: { lt: OTP_MAX_ATTEMPTS },
      },
      data: { attempts: { increment: 1 } },
    });
    return { consumed: false };
  }

  private requirePepper(): string {
    const pepper = this.config.get<string>('OTP_PEPPER');
    if (!pepper || pepper.length < 16) {
      throw new ServiceUnavailableException('Email verification is temporarily unavailable');
    }
    return pepper;
  }

  private hashCode(pepper: string, code: string) {
    return createHmac('sha256', pepper).update(code).digest('hex');
  }

  private normalizeEmail(email: string) {
    return email.trim().toLowerCase();
  }
}
