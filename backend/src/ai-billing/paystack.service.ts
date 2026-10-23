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
  currency?: string;
  active?: boolean;
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

  async createMerchantMpesaCharge(input: {
    email: string;
    amountKes: number;
    phone: string;
    reference: string;
    subaccountCode: string;
    tenantId: string;
  }): Promise<{ reference: string; status: string; display_text?: string }> {
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
        metadata: { product: 'counterbase_merchant_sale', tenantId: input.tenantId },
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
      signal: AbortSignal.timeout(15000),
      headers: {
        Authorization: `Bearer ${this.secretKey}`,
        'Content-Type': 'application/json',
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });

    const payload = (await response.json()) as PaystackApiResponse<T>;

    if (!response.ok || !payload.status) {
      // Provider error text can echo submitted bank or phone details.
      const merchantPaymentRequest = path === '/subaccount' || path === '/charge';
      this.logger.error(
        merchantPaymentRequest
          ? `Paystack request failed: ${options.method} ${path} — HTTP ${response.status}`
          : `Paystack request failed: ${options.method} ${path} — ${payload.message}`,
      );
      throw new HttpException(
        merchantPaymentRequest
          ? (path === '/subaccount'
            ? 'Paystack could not verify that payout account. Check the bank and account number.'
            : 'Paystack could not start this M-Pesa payment.')
          : (payload.message || 'Paystack request failed'),
        response.status || HttpStatus.BAD_GATEWAY,
      );
    }

    return payload;
  }
}
