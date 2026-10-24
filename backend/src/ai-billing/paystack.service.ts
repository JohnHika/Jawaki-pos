import { Injectable, Logger, HttpException, HttpStatus } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

interface PaystackAuthorization {
  authorization_code?: string;
  card_type?: string;
  last4?: string;
  exp_month?: string;
  exp_year?: string;
  reusable: boolean;
}

interface PaystackCustomer {
  customer_code?: string;
  email?: string;
}

interface PaystackChargeData {
  reference: string;
  status: string;
  amount: number;
  currency?: string;
  channel?: string;
  id?: number | string;
  paid_at?: string | null;
  metadata?: Record<string, unknown> | string;
  customer?: PaystackCustomer;
  authorization?: PaystackAuthorization;
  subaccount?: { subaccount_code?: string } | string | null;
}

export interface PaystackBank { name: string; code: string; type?: string; currency?: string; active?: boolean }

interface PaystackSubaccount {
  subaccount_code: string;
  account_name?: string;
  account_number?: string;
  settlement_bank?: string;
  currency?: string;
  active?: boolean;
  is_verified?: boolean;
}

interface PaystackApiResponse<T> {
  status: boolean;
  message: string;
  data: T;
  meta?: {
    page?: number;
    pageCount?: number;
    perPage?: number;
    total?: number;
  };
}

/**
 * Thin wrapper around the Paystack REST API. Axon uses hosted transactions
 * for activation and monthly invoices; the AI billing flow also uses saved
 * card authorizations for its separate recurring charges.
 */
@Injectable()
export class PaystackService {
  private readonly logger = new Logger(PaystackService.name);
  private readonly baseUrl = 'https://api.paystack.co';
  private readonly secretKey: string;
  private readonly merchantPayerEmail: string;

  constructor(private readonly configService: ConfigService) {
    this.secretKey = this.configService.get<string>('PAYSTACK_SECRET_KEY') || '';
    this.merchantPayerEmail = (
      this.configService.get<string>('PAYSTACK_PAYER_EMAIL') || 'billing@archeaxon.com'
    ).trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.merchantPayerEmail)) {
      throw new Error('PAYSTACK_PAYER_EMAIL must be a valid email address');
    }
    if (!this.secretKey) {
      this.logger.warn(
        'PAYSTACK_SECRET_KEY not set — card payments and auto-renewal will fail until configured.',
      );
    }
  }

  isConfigured(): boolean {
    return Boolean(this.secretKey);
  }

  getMerchantPayerEmail(): string {
    return this.merchantPayerEmail;
  }

  async listKenyanBanks(): Promise<PaystackBank[]> {
    const perPage = 100;
    const maxPages = 100;
    const banks: PaystackBank[] = [];

    for (let page = 1; page <= maxPages; page += 1) {
      const response = await this.request<PaystackBank[]>(
        `/bank?country=kenya&currency=KES&perPage=${perPage}&page=${page}`,
        { method: 'GET' },
      );
      banks.push(...response.data);

      const pageCount = response.meta?.pageCount;
      const hasMorePages = typeof pageCount === 'number' && Number.isFinite(pageCount)
        ? page < pageCount
        : response.data.length >= perPage;
      if (!hasMorePages) break;

      if (page === maxPages) {
        throw new HttpException(
          'Paystack returned an unexpectedly large bank list. Try again later.',
          HttpStatus.BAD_GATEWAY,
        );
      }
    }

    // The Kenya/KES catalogue also contains M-Pesa, Airtel and other payment
    // channels. A Paystack subaccount needs an actual KEPSS bank settlement
    // account, so include every active KEPSS bank and exclude those channels.
    const uniqueBanks = new Map<string, PaystackBank>();
    for (const bank of banks) {
      if (bank.code && bank.name && bank.type === 'kepss' && bank.active !== false &&
        !uniqueBanks.has(bank.code)) {
        uniqueBanks.set(bank.code, bank);
      }
    }
    return [...uniqueBanks.values()].sort((a, b) => a.name.localeCompare(b.name));
  }

  async createMerchantSubaccount(input: {
    businessName: string;
    bankCode: string;
    accountNumber: string;
    contactEmail: string;
  }): Promise<PaystackSubaccount> {
    const response = await this.request<PaystackSubaccount>('/subaccount', {
      method: 'POST',
      body: {
        business_name: input.businessName,
        bank_code: input.bankCode,
        settlement_bank: input.bankCode,
        account_number: input.accountNumber,
        percentage_charge: 0,
        primary_contact_email: input.contactEmail,
      },
    });
    return response.data;
  }

  async getMerchantSubaccount(subaccountCode: string): Promise<PaystackSubaccount> {
    const response = await this.request<PaystackSubaccount>(
      `/subaccount/${encodeURIComponent(subaccountCode)}`,
      { method: 'GET' },
    );
    return response.data;
  }

  async updateMerchantSubaccount(subaccountCode: string, input: {
    businessName: string;
    bankCode: string;
    accountNumber: string;
    contactEmail: string;
  }): Promise<PaystackSubaccount> {
    const response = await this.request<PaystackSubaccount>(
      `/subaccount/${encodeURIComponent(subaccountCode)}`,
      {
        method: 'PUT',
        body: {
          business_name: input.businessName,
          settlement_bank: input.bankCode,
          account_number: input.accountNumber,
          percentage_charge: 0,
          primary_contact_email: input.contactEmail,
          active: true,
        },
      },
    );
    return response.data;
  }

  async createMerchantMpesaCharge(input: {
    email: string;
    amountKes: number;
    phone: string;
    reference: string;
    subaccountCode: string;
    tenantId: string;
    businessName?: string;
  }): Promise<{ reference: string; status: string; display_text?: string }> {
    const businessName = input.businessName?.trim();
    const response = await this.request<{ reference: string; status: string; display_text?: string }>('/charge', {
      method: 'POST',
      body: {
        email: input.email,
        amount: this.toSubunits(input.amountKes),
        currency: 'KES',
        reference: input.reference,
        mobile_money: { phone: input.phone, provider: 'mpesa' },
        subaccount: input.subaccountCode,
        bearer: 'subaccount',
        metadata: {
          product: 'counterbase_merchant_sale',
          tenantId: input.tenantId,
          ...(businessName
            ? {
                shopName: businessName,
                custom_fields: [
                  {
                    display_name: 'Shop',
                    variable_name: 'shop_name',
                    value: businessName,
                  },
                ],
              }
            : {}),
        },
      },
    });
    return response.data;
  }

  /** Start a checkout for a fresh subscription payment. */
  async initializeTransaction(params: {
    email: string;
    amountKes: number;
    reference: string;
    metadata: Record<string, unknown>;
    callbackUrl?: string;
    useEnabledChannels?: boolean;
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
        ...(params.useEnabledChannels ? {} : { channels: ['card'] }),
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

  /** Paystack expects KES amounts in cents. */
  private toSubunits(amountKes: number): number {
    return Math.round(amountKes * 100);
  }

  private async request<T>(
    path: string,
    options: { method: 'GET' | 'POST' | 'PUT'; body?: Record<string, unknown> },
  ): Promise<PaystackApiResponse<T>> {
    if (!this.secretKey) {
      throw new HttpException(
        'Paystack is not configured on this server.',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }

    const response = await fetch(`${this.baseUrl}${path}`, {
      method: options.method,
      signal: AbortSignal.timeout(15000),
      headers: {
        Authorization: `Bearer ${this.secretKey}`,
        'Content-Type': 'application/json',
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });

    let payload: PaystackApiResponse<T>;
    try {
      payload = (await response.json()) as PaystackApiResponse<T>;
    } catch {
      this.logger.error(
        `Paystack returned an unreadable response: ${options.method} ${path} — HTTP ${response.status}`,
      );
      throw new HttpException(
        'Paystack returned an unreadable response. Check the payment status before retrying.',
        HttpStatus.BAD_GATEWAY,
      );
    }

    if (!response.ok || !payload.status) {
      // Provider errors help diagnose channel and account setup problems, but
      // can echo customer phone, email, or bank details.
      const merchantPaymentRequest = path.startsWith('/subaccount') || path === '/charge';
      const safeMessage = this.safeProviderMessage(payload.message);
      this.logger.error(
        `Paystack request failed: ${options.method} ${path} — HTTP ${response.status}` +
          (safeMessage ? ` — ${safeMessage}` : ''),
      );
      throw new HttpException(
        merchantPaymentRequest
          ? (path === '/subaccount'
            ? this.merchantPaymentFailure('payout', response.status, safeMessage)
            : this.merchantPaymentFailure('mpesa', response.status, safeMessage))
          : (safeMessage || 'Paystack request failed'),
        response.status || HttpStatus.BAD_GATEWAY,
      );
    }

    return payload;
  }

  private merchantPaymentFailure(kind: 'payout' | 'mpesa', status: number, detail: string) {
    if (status === HttpStatus.UNAUTHORIZED) {
      return 'The payment provider rejected its server credentials. Contact Counterbase support.';
    }
    if (status === HttpStatus.FORBIDDEN) {
      return kind === 'mpesa'
        ? 'M-Pesa is not enabled for this Paystack business. Check that the live M-Pesa channel is approved.'
        : 'Paystack cannot create this payout account. Check the business account setup.';
    }
    if (detail) {
      return kind === 'mpesa'
        ? `Paystack rejected this M-Pesa request: ${detail}`
        : `Paystack could not verify that payout account: ${detail}`;
    }
    return kind === 'mpesa'
      ? 'Paystack could not start this M-Pesa payment. Check the customer phone number and try again.'
      : 'Paystack could not verify that payout account. Check the bank and account number.';
  }

  private safeProviderMessage(message: unknown): string {
    if (typeof message !== 'string') return '';
    return message
      .replace(/[\w.!#$%&'*+/=?^`{|}~-]+@[\w.-]+\.[A-Za-z]{2,}/g, '[email]')
      .replace(/\b(?:sk|pk)_(?:live|test)_[A-Za-z0-9]+\b/gi, '[key]')
      .replace(/\+?\d[\d\s()-]{6,}\d/g, '[number]')
      .replace(/[\r\n\t]+/g, ' ')
      .replace(/\s{2,}/g, ' ')
      .trim()
      .slice(0, 180);
  }
}
