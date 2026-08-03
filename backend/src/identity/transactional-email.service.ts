import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';

export interface OtpEmailMessage {
  to: string;
  code: string;
  purpose: string;
}

/**
 * Minimal provider-neutral transactional delivery boundary. Deployment chooses
 * the provider through EMAIL_DELIVERY_URL/EMAIL_FROM and optional
 * EMAIL_DELIVERY_API_KEY; no credentials or provider key are embedded here.
 */
@Injectable()
export class TransactionalEmailService {
  constructor(private readonly config: ConfigService) {}

  async sendOtp(message: OtpEmailMessage): Promise<void> {
    const url = this.config.get<string>('EMAIL_DELIVERY_URL');
    const from = this.config.get<string>('EMAIL_FROM');
    const apiKey = this.config.get<string>('EMAIL_DELIVERY_API_KEY');
    if (!url || !from) {
      throw new ServiceUnavailableException('Email verification is temporarily unavailable');
    }

    await axios.post(
      url,
      {
        from,
        to: message.to,
        subject: 'Your Axon POS verification code',
        text: `Your Axon POS verification code is ${message.code}. It expires in 10 minutes.`,
      },
      {
        headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : undefined,
        timeout: 10_000,
      },
    );
  }
}
