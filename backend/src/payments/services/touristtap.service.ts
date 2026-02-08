import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import * as crypto from 'crypto';
import { PrismaService } from '../../common/prisma/prisma.service';
import { TouristTapPaymentDto, TouristTapCallbackDto } from '../dto/payments.dto';

@Injectable()
export class TouristTapService {
  private readonly logger = new Logger(TouristTapService.name);
  private readonly baseUrl = 'https://api.touristtap.com/v1';
  private readonly apiKey: string;
  private readonly merchantId: string;
  private readonly callbackUrl: string;
  private readonly webhookSecret: string;

  constructor(
    private configService: ConfigService,
    private prisma: PrismaService,
  ) {
    this.apiKey = this.configService.get<string>('TOURISTTAP_API_KEY', '');
    this.merchantId = this.configService.get<string>('TOURISTTAP_MERCHANT_ID', '');
    this.callbackUrl = this.configService.get<string>('TOURISTTAP_CALLBACK_URL', '');
    this.webhookSecret = this.configService.get<string>('TOURISTTAP_WEBHOOK_SECRET', '');
  }

  /**
   * Initiate a TouristTap NFC payment
   */
  async initiatePayment(dto: TouristTapPaymentDto): Promise<{
    success: boolean;
    transactionRef: string;
    status: string;
    message: string;
  }> {
    try {
      const requestBody = {
        merchant_id: this.merchantId,
        transaction_ref: dto.transactionRef,
        amount: dto.amount,
        currency: dto.currency || 'KES',
        customer_ref: dto.customerRef,
        callback_url: this.callbackUrl,
        timestamp: new Date().toISOString(),
      };

      const response = await axios.post(
        `${this.baseUrl}/payments/initiate`,
        requestBody,
        {
          headers: {
            'X-API-Key': this.apiKey,
            'Content-Type': 'application/json',
          },
        },
      );

      const { transaction_ref, status, message } = response.data;

      // Store transaction
      await this.prisma.touristTapTransaction.create({
        data: {
          transactionRef: transaction_ref || dto.transactionRef,
          amount: dto.amount,
          currency: dto.currency || 'KES',
          customerRef: dto.customerRef,
          status: 'pending',
          providerResponse: response.data,
        },
      });

      return {
        success: true,
        transactionRef: transaction_ref || dto.transactionRef,
        status,
        message: message || 'Payment initiated',
      };
    } catch (error: any) {
      this.logger.error('TouristTap payment initiation failed', error.response?.data || error.message);
      throw new BadRequestException(
        error.response?.data?.message || 'Failed to initiate TouristTap payment',
      );
    }
  }

  /**
   * Confirm an NFC tap payment
   */
  async confirmPayment(transactionRef: string, nfcToken: string): Promise<{
    success: boolean;
    status: string;
    message: string;
  }> {
    try {
      const response = await axios.post(
        `${this.baseUrl}/payments/confirm`,
        {
          merchant_id: this.merchantId,
          transaction_ref: transactionRef,
          nfc_token: nfcToken,
        },
        {
          headers: {
            'X-API-Key': this.apiKey,
            'Content-Type': 'application/json',
          },
        },
      );

      const { status, message } = response.data;

      // Update transaction
      await this.prisma.touristTapTransaction.update({
        where: { transactionRef },
        data: {
          status: status === 'SUCCESS' ? 'completed' : status.toLowerCase(),
          providerResponse: response.data,
        },
      });

      return {
        success: status === 'SUCCESS',
        status,
        message,
      };
    } catch (error: any) {
      this.logger.error('TouristTap payment confirmation failed', error.response?.data);
      throw new BadRequestException(
        error.response?.data?.message || 'Failed to confirm payment',
      );
    }
  }

  /**
   * Get transaction status
   */
  async getTransactionStatus(transactionRef: string): Promise<{
    status: string;
    amount: number;
    currency: string;
    paidAt?: Date;
  }> {
    try {
      const response = await axios.get(
        `${this.baseUrl}/payments/status/${transactionRef}`,
        {
          headers: {
            'X-API-Key': this.apiKey,
          },
          params: {
            merchant_id: this.merchantId,
          },
        },
      );

      const { status, amount, currency, paid_at } = response.data;

      // Update local record
      await this.prisma.touristTapTransaction.update({
        where: { transactionRef },
        data: {
          status: status.toLowerCase(),
          providerResponse: response.data,
        },
      });

      return {
        status,
        amount,
        currency,
        paidAt: paid_at ? new Date(paid_at) : undefined,
      };
    } catch (error: any) {
      this.logger.error('TouristTap status check failed', error.response?.data);
      throw new BadRequestException('Failed to get transaction status');
    }
  }

  /**
   * Process webhook callback
   */
  async processCallback(callback: TouristTapCallbackDto): Promise<void> {
    this.logger.log(`Processing TouristTap callback: ${callback.transactionRef}`);

    // Verify signature if secret is configured
    if (this.webhookSecret) {
      const isValid = this.verifySignature(callback);
      if (!isValid) {
        this.logger.warn('Invalid TouristTap webhook signature');
        throw new BadRequestException('Invalid signature');
      }
    }

    // Update transaction
    await this.prisma.touristTapTransaction.update({
      where: { transactionRef: callback.transactionRef },
      data: {
        status: callback.status.toLowerCase(),
        providerResponse: callback as any,
      },
    });
  }

  /**
   * Get transaction by reference
   */
  async getTransaction(transactionRef: string) {
    return this.prisma.touristTapTransaction.findUnique({
      where: { transactionRef },
    });
  }

  /**
   * Cancel a pending payment
   */
  async cancelPayment(transactionRef: string): Promise<void> {
    try {
      await axios.post(
        `${this.baseUrl}/payments/cancel`,
        {
          merchant_id: this.merchantId,
          transaction_ref: transactionRef,
        },
        {
          headers: {
            'X-API-Key': this.apiKey,
            'Content-Type': 'application/json',
          },
        },
      );

      await this.prisma.touristTapTransaction.update({
        where: { transactionRef },
        data: { status: 'cancelled' },
      });
    } catch (error: any) {
      this.logger.error('TouristTap cancellation failed', error.response?.data);
      throw new BadRequestException('Failed to cancel payment');
    }
  }

  // ==================== HELPERS ====================

  private verifySignature(callback: TouristTapCallbackDto): boolean {
    const payload = `${callback.transactionRef}|${callback.amount}|${callback.status}|${callback.timestamp}`;
    const expectedSignature = crypto
      .createHmac('sha256', this.webhookSecret)
      .update(payload)
      .digest('hex');

    return crypto.timingSafeEqual(
      Buffer.from(callback.signature),
      Buffer.from(expectedSignature),
    );
  }
}
