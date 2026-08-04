import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';

export interface OtpEmailMessage {
  to: string;
  code: string;
  purpose: string;
}

/**
 * Nodemailer-based transactional email delivery. Configured entirely through
 * environment variables — no credentials in source.
 *
 * Required env vars:
 *   EMAIL_HOST       — SMTP host (e.g. smtp.gmail.com)
 *   EMAIL_PORT       — SMTP port (e.g. 587)
 *   EMAIL_USER       — SMTP username
 *   EMAIL_PASS       — SMTP password or app password
 *   EMAIL_FROM       — From address (e.g. "Axon POS <noreply@...>")
 */
@Injectable()
export class TransactionalEmailService {
  constructor(private readonly config: ConfigService) {}

  async sendOtp(message: OtpEmailMessage): Promise<void> {
    const host = this.config.get<string>('EMAIL_HOST');
    const port = this.config.get<number>('EMAIL_PORT');
    const user = this.config.get<string>('EMAIL_USER');
    const pass = this.config.get<string>('EMAIL_PASS');
    const from = this.config.get<string>('EMAIL_FROM');

    if (!host || !port || !user || !pass || !from) {
      throw new ServiceUnavailableException(
        'Email verification is temporarily unavailable',
      );
    }

    const transporter = nodemailer.createTransport({
      host,
      port,
      secure: port === 465,
      auth: { user, pass },
    });

    await transporter.sendMail({
      from,
      to: message.to,
      subject: 'Your Axon POS verification code',
      text: `Your Axon POS verification code is ${message.code}. It expires in 10 minutes.`,
    });
  }
}
