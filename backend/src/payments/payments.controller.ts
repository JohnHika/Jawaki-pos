import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
} from '@nestjs/swagger';
import { DarajaService } from './services/daraja.service';
import { PesapalService } from './services/pesapal.service';
import { TouristTapService } from './services/touristtap.service';
import {
  MpesaStkPushDto,
  MpesaCallbackDto,
  PesapalPaymentDto,
  PesapalIpnDto,
  TouristTapPaymentDto,
  TouristTapCallbackDto,
  PaymentInitResponseDto,
  PaymentStatusResponseDto,
} from './dto/payments.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('payments')
@Controller({ path: 'payments', version: '1' })
export class PaymentsController {
  constructor(
    private readonly darajaService: DarajaService,
    private readonly pesapalService: PesapalService,
    private readonly touristTapService: TouristTapService,
  ) {}

  // ==================== M-PESA (DARAJA) ====================

  @Post('mpesa/stkpush')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Initiate M-Pesa STK Push payment' })
  @ApiResponse({ status: 201, description: 'STK push initiated', type: PaymentInitResponseDto })
  async initiateMpesaPayment(@Body() dto: MpesaStkPushDto) {
    const result = await this.darajaService.initiateSTKPush(dto);
    return {
      success: result.success,
      transactionId: result.checkoutRequestId,
      message: result.message,
    };
  }

  @Get('mpesa/status/:checkoutRequestId')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Get M-Pesa transaction status' })
  @ApiResponse({ status: 200, description: 'Transaction status', type: PaymentStatusResponseDto })
  async getMpesaStatus(@Param('checkoutRequestId') checkoutRequestId: string) {
    const result = await this.darajaService.querySTKStatus(checkoutRequestId);
    const transaction = await this.darajaService.getTransaction(checkoutRequestId);

    return {
      transactionId: checkoutRequestId,
      status: result.status,
      amount: transaction?.amount ? Number(transaction.amount) : 0,
      paidAt: transaction?.transactionDate,
      receiptNumber: transaction?.mpesaReceiptNumber,
    };
  }

  @Post('mpesa/callback')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'M-Pesa STK Push callback (webhook)' })
  async mpesaCallback(@Body() callback: MpesaCallbackDto) {
    await this.darajaService.processSTKCallback(callback);
    return { ResultCode: 0, ResultDesc: 'Accepted' };
  }

  @Post('mpesa/confirmation')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'M-Pesa C2B confirmation (webhook)' })
  async mpesaConfirmation(@Body() confirmation: any) {
    await this.darajaService.processC2BConfirmation(confirmation);
    return { ResultCode: 0, ResultDesc: 'Accepted' };
  }

  // ==================== PESAPAL ====================

  @Post('pesapal/initiate')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Initiate PesaPal payment' })
  @ApiResponse({ status: 201, description: 'Payment initiated', type: PaymentInitResponseDto })
  async initiatePesapalPayment(@Body() dto: PesapalPaymentDto) {
    const result = await this.pesapalService.submitOrder(dto);
    return {
      success: true,
      transactionId: result.orderTrackingId,
      checkoutUrl: result.redirectUrl,
      message: 'Redirect user to checkout URL',
    };
  }

  @Get('pesapal/status/:orderTrackingId')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Get PesaPal transaction status' })
  @ApiResponse({ status: 200, description: 'Transaction status', type: PaymentStatusResponseDto })
  async getPesapalStatus(@Param('orderTrackingId') orderTrackingId: string) {
    const result = await this.pesapalService.getTransactionStatus(orderTrackingId);
    const transaction = await this.pesapalService.getTransaction(orderTrackingId);

    return {
      transactionId: orderTrackingId,
      status: result.status,
      amount: result.amount,
      payerInfo: {
        phone: result.paymentAccountReference,
      },
    };
  }

  @Post('pesapal/ipn')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'PesaPal IPN notification (webhook)' })
  async pesapalIpn(@Body() ipn: PesapalIpnDto) {
    await this.pesapalService.processIPN(ipn);
    return { status: 'ok' };
  }

  @Get('pesapal/callback')
  @ApiOperation({ summary: 'PesaPal callback redirect' })
  async pesapalCallback(
    @Query('OrderTrackingId') orderTrackingId: string,
    @Query('OrderMerchantReference') merchantReference: string,
  ) {
    // Get status and return to frontend
    const status = await this.pesapalService.getTransactionStatus(orderTrackingId);
    return {
      orderTrackingId,
      merchantReference,
      status: status.status,
      message: status.message,
    };
  }

  // ==================== TOURISTTAP ====================

  @Post('touristtap/initiate')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Initiate TouristTap NFC payment' })
  @ApiResponse({ status: 201, description: 'Payment initiated', type: PaymentInitResponseDto })
  async initiateTouristTapPayment(@Body() dto: TouristTapPaymentDto) {
    const result = await this.touristTapService.initiatePayment(dto);
    return {
      success: result.success,
      transactionId: result.transactionRef,
      message: result.message,
    };
  }

  @Post('touristtap/confirm')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Confirm TouristTap NFC payment' })
  @ApiResponse({ status: 200, description: 'Payment confirmed' })
  async confirmTouristTapPayment(
    @Body() body: { transactionRef: string; nfcToken: string },
  ) {
    return this.touristTapService.confirmPayment(body.transactionRef, body.nfcToken);
  }

  @Get('touristtap/status/:transactionRef')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Get TouristTap transaction status' })
  @ApiResponse({ status: 200, description: 'Transaction status', type: PaymentStatusResponseDto })
  async getTouristTapStatus(@Param('transactionRef') transactionRef: string) {
    const result = await this.touristTapService.getTransactionStatus(transactionRef);
    return {
      transactionId: transactionRef,
      status: result.status,
      amount: result.amount,
      paidAt: result.paidAt,
    };
  }

  @Post('touristtap/callback')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'TouristTap callback (webhook)' })
  async touristTapCallback(@Body() callback: TouristTapCallbackDto) {
    await this.touristTapService.processCallback(callback);
    return { status: 'ok' };
  }

  @Post('touristtap/cancel/:transactionRef')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Cancel pending TouristTap payment' })
  async cancelTouristTapPayment(@Param('transactionRef') transactionRef: string) {
    await this.touristTapService.cancelPayment(transactionRef);
  }
}
