import {
  Controller,
  Post,
  Get,
  Body,
  Param,
  Query,
  Request,
  UseGuards,
  HttpStatus,
  HttpCode,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { UserRole } from '@prisma/client';

/**
 * KNOWN LIMITATION: every endpoint in this controller is a stub that
 * returns hardcoded placeholder data. No real M-Pesa Daraja, Pesapal, or
 * TouristTap integration exists yet — "success" responses here do not
 * mean money moved. Do not treat these as production-ready until real
 * gateway integrations are built.
 */
@ApiTags('payments')
@Controller({ path: 'payments', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class PaymentsController {
  constructor() {}

  // ==================== M-PESA (Daraja) ENDPOINTS ====================

  @Post('mpesa/initiate')
  @ApiOperation({ summary: 'Initiate M-Pesa payment via Daraja API' })
  @ApiResponse({ status: 200, description: 'Payment initiated' })
  @ApiResponse({ status: 400, description: 'Invalid payment details' })
  async initiateMpesaPayment(
    @Request() req: any,
    @Body() body: {
      phoneNumber: string;
      amount: number;
      reference: string;
      description?: string;
    },
  ): Promise<any> {
    // This endpoint should integrate with M-Pesa Daraja API
    // For now, return a placeholder response
    return {
      message: 'M-Pesa payment initiated',
      merchantRequest_id: 'test-merchant-request-id',
      checkout_request_id: 'test-checkout-request-id',
      response_code: '0',
      response_description: 'Success',
    };
  }

  @Get('mpesa/status/:transactionId')
  @ApiOperation({ summary: 'Get M-Pesa transaction status' })
  @ApiResponse({ status: 200, description: 'Transaction status' })
  async getMpesaStatus(@Param('transactionId') transactionId: string): Promise<any> {
    // This endpoint should query M-Pesa Daraja API for transaction status
    return {
      transactionId,
      status: 'completed',
      amount: 100,
     _mpesa_code: 'MPESA001',
      paid_at: new Date(),
    };
  }

  @Post('mpesa/callback')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'M-Pesa callback endpoint (webhook)' })
  @ApiResponse({ status: 200, description: 'Callback received' })
  async mpesaCallback(@Body() body: any): Promise<{ result: string }> {
    // This endpoint receives webhook notifications from M-Pesa
    console.log('M-Pesa callback received:', body);
    return { result: 'success' };
  }

  // ==================== PESAPAL ENDPOINTS ====================

  @Post('pesapal/initiate')
  @ApiOperation({ summary: 'Initiate Pesapal payment' })
  @ApiResponse({ status: 200, description: 'Pesapal payment initiated' })
  async initiatePesapalPayment(
    @Request() req: any,
    @Body() body: {
      amount: number;
      reference: string;
      description?: string;
      email?: string;
      phone?: string;
    },
  ): Promise<any> {
    // This endpoint should integrate with Pesapal API
    return {
      message: 'Pesapal payment initiated',
      pesapal_tracking_id: 'PES00123456789',
      payment_url: 'https:// pay.pesapal.com/v2/pay/PES00123456789',
    };
  }

  @Get('pesapal/status/:reference')
  @ApiOperation({ summary: 'Get Pesapal transaction status' })
  @ApiResponse({ status: 200, description: 'Transaction status' })
  async getPesapalStatus(@Param('reference') reference: string): Promise<any> {
    // This endpoint should query Pesapal API for transaction status
    return {
      reference,
      status: 'completed',
      amount: 100,
      pesapal_tracking_id: 'PES00123456789',
      paid_at: new Date(),
    };
  }

  @Post('pesapal/ipn')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Pesapal IPN (Instant Payment Notification)' })
  @ApiResponse({ status: 200, description: 'IPN received' })
  async pesapalIPN(@Body() body: any): Promise<{ status: string }> {
    // This endpoint receives IPN notifications from Pesapal
    console.log('Pesapal IPN received:', body);
    return { status: 'success' };
  }

  // ==================== TOURISTTAP (NFC) ENDPOINTS ====================

  @Post('touristtap/initiate')
  @ApiOperation({ summary: 'Initiate TouristTap NFC payment' })
  @ApiResponse({ status: 200, description: 'TouristTap payment initiated' })
  async initiateTouristTapPayment(
    @Request() req: any,
    @Body() body: {
      amount: number;
      reference: string;
      description?: string;
      deviceMac?: string;
    },
  ): Promise<any> {
    // This endpoint should integrate with TouristTap NFC API
    return {
      message: 'TouristTap NFC payment initiated',
      transactionId: 'TT-' + Date.now(),
      payment_url: 'nfc://pay?transaction=' + Date.now(),
    };
  }

  @Post('touristtap/status')
  @ApiOperation({ summary: 'Get TouristTap transaction status' })
  @ApiResponse({ status: 200, description: 'Transaction status' })
  async getTouristTapStatus(@Body() body: { transactionId: string }): Promise<any> {
    // This endpoint should query TouristTap API for transaction status
    return {
      transactionId: body.transactionId,
      status: 'completed',
      amount: 100,
      paid_at: new Date(),
    };
  }

  // ==================== GENERAL PAYMENT ENDPOINTS ====================

  @Get()
  @ApiOperation({ summary: 'Get all payment methods' })
  @ApiResponse({ status: 200, description: 'Available payment methods' })
  async getPaymentMethods(): Promise<any[]> {
    return [
      {
        id: 'mpesa',
        name: 'M-Pesa',
        enabled: true,
        icon: 'mpesa',
      },
      {
        id: 'pesapal',
        name: 'Pesapal',
        enabled: true,
        icon: 'pesapal',
      },
      {
        id: 'touristtap',
        name: 'TouristTap (NFC)',
        enabled: true,
        icon: 'nfc',
      },
      {
        id: 'card',
        name: 'Credit/Debit Card',
        enabled: true,
        icon: 'card',
      },
      {
        id: 'cash',
        name: 'Cash',
        enabled: true,
        icon: 'cash',
      },
    ];
  }

  @Get('methods')
  @ApiOperation({ summary: 'Get enabled payment methods' })
  @ApiResponse({ status: 200, description: 'Enabled payment methods' })
  async getEnabledPaymentMethods(): Promise<any[]> {
    return [
      {
        id: 'mpesa',
        name: 'M-Pesa',
        enabled: true,
      },
      {
        id: 'pesapal',
        name: 'Pesapal',
        enabled: true,
      },
      {
        id: 'touristtap',
        name: 'TouristTap (NFC)',
        enabled: true,
      },
    ];
  }
}
