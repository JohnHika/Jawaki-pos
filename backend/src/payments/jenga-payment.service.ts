import {
  BadGatewayException,
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import axios, { AxiosError } from "axios";
import { createSign, randomBytes } from "crypto";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../common/prisma/prisma.service";
import { InitiateMpesaDto } from "./dto/initiate-mpesa.dto";

type JengaCallback = {
  status?: string;
  code?: number | string;
  message?: string;
  transactionReference?: string;
  telcoReference?: string;
  mobileNumber?: string;
  currency?: string;
  requestAmount?: number | string;
  debitedAmount?: number | string;
  charge?: number | string;
  telco?: string;
};

@Injectable()
export class JengaPaymentService {
  private readonly logger = new Logger(JengaPaymentService.name);
  private accessToken?: { value: string; expiresAt: number };

  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  isConfigured(): boolean {
    return [
      "JENGA_API_KEY",
      "JENGA_MERCHANT_CODE",
      "JENGA_CONSUMER_SECRET",
      "JENGA_PRIVATE_KEY",
      "JENGA_ACCOUNT_NUMBER",
      "JENGA_MERCHANT_NAME",
      "JENGA_CALLBACK_URL",
    ].every((key) => Boolean(this.config.get<string>(key)?.trim()));
  }

  async initiate(dto: InitiateMpesaDto) {
    this.assertConfigured();
    const phone = this.normalizePhone(dto.phoneNumber);
    const amount = dto.amount.toFixed(2);
    const reference = await this.uniqueReference();
    const callbackUrl = this.required("JENGA_CALLBACK_URL");

    if (this.isProduction() && !callbackUrl.startsWith("https://")) {
      throw new ServiceUnavailableException(
        "Jenga production callback URL must use HTTPS",
      );
    }

    const payment = {
      ref: reference,
      amount,
      currency: "KES",
      telco: "Safaricom",
      mobileNumber: phone,
      date: new Date().toISOString().slice(0, 10),
      callBackUrl: callbackUrl,
      pushType: "STK",
    };
    const merchant = {
      accountNumber: this.required("JENGA_ACCOUNT_NUMBER"),
      countryCode: "KE",
      name: this.required("JENGA_MERCHANT_NAME"),
    };
    const signature = this.sign(
      merchant.accountNumber +
        reference +
        phone +
        payment.telco +
        amount +
        payment.currency,
    );

    await this.prisma.mpesaTransaction.create({
      data: {
        merchantRequestId: `JENGA:${reference}`,
        checkoutRequestId: reference,
        phoneNumber: phone,
        amount: new Prisma.Decimal(amount),
        accountReference: dto.reference,
        transactionDesc: dto.description,
        status: "pending",
      },
    });

    try {
      const response = await axios.post(
        `${this.baseUrl()}/v3-apis/payment-api/v3.0/stkussdpush/initiate`,
        { merchant, payment },
        {
          headers: {
            Authorization: `Bearer ${await this.token()}`,
            Signature: signature,
          },
          timeout: 15000,
        },
      );
      await this.prisma.mpesaTransaction.update({
        where: { checkoutRequestId: reference },
        data: {
          status: "processing",
          resultDesc: String(response.data?.message ?? "Prompt sent"),
        },
      });
      return {
        message: "Payment prompt sent to customer",
        merchant_request_id: `JENGA:${reference}`,
        checkout_request_id: reference,
        response_code: String(response.data?.code ?? "-1"),
        response_description: String(
          response.data?.message ?? "Request accepted",
        ),
        status: "PENDING",
      };
    } catch (error) {
      await this.prisma.mpesaTransaction.update({
        where: { checkoutRequestId: reference },
        data: { status: "failed", resultDesc: this.safeError(error) },
      });
      throw new BadGatewayException(
        "Equity payment prompt could not be sent. Please retry.",
      );
    }
  }

  async handleCallback(body: JengaCallback) {
    const reference = body.transactionReference?.trim();
    if (!reference)
      throw new BadRequestException("Missing transactionReference");

    const transaction = await this.prisma.mpesaTransaction.findUnique({
      where: { checkoutRequestId: reference },
    });
    if (!transaction) {
      this.logger.warn(
        `Ignored Jenga callback for unknown reference ${reference}`,
      );
      return { result: "accepted" };
    }

    const amountMatches =
      body.requestAmount !== undefined &&
      new Prisma.Decimal(String(body.requestAmount)).equals(transaction.amount);
    const identityMatches =
      amountMatches &&
      body.currency === "KES" &&
      this.normalizePhone(body.mobileNumber ?? "") === transaction.phoneNumber;
    const code = Number(body.code);
    let status = transaction.status;
    if ([1, 5, 6, 7].includes(code))
      status = code === 5 || code === 6 ? "cancelled" : "failed";
    else if (identityMatches && code === 3) status = "processing";

    await this.prisma.mpesaTransaction.update({
      where: { checkoutRequestId: reference },
      data: {
        status,
        resultCode: Number.isFinite(code) ? code : undefined,
        resultDesc: body.message,
        mpesaReceiptNumber: body.telcoReference,
        callbackPayload: body as Prisma.InputJsonValue,
      },
    });

    // A callback alone is not trusted for approval. Confirm Paid and amount
    // against Jenga's authenticated status endpoint before completing.
    if (identityMatches && code === 3) await this.status(reference, true);
    return { result: "accepted" };
  }

  async status(reference: string, forceQuery = false) {
    const transaction = await this.prisma.mpesaTransaction.findUnique({
      where: { checkoutRequestId: reference },
    });
    if (!transaction)
      throw new BadRequestException("Unknown payment reference");
    if (
      !forceQuery &&
      ["completed", "failed", "cancelled"].includes(transaction.status)
    ) {
      return this.statusResponse(transaction);
    }
    this.assertConfigured();
    try {
      const response = await axios.get(
        `${this.baseUrl()}/api-checkout/mpesa-stk-push/v3.0/status/order/${encodeURIComponent(reference)}`,
        {
          headers: { Authorization: `Bearer ${await this.token()}` },
          timeout: 10000,
        },
      );
      const order = response.data?.data?.order;
      const invoice = response.data?.data?.invoice;
      const paidAmount = new Prisma.Decimal(String(order?.amountPaid ?? 0));
      const completed =
        String(order?.orderStatus).toLowerCase() === "paid" &&
        paidAmount.equals(transaction.amount);
      const updated = await this.prisma.mpesaTransaction.update({
        where: { checkoutRequestId: reference },
        data: completed
          ? {
              status: "completed",
              transactionDate: new Date(),
              mpesaReceiptNumber:
                invoice?.externalReference ?? transaction.mpesaReceiptNumber,
            }
          : {},
      });
      return this.statusResponse(updated);
    } catch (error) {
      this.logger.warn(
        `Jenga status query failed for ${reference}: ${this.safeError(error)}`,
      );
      return this.statusResponse(transaction);
    }
  }

  private statusResponse(transaction: any) {
    return {
      transactionId: transaction.checkoutRequestId,
      status: String(transaction.status).toUpperCase(),
      amount: Number(transaction.amount),
      mpesa_code: transaction.mpesaReceiptNumber,
      paid_at: transaction.transactionDate,
    };
  }

  private async token(): Promise<string> {
    if (this.accessToken && this.accessToken.expiresAt > Date.now() + 60_000)
      return this.accessToken.value;
    try {
      const response = await axios.post(
        `${this.baseUrl()}/authentication/api/v3/authenticate/merchant`,
        {
          merchantCode: this.required("JENGA_MERCHANT_CODE"),
          consumerSecret: this.required("JENGA_CONSUMER_SECRET"),
        },
        {
          headers: { "Api-Key": this.required("JENGA_API_KEY") },
          timeout: 10000,
        },
      );
      const value = response.data?.accessToken;
      if (!value) throw new Error("No access token returned");
      this.accessToken = {
        value,
        expiresAt: this.parseTokenExpiry(response.data?.expiresIn),
      };
      return value;
    } catch (error) {
      this.logger.error(
        `Jenga authentication failed: ${this.safeError(error)}`,
      );
      throw new ServiceUnavailableException(
        "Equity payment service is unavailable",
      );
    }
  }

  private sign(value: string): string {
    const signer = createSign("RSA-SHA256");
    signer.update(value);
    signer.end();
    return signer.sign(
      this.required("JENGA_PRIVATE_KEY").replace(/\\n/g, "\n"),
      "base64",
    );
  }

  private normalizePhone(value: string): string {
    const digits = value.replace(/\D/g, "");
    if (/^0[17]\d{8}$/.test(digits)) return `254${digits.slice(1)}`;
    if (/^[17]\d{8}$/.test(digits)) return `254${digits}`;
    if (/^254[17]\d{8}$/.test(digits)) return digits;
    throw new BadRequestException("Invalid Kenyan mobile number");
  }

  private async uniqueReference(): Promise<string> {
    for (let attempt = 0; attempt < 10; attempt++) {
      const reference = randomBytes(4)
        .toString("hex")
        .slice(0, 6)
        .toUpperCase();
      if (
        !(await this.prisma.mpesaTransaction.findUnique({
          where: { checkoutRequestId: reference },
        }))
      )
        return reference;
    }
    throw new ServiceUnavailableException(
      "Could not allocate a payment reference",
    );
  }

  private assertConfigured() {
    if (!this.isConfigured())
      throw new ServiceUnavailableException(
        "Equity payments are not configured",
      );
  }

  private required(key: string): string {
    const value = this.config.get<string>(key)?.trim();
    if (!value)
      throw new ServiceUnavailableException(
        `Missing payment configuration: ${key}`,
      );
    return value;
  }

  private isProduction() {
    return this.config.get("JENGA_ENV") === "production";
  }
  private baseUrl() {
    return this.isProduction()
      ? "https://api.finserve.africa"
      : "https://uat.finserve.africa";
  }
  private safeError(error: unknown) {
    if (error instanceof AxiosError)
      return `HTTP ${error.response?.status ?? "network error"}`;
    return error instanceof Error ? error.message : "Unknown error";
  }

  private parseTokenExpiry(expiresIn: unknown): number {
    if (typeof expiresIn === "number" && Number.isFinite(expiresIn)) {
      return Date.now() + expiresIn * 1000;
    }
    if (typeof expiresIn === "string") {
      const seconds = Number(expiresIn);
      if (Number.isFinite(seconds)) return Date.now() + seconds * 1000;
      const timestamp = Date.parse(expiresIn);
      if (Number.isFinite(timestamp)) return timestamp;
    }
    return Date.now() + 10 * 60 * 1000;
  }
}
