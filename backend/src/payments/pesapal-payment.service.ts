import {
  BadGatewayException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import axios, { AxiosError } from "axios";
import { createHash, createHmac } from "crypto";

/**
 * Pesapal API 3.0 client.
 *
 * Auth: Pesapal 3.0 issues a bearer token via an OAuth1-signed request
 * (consumer key = token, consumer secret = signature base) to
 * POST /api/AuthSetup/RequestToken. All subsequent calls use the bearer token.
 *
 * Docs: developer.pesapal.com
 *   POST /api/AuthSetup/RequestToken
 *   POST /api/Transactions/SubmitOrderRequest
 *   GET  /api/Transactions/GetTransactionStatus?orderTrackingId=...
 */
@Injectable()
export class PesapalPaymentService {
  private readonly logger = new Logger(PesapalPaymentService.name);
  private accessToken?: { value: string; expiresAt: number };

  constructor(private readonly config: ConfigService) {}

  isConfigured(): boolean {
    return [
      "PESAPAL_CONSUMER_KEY",
      "PESAPAL_CONSUMER_SECRET",
      "PESAPAL_IPN_URL",
    ].every((key) => Boolean(this.config.get<string>(key)?.trim()));
  }

  /**
   * Builds the recurring SubmitOrderRequest payload for a card subscription.
   * The customer opts in to auto-renew on the Pesapal iframe; Pesapal
   * tokenizes the card — raw card data never touches this backend.
   */
  buildRecurringOrderRequest(input: {
    accountNumber: string;
    amount: number;
    description: string;
    billingCycle: "MONTHLY" | "YEARLY";
    startDate: Date;
    endDate: Date;
    emailAddress?: string | null;
    phoneNumber?: string | null;
    firstName?: string | null;
    lastName?: string | null;
    callbackUrl?: string | null;
  }) {
    const notificationId = this.required("PESAPAL_IPN_ID");
    const callbackUrl = input.callbackUrl?.trim() || this.required("PESAPAL_CALLBACK_URL");
    if (callbackUrl && !/^https?:\/\//.test(callbackUrl)) {
      throw new BadGatewayException("Pesapal callback URL must be http(s)");
    }

    const subscriptionDetails = {
      start_date: this.pesapalDate(input.startDate),
      end_date: this.pesapalDate(input.endDate),
      frequency: input.billingCycle === "YEARLY" ? "YEARLY" : "MONTHLY",
    };

    return {
      id: input.accountNumber,
      currency: "KES",
      amount: Number(input.amount.toFixed(2)),
      description: input.description,
      callback_url: callbackUrl,
      notification_id: notificationId,
      // account_number is what Pesapal echoes back as
      // OrderMerchantReference on the recurring IPN.
      account_number: input.accountNumber,
      subscription_details: subscriptionDetails,
      ...(input.emailAddress ? { email_address: input.emailAddress } : {}),
      ...(input.phoneNumber ? { phone_number: input.phoneNumber } : {}),
      ...(input.firstName ? { first_name: input.firstName } : {}),
      ...(input.lastName ? { last_name: input.lastName } : {}),
    };
  }

  /** Submits the order and returns the Pesapal redirect (iframe) URL. */
  async submitOrderRequest(payload: Record<string, unknown>) {
    const response = await this.authedPost("/api/Transactions/SubmitOrderRequest", payload);
    const orderTrackingId = response?.order_tracking_id;
    if (!orderTrackingId) {
      this.logger.error(`Pesapal SubmitOrderRequest returned no tracking id: ${JSON.stringify(response)}`);
      throw new BadGatewayException("Pesapal did not return an order tracking id");
    }
    return {
      orderTrackingId: String(orderTrackingId),
      redirectUrl: String(response?.redirect_url ?? ""),
      merchantReference: String(response?.merchant_reference ?? payload["account_number"] ?? ""),
      status: response?.status ?? null,
    };
  }

  /**
   * Server-to-server GetTransactionStatus. The recurring IPN carries no
   * payment details, so this authenticated query is the only source of truth
   * for settling an invoice.
   */
  async getTransactionStatus(orderTrackingId: string) {
    const response = await this.authedGet(
      `/api/Transactions/GetTransactionStatus?orderTrackingId=${encodeURIComponent(orderTrackingId)}`,
    );
    const payment = Array.isArray(response)
      ? response[0]
      : response?.payment_status_details ?? response;
    const status = String(
      response?.payment_status ?? payment?.payment_status ?? "",
    ).toUpperCase();
    const subscriptionInfo = response?.subscription_transaction_info ?? null;
    return {
      raw: response,
      orderTrackingId: String(response?.order_tracking_id ?? orderTrackingId),
      paymentStatus: status, // "" | PENDING | COMPLETED | FAILED | ... per Pesapal
      paymentStatusCode: Number(response?.payment_status_code ?? 0),
      paymentMethod: response?.payment_method ?? null,
      amount: response?.amount != null ? Number(response.amount) : null,
      currency: response?.currency ?? null,
      confirmationCode: response?.confirmation_code ?? null,
      merchantReference: response?.merchant_reference ?? null,
      accountNumberRef: response?.account_number ?? null,
      subscriptionTransactionInfo: subscriptionInfo
        ? {
            accountReference: String(subscriptionInfo.account_reference ?? ""),
            amount: subscriptionInfo.amount != null ? Number(subscriptionInfo.amount) : null,
            correlationId: String(subscriptionInfo.correlation_id ?? ""),
          }
        : null,
    };
  }

  /** RequestToken with an in-memory cache (tokens last ~5 min). */
  private async token(): Promise<string> {
    if (this.accessToken && this.accessToken.expiresAt > Date.now() + 30_000) {
      return this.accessToken.value;
    }
    const consumerKey = this.required("PESAPAL_CONSUMER_KEY");
    const consumerSecret = this.required("PESAPAL_CONSUMER_SECRET");

    // OAuth1-style signed request per Pesapal 3.0 AuthSetup.
    const nonce = createHash("sha256")
      .update(`${Date.now()}:${Math.random()}`)
      .digest("hex")
      .slice(0, 32);
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const oauth = {
      oauth_consumer_key: consumerKey,
      oauth_nonce: nonce,
      oauth_signature_method: "HMAC-SHA256",
      oauth_timestamp: timestamp,
      oauth_version: "1.0",
    };
    const baseUrl = this.baseUrl();
    const encodedParams = Object.keys(oauth)
      .sort()
      .map((k) => `${this.rfc3986(k)}=${this.rfc3986(String(oauth[k as keyof typeof oauth]))}`)
      .join("&");
    const signatureBase = ["POST", this.rfc3986(baseUrl + "/api/AuthSetup/RequestToken"), this.rfc3986(encodedParams)].join("&");
    const signature = createHmac("sha256", consumerSecret).update(signatureBase).digest("base64");

    try {
      const response = await axios.post(
        `${baseUrl}/api/AuthSetup/RequestToken`,
        {
          consumer_id: consumerKey,
          consumer_secret: consumerSecret,
        },
        {
          headers: {
            "Content-Type": "application/json",
            Accept: "application/json",
            Authorization: `OAuth oauth_consumer_key="${this.rfc3986(consumerKey)}",oauth_signature_method="HMAC-SHA256",oauth_timestamp="${timestamp}",oauth_nonce="${nonce}",oauth_version="1.0",oauth_signature="${this.rfc3986(signature)}"`,
          },
          timeout: 15000,
        },
      );
      const value = response.data?.token;
      if (!value) throw new Error("No token returned by Pesapal");
      this.accessToken = {
        value: String(value),
        expiresAt: this.parseExpiry(response.data?.expires_in),
      };
      return this.accessToken.value;
    } catch (error) {
      this.logger.error(`Pesapal authentication failed: ${this.safeError(error)}`);
      throw new ServiceUnavailableException("Pesapal is unavailable");
    }
  }

  private async authedPost(path: string, body: Record<string, unknown>) {
    this.assertConfigured();
    try {
      const response = await axios.post(`${this.baseUrl()}${path}`, body, {
        headers: {
          Authorization: `Bearer ${await this.token()}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        timeout: 20000,
      });
      return response.data;
    } catch (error) {
      this.logger.warn(`Pesapal POST ${path} failed: ${this.safeError(error)}`);
      throw new BadGatewayException("Pesapal request failed. Please retry.");
    }
  }

  private async authedGet(path: string) {
    this.assertConfigured();
    try {
      const response = await axios.get(`${this.baseUrl()}${path}`, {
        headers: { Authorization: `Bearer ${await this.token()}`, Accept: "application/json" },
        timeout: 15000,
      });
      return response.data;
    } catch (error) {
      this.logger.warn(`Pesapal GET ${path} failed: ${this.safeError(error)}`);
      throw new BadGatewayException("Pesapal request failed. Please retry.");
    }
  }

  /** YYYY-MM-DDTHH:mm:ss — Pesapal's expected subscription date format. */
  private pesapalDate(d: Date): string {
    const pad = (n: number) => String(n).padStart(2, "0");
    return (
      `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}` +
      `T${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}`
    );
  }

  private rfc3986(value: string): string {
    return encodeURIComponent(value).replace(
      /[!'()*]/g,
      (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
    );
  }

  private parseExpiry(expiresIn: unknown): number {
    if (typeof expiresIn === "number" && Number.isFinite(expiresIn)) {
      // Pesapal reports expiresIn in ms for ISO-like tokens, seconds otherwise.
      return Date.now() + (expiresIn > 1_000_000 ? expiresIn : expiresIn * 1000);
    }
    if (typeof expiresIn === "string" && Number.isFinite(Number(expiresIn))) {
      const seconds = Number(expiresIn);
      return Date.now() + (seconds > 1_000_000 ? seconds * 1000 : seconds * 1000);
    }
    return Date.now() + 4 * 60 * 1000; // conservative default: 4 min
  }

  private assertConfigured() {
    if (!this.isConfigured()) {
      throw new ServiceUnavailableException("Pesapal is not configured");
    }
  }

  private required(key: string): string {
    const value = this.config.get<string>(key)?.trim();
    if (!value) {
      throw new ServiceUnavailableException(`Missing payment configuration: ${key}`);
    }
    return value;
  }

  private baseUrl(): string {
    return (this.config.get<string>("PESAPAL_ENV") ?? "sandbox") === "production"
      ? "https://pay.pesapal.com/v3"
      : "https://cybqa.pesapal.com/pesapalv3";
  }

  private safeError(error: unknown): string {
    if (error instanceof AxiosError) {
      return `HTTP ${error.response?.status ?? "network error"}`;
    }
    return error instanceof Error ? error.message : "Unknown error";
  }
}