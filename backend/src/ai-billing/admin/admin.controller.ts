import { Controller, Post, Get, Body, Query, Param } from '@nestjs/common';
import { AiBillingService } from '../ai-billing.service';
import { AdminActionDto } from '../dto/subscribe.dto';

@Controller('api/v1/admin/ai-billing')
export class AiBillingAdminController {
  constructor(private readonly billingService: AiBillingService) {}

  /** List all subscriptions */
  @Get('subscriptions')
  async listSubscriptions(@Query('client') client?: string) {
    return this.billingService.listAllSubscriptions(client);
  }

  /** Get pending payments needing approval */
  @Get('pending')
  async getPending(@Query('client') client?: string) {
    return this.billingService.getPendingPayments(client);
  }

  /** Approve or reject a payment */
  @Post('handle-payment')
  async handlePayment(@Body() dto: AdminActionDto) {
    return this.billingService.handlePayment(dto.paymentId, dto.action, dto.notes);
  }

  /** Revenue dashboard */
  @Get('revenue')
  async getRevenue(@Query('client') client?: string) {
    return this.billingService.getRevenueSummary(client);
  }

  /** List all POS clients */
  @Get('clients')
  async listClients() {
    return this.billingService.listPosClients();
  }

  /** Get branches for a POS client */
  @Get('clients/:slug/branches')
  async getClientBranches(@Param('slug') slug: string) {
    return this.billingService.getClientBranches(slug);
  }
}
