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
 *   EMAIL_FROM       — From address (e.g. "Counterbase <noreply@...>")
 *
 * Optional Zoho CPaaS / ZeptoMail API delivery (recommended on hosts that
 * block SMTP):
 *   ZEPTOMAIL_SEND_API_KEY — Agent-specific send API key
 *   ZEPTOMAIL_API_URL      — Regional send endpoint; defaults to the US API
 */
@Injectable()
export class TransactionalEmailService {
  constructor(private readonly config: ConfigService) {}

  async sendOtp(message: OtpEmailMessage): Promise<void> {
    const zeptoMailKey = this.config.get<string>('ZEPTOMAIL_SEND_API_KEY');
    if (zeptoMailKey) {
      await this.sendWithZeptoMail(message, zeptoMailKey);
      return;
    }

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
      subject: 'Your Counterbase verification code',
      text: `Your Counterbase verification code is ${message.code}. It expires in 10 minutes.`,
    });
  }

  private async sendWithZeptoMail(
    message: OtpEmailMessage,
    apiKey: string,
  ): Promise<void> {
    const from = this.config.get<string>('EMAIL_FROM');
    const endpoint =
      this.config.get<string>('ZEPTOMAIL_API_URL')?.trim() ||
      'https://cpaas.zoho.com/v1.1/email';

    if (!from) {
      throw new ServiceUnavailableException(
        'Email verification is temporarily unavailable',
      );
    }

    let parsedEndpoint: URL;
    try {
      parsedEndpoint = new URL(endpoint);
    } catch {
      throw new ServiceUnavailableException(
        'Email verification is temporarily unavailable',
      );
    }
    const allowedHosts = new Set([
      'cpaas.zoho.com',
      'cpaas.zoho.eu',
      'cpaas.zoho.com.au',
      'cpaas.zoho.in',
      'cpaas.zoho.com.cn',
      'cpaas.zoho.jp',
    ]);
    if (
      parsedEndpoint.protocol !== 'https:' ||
      !allowedHosts.has(parsedEndpoint.hostname) ||
      parsedEndpoint.pathname !== '/v1.1/email' ||
      parsedEndpoint.search ||
      parsedEndpoint.hash ||
      parsedEndpoint.username ||
      parsedEndpoint.password
    ) {
      throw new ServiceUnavailableException(
        'Email verification is temporarily unavailable',
      );
    }

    const sender = this.parseSender(from);
    try {
      const response = await fetch(parsedEndpoint, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Zoho-enczapikey ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: sender,
          to: [{ email_address: { address: message.to } }],
          subject: 'Your Counterbase verification code',
          textbody: `Your Counterbase verification code is ${message.code}. It expires in 10 minutes.`,
        }),
        signal: AbortSignal.timeout(10_000),
      });

      if (!response.ok) {
        throw new ServiceUnavailableException(
          'Email verification is temporarily unavailable',
        );
      }
    } catch (error) {
      if (error instanceof ServiceUnavailableException) throw error;
      throw new ServiceUnavailableException(
        'Email verification is temporarily unavailable',
      );
    }
  }

  private parseSender(from: string): { address: string; name?: string } {
    const match = from.match(/^\s*(.*?)\s*<([^<>]+)>\s*$/);
    if (!match) return { address: from.trim() };

    const name = match[1].trim().replace(/^"|"$/g, '');
    return {
      address: match[2].trim(),
      ...(name ? { name } : {}),
    };
  }
}
