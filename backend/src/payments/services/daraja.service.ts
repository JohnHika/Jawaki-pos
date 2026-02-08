import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { PrismaService } from '../../common/prisma/prisma.service';
import { MpesaStkPushDto, MpesaCallbackDto, MpesaC2BConfirmationDto } from '../dto/payments.dto';

@Injectable()
export class DarajaService {
  private readonly logger = new Logger(DarajaService.name);
  private readonly baseUrl: string;
  private readonly consumerKey: string;
  private readonly consumerSecret: string;
  private readonly passKey: string;
  private readonly shortCode: string;
  private readonly callbackUrl: string;

  constructor(
    private configService: ConfigService,
    private prisma: PrismaService,
  ) {
    const env = this.configService.get<string>('DARAJA_ENV', 'sandbox');
    this.baseUrl = env === 'production'
      ? 'https://api.safaricom.co.ke'
      : 'https://sandbox.safaricom.co.ke';

    this.consumerKey = this.configService.get<string>('DARAJA_CONSUMER_KEY', '');
    this.consumerSecret = this.configService.get<string>('DARAJA_CONSUMER_SECRET', '');
    this.passKey = this.configService.get<string>('DARAJA_PASSKEY', '');
    this.shortCode = this.configService.get<string>('DARAJA_SHORTCODE', '174379');
    this.callbackUrl = this.configService.get<string>('DARAJA_CALLBACK_URL', '');
  }

  /**
   * Get OAuth access token from Daraja API
   */
  async getAccessToken(): Promise<string> {
    try {
      const auth = Buffer.from(`${this.consumerKey}:${this.consumerSecret}`).toString('base64');

      const response = await axios.get(
        `${this.baseUrl}/oauth/v1/generate?grant_type=client_credentials`,
        {
          headers: {
            Authorization: `Basic ${auth}`,
          },
        },
      );

      return response.data.access_token;
    } catch (error) {
      this.logger.error('Failed to get Daraja access token', error);
      throw new BadRequestException('Failed to authenticate with M-Pesa');
    }
  }

  /**
   * Initiate STK Push (Lipa Na M-Pesa Online)
   */
  async initiateSTKPush(dto: MpesaStkPushDto): Promise<{
    success: boolean;
    merchantRequestId: string;
    checkoutRequestId: string;
    message: string;
  }> {
    try {
      const accessToken = await this.getAccessToken();
      const timestamp = this.getTimestamp();
      const password = this.generatePassword(timestamp);

      // Format phone number (ensure it starts with 254)
      const phoneNumber = this.formatPhoneNumber(dto.phoneNumber);

      const requestBody = {
        BusinessShortCode: this.shortCode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: 'CustomerPayBillOnline',
        Amount: Math.round(dto.amount),
        PartyA: phoneNumber,
        PartyB: this.shortCode,
        PhoneNumber: phoneNumber,
        CallBackURL: this.callbackUrl,
        AccountReference: dto.accountReference.substring(0, 12),
        TransactionDesc: dto.transactionDesc || 'Payment',
      };

      const response = await axios.post(
        `${this.baseUrl}/mpesa/stkpush/v1/processrequest`,
        requestBody,
        {
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
        },
      );

      const { MerchantRequestID, CheckoutRequestID, ResponseCode, ResponseDescription } = response.data;

      if (ResponseCode !== '0') {
        throw new BadRequestException(ResponseDescription);
      }

      // Store transaction
      await this.prisma.mpesaTransaction.create({
        data: {
          merchantRequestId: MerchantRequestID,
          checkoutRequestId: CheckoutRequestID,
          phoneNumber,
          amount: dto.amount,
          accountReference: dto.accountReference,
          transactionDesc: dto.transactionDesc,
          status: 'pending',
        },
      });

      return {
        success: true,
        merchantRequestId: MerchantRequestID,
        checkoutRequestId: CheckoutRequestID,
        message: 'STK push sent successfully',
      };
    } catch (error: any) {
      this.logger.error('STK Push failed', error.response?.data || error.message);
      throw new BadRequestException(
        error.response?.data?.errorMessage || 'Failed to initiate M-Pesa payment',
      );
    }
  }

  /**
   * Query STK Push status
   */
  async querySTKStatus(checkoutRequestId: string): Promise<{
    status: string;
    resultCode: number;
    resultDesc: string;
  }> {
    try {
      const accessToken = await this.getAccessToken();
      const timestamp = this.getTimestamp();
      const password = this.generatePassword(timestamp);

      const response = await axios.post(
        `${this.baseUrl}/mpesa/stkpushquery/v1/query`,
        {
          BusinessShortCode: this.shortCode,
          Password: password,
          Timestamp: timestamp,
          CheckoutRequestID: checkoutRequestId,
        },
        {
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
        },
      );

      const { ResultCode, ResultDesc } = response.data;

      return {
        status: ResultCode === '0' ? 'completed' : 'failed',
        resultCode: parseInt(ResultCode, 10),
        resultDesc: ResultDesc,
      };
    } catch (error) {
      this.logger.error('STK Query failed', error);
      throw new BadRequestException('Failed to query M-Pesa status');
    }
  }

  /**
   * Process STK Push callback
   */
  async processSTKCallback(callback: MpesaCallbackDto): Promise<void> {
    const { stkCallback } = callback.Body;
    const { MerchantRequestID, CheckoutRequestID, ResultCode, ResultDesc, CallbackMetadata } = stkCallback;

    this.logger.log(`Processing M-Pesa callback: ${CheckoutRequestID}, Result: ${ResultCode}`);

    // Parse metadata
    let mpesaReceiptNumber: string | undefined;
    let transactionDate: Date | undefined;
    let phoneNumber: string | undefined;

    if (CallbackMetadata?.Item) {
      for (const item of CallbackMetadata.Item) {
        switch (item.Name) {
          case 'MpesaReceiptNumber':
            mpesaReceiptNumber = String(item.Value);
            break;
          case 'TransactionDate':
            transactionDate = this.parseTransactionDate(String(item.Value));
            break;
          case 'PhoneNumber':
            phoneNumber = String(item.Value);
            break;
        }
      }
    }

    // Update transaction
    await this.prisma.mpesaTransaction.update({
      where: { checkoutRequestId: CheckoutRequestID },
      data: {
        resultCode: ResultCode,
        resultDesc: ResultDesc,
        mpesaReceiptNumber,
        transactionDate,
        status: ResultCode === 0 ? 'completed' : 'failed',
        callbackPayload: callback as any,
      },
    });
  }

  /**
   * Process C2B confirmation
   */
  async processC2BConfirmation(confirmation: MpesaC2BConfirmationDto): Promise<void> {
    this.logger.log(`C2B Confirmation: ${confirmation.TransID}`);

    // Store or update based on BillRefNumber (account reference)
    await this.prisma.mpesaTransaction.create({
      data: {
        merchantRequestId: `C2B_${confirmation.TransID}`,
        checkoutRequestId: confirmation.TransID,
        phoneNumber: confirmation.MSISDN,
        amount: parseFloat(confirmation.TransAmount),
        accountReference: confirmation.BillRefNumber,
        mpesaReceiptNumber: confirmation.TransID,
        transactionDate: this.parseTransactionDate(confirmation.TransTime),
        status: 'completed',
        resultCode: 0,
        resultDesc: 'C2B payment received',
        callbackPayload: confirmation as any,
      },
    });
  }

  /**
   * Get transaction by checkout request ID
   */
  async getTransaction(checkoutRequestId: string) {
    return this.prisma.mpesaTransaction.findUnique({
      where: { checkoutRequestId },
    });
  }

  /**
   * Get transaction by account reference (sale ID)
   */
  async getTransactionByReference(accountReference: string) {
    return this.prisma.mpesaTransaction.findFirst({
      where: { accountReference },
      orderBy: { createdAt: 'desc' },
    });
  }

  // ==================== HELPERS ====================

  private getTimestamp(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');

    return `${year}${month}${day}${hours}${minutes}${seconds}`;
  }

  private generatePassword(timestamp: string): string {
    const data = `${this.shortCode}${this.passKey}${timestamp}`;
    return Buffer.from(data).toString('base64');
  }

  private formatPhoneNumber(phone: string): string {
    let cleaned = phone.replace(/\D/g, '');

    if (cleaned.startsWith('0')) {
      cleaned = '254' + cleaned.substring(1);
    } else if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    } else if (!cleaned.startsWith('254')) {
      cleaned = '254' + cleaned;
    }

    return cleaned;
  }

  private parseTransactionDate(dateStr: string): Date {
    // Format: YYYYMMDDHHmmss
    const year = parseInt(dateStr.substring(0, 4), 10);
    const month = parseInt(dateStr.substring(4, 6), 10) - 1;
    const day = parseInt(dateStr.substring(6, 8), 10);
    const hours = parseInt(dateStr.substring(8, 10), 10);
    const minutes = parseInt(dateStr.substring(10, 12), 10);
    const seconds = parseInt(dateStr.substring(12, 14), 10);

    return new Date(year, month, day, hours, minutes, seconds);
  }
}
