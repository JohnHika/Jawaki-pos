import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { PrismaService } from '../../common/prisma/prisma.service';
import { RedisService } from '../../common/redis/redis.service';
import { PesapalPaymentDto, PesapalIpnDto } from '../dto/payments.dto';

@Injectable()
export class PesapalService {
  private readonly logger = new Logger(PesapalService.name);
  private readonly baseUrl: string;
  private readonly consumerKey: string;
  private readonly consumerSecret: string;
  private readonly ipnUrl: string;

  constructor(
    private configService: ConfigService,
    private prisma: PrismaService,
    private redisService: RedisService,
  ) {
    const env = this.configService.get<string>('PESAPAL_ENV', 'sandbox');
    this.baseUrl = env === 'production'
      ? 'https://pay.pesapal.com/v3'
      : 'https://cybqa.pesapal.com/pesapalv3';

    this.consumerKey = this.configService.get<string>('PESAPAL_CONSUMER_KEY', '');
    this.consumerSecret = this.configService.get<string>('PESAPAL_CONSUMER_SECRET', '');
    this.ipnUrl = this.configService.get<string>('PESAPAL_IPN_URL', '');
  }

  /**
   * Get OAuth access token from PesaPal
   */
  async getAccessToken(): Promise<string> {
    // Check cache first
    const cachedToken = await this.redisService.get('pesapal:token');
    if (cachedToken) return cachedToken;

    try {
      const response = await axios.post(
        `${this.baseUrl}/api/Auth/RequestToken`,
        {
          consumer_key: this.consumerKey,
          consumer_secret: this.consumerSecret,
        },
        {
          headers: {
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
        },
      );

      const { token, expiryDate } = response.data;

      // Cache token (expire 5 minutes before actual expiry)
      const expiresIn = Math.max(0, new Date(expiryDate).getTime() - Date.now() - 300000);
      await this.redisService.set('pesapal:token', token, Math.floor(expiresIn / 1000));

      return token;
    } catch (error: any) {
      this.logger.error('Failed to get PesaPal access token', error.response?.data);
      throw new BadRequestException('Failed to authenticate with PesaPal');
    }
  }

  /**
   * Register IPN URL
   */
  async registerIPN(): Promise<string> {
    try {
      const accessToken = await this.getAccessToken();

      const response = await axios.post(
        `${this.baseUrl}/api/URLSetup/RegisterIPN`,
        {
          url: this.ipnUrl,
          ipn_notification_type: 'POST',
        },
        {
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
        },
      );

      return response.data.ipn_id;
    } catch (error: any) {
      this.logger.error('Failed to register PesaPal IPN', error.response?.data);
      throw new BadRequestException('Failed to register IPN');
    }
  }

  /**
   * Submit a payment order
   */
  async submitOrder(dto: PesapalPaymentDto): Promise<{
    orderTrackingId: string;
    redirectUrl: string;
    merchantReference: string;
  }> {
    try {
      const accessToken = await this.getAccessToken();

      // Get IPN ID (register if not cached)
      let ipnId = await this.redisService.get('pesapal:ipn_id');
      if (!ipnId) {
        ipnId = await this.registerIPN();
        await this.redisService.set('pesapal:ipn_id', ipnId, 86400 * 30); // 30 days
      }

      const orderRequest = {
        id: dto.merchantReference,
        currency: dto.currency || 'KES',
        amount: dto.amount,
        description: dto.description,
        callback_url: dto.callbackUrl || this.ipnUrl.replace('/ipn', '/callback'),
        cancellation_url: dto.cancellationUrl,
        notification_id: ipnId,
        billing_address: {
          email_address: dto.email,
          phone_number: dto.phoneNumber,
          first_name: dto.firstName,
          last_name: dto.lastName,
        },
      };

      const response = await axios.post(
        `${this.baseUrl}/api/Transactions/SubmitOrderRequest`,
        orderRequest,
        {
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
        },
      );

      const { order_tracking_id, redirect_url, merchant_reference } = response.data;

      // Store transaction
      await this.prisma.pesapalTransaction.create({
        data: {
          orderTrackingId: order_tracking_id,
          merchantReference: merchant_reference,
          amount: dto.amount,
          currency: dto.currency || 'KES',
          description: dto.description,
          status: 'pending',
        },
      });

      return {
        orderTrackingId: order_tracking_id,
        redirectUrl: redirect_url,
        merchantReference: merchant_reference,
      };
    } catch (error: any) {
      this.logger.error('Failed to submit PesaPal order', error.response?.data);
      throw new BadRequestException(
        error.response?.data?.message || 'Failed to initiate PesaPal payment',
      );
    }
  }

  /**
   * Get transaction status
   */
  async getTransactionStatus(orderTrackingId: string): Promise<{
    status: string;
    paymentMethod: string;
    paymentAccountReference: string;
    amount: number;
    currency: string;
    message: string;
  }> {
    try {
      const accessToken = await this.getAccessToken();

      const response = await axios.get(
        `${this.baseUrl}/api/Transactions/GetTransactionStatus?orderTrackingId=${orderTrackingId}`,
        {
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
        },
      );

      const data = response.data;

      // Update transaction in database
      await this.prisma.pesapalTransaction.update({
        where: { orderTrackingId },
        data: {
          status: this.mapStatus(data.payment_status_description),
          statusCode: data.status_code,
          message: data.message,
          paymentMethod: data.payment_method,
          paymentAccountRef: data.payment_account,
        },
      });

      return {
        status: data.payment_status_description,
        paymentMethod: data.payment_method,
        paymentAccountReference: data.payment_account,
        amount: data.amount,
        currency: data.currency,
        message: data.message,
      };
    } catch (error: any) {
      this.logger.error('Failed to get PesaPal status', error.response?.data);
      throw new BadRequestException('Failed to get transaction status');
    }
  }

  /**
   * Process IPN notification
   */
  async processIPN(ipn: PesapalIpnDto): Promise<void> {
    this.logger.log(`Processing PesaPal IPN: ${ipn.OrderTrackingId}`);

    try {
      // Get full transaction status
      await this.getTransactionStatus(ipn.OrderTrackingId);
    } catch (error) {
      this.logger.error('Failed to process PesaPal IPN', error);
    }
  }

  /**
   * Get transaction by order tracking ID
   */
  async getTransaction(orderTrackingId: string) {
    return this.prisma.pesapalTransaction.findUnique({
      where: { orderTrackingId },
    });
  }

  /**
   * Get transaction by merchant reference
   */
  async getTransactionByReference(merchantReference: string) {
    return this.prisma.pesapalTransaction.findFirst({
      where: { merchantReference },
      orderBy: { createdAt: 'desc' },
    });
  }

  // ==================== HELPERS ====================

  private mapStatus(statusDesc: string): string {
    switch (statusDesc?.toLowerCase()) {
      case 'completed':
        return 'completed';
      case 'failed':
        return 'failed';
      case 'invalid':
        return 'failed';
      case 'reversed':
        return 'refunded';
      default:
        return 'pending';
    }
  }
}
