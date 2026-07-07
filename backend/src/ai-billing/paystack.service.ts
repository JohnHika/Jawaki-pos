import { Injectable, Logger, HttpException, HttpStatus } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

interface PaystackAuthorization {
  authorization_code: string;
  card_type?: string;
  last4?: string;
  exp_month?: string;
  exp_year?: string;
  reusable: boolean;
}

interface PaystackCustomer {
  customer_code: string;
  email: string;
}

interface PaystackChargeData {
  reference: string;
  status: string;
  amount: number;
  customer: PaystackCustomer;
  authorization: PaystackAuthorization;
}

interface PaystackApiResponse<T> {
  status: boolean;
  message: string;
  data: T;
}

/**
 * Thin wrapper around the Paystack REST API. Used for card-based AI
 * subscription billing: the customer pays once via a Paystack checkout,
 * we keep the resulting `authorization_code`, and the renewal cron reuses
 * it to charge the same card again each month — no customer action needed.
 */
@Injectable()
export class PaystackService {
  private readonly logger = new Logger(PaystackService.name);
  private readonly baseUrl = 'https://api.paystack.co';
  private readonly secretKey: string;

  constructor(private readonly configService: ConfigService) {
    this.secretKey = this.configService.get<string>('PAYSTACK_SECRET_KEY') || '';
    if (!this.secretKey) {
      this.logger.warn(
        'PAYSTACK_SECRET_KEY not set — card payments and auto-renewal will fail until configured.',
      );
    }
  }

  isConfigured(): boolean {
    return Boolean(this.secretKey);
  }

  /** Start a checkout for a fresh subscription payment. */
  async initializeTransaction(params: {
    email: string;
    amountKes: number;
    reference: string;
    metadata: Record<string, unknown>;
    callbackUrl?: string;
  }): Promise<{ authorizationUrl: string; accessCode: string; reference: string }> {
    const response = await this.request<{
      authorization_url: string;
      access_code: string;
      reference: string;
    }>('/transaction/initialize', {
      method: 'POST',
      body: {
        email: params.email,
        amount: this.toSubunits(params.amountKes),
        currency: 'KES',
        reference: params.reference,
        metadata: params.metadata,
        callback_url: params.callbackUrl,
        channels: ['card'],
      },
    });

    return {
      authorizationUrl: response.data.authorization_url,
      accessCode: response.data.access_code,
      reference: response.data.reference,
    };
  }

  /** Confirm a transaction's outcome (used from the webhook and as a fallback poll). */
  async verifyTransaction(reference: string): Promise<PaystackChargeData> {
    const response = await this.request<PaystackChargeData>(
      `/transaction/verify/${encodeURIComponent(reference)}`,
      { method: 'GET' },
    );
    return response.data;
  }

  /** Charge a previously-saved card authorization — this is the auto-renewal step. */
  async chargeAuthorization(params: {
    email: string;
    authorizationCode: string;
    amountKes: number;
    reference: string;
    metadata: Record<string, unknown>;
  }): Promise<PaystackChargeData> {
    const response = await this.request<PaystackChargeData>(
      '/transaction/charge_authorization',
      {
        method: 'POST',
        body: {
          email: params.email,
          amount: this.toSubunits(params.amountKes),
          authorization_code: params.authorizationCode,
          currency: 'KES',
          reference: params.reference,
          metadata: params.metadata,
        },
      },
    );
    return response.data;
  }

  /** Paystack sends amounts as the smallest currency unit; KES has no minor unit in Paystack's model, so this is a 1:1 pass-through kept explicit for clarity and future currency changes. */
  private toSubunits(amountKes: number): number {
    return Math.round(amountKes * 100);
  }

  private async request<T>(
    path: string,
    options: { method: 'GET' | 'POST'; body?: Record<string, unknown> },
  ): Promise<PaystackApiResponse<T>> {
    if (!this.secretKey) {
      throw new HttpException(
        'Paystack is not configured on this server.',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }

    const response = await fetch(`${this.baseUrl}${path}`, {
      method: options.method,
      headers: {
        Authorization: `Bearer ${this.secretKey}`,
        'Content-Type': 'application/json',
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });

    const payload = (await response.json()) as PaystackApiResponse<T>;

    if (!response.ok || !payload.status) {
      this.logger.error(
        `Paystack request failed: ${options.method} ${path} — ${payload.message}`,
      );
      throw new HttpException(
        payload.message || 'Paystack request failed',
        response.status || HttpStatus.BAD_GATEWAY,
      );
    }

    return payload;
  }
}
