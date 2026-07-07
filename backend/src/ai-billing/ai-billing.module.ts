import { Module } from '@nestjs/common';
import { AiBillingController } from './ai-billing.controller';
import { AiBillingService } from './ai-billing.service';
import { AiBillingAdminController } from './admin/admin.controller';
import { AiAccessGuard } from './ai-billing.guard';
import { PaystackService } from './paystack.service';
import { AiBillingRenewalTask } from './ai-billing-renewal.task';

@Module({
  controllers: [AiBillingController, AiBillingAdminController],
  providers: [AiBillingService, AiAccessGuard, PaystackService, AiBillingRenewalTask],
  exports: [AiBillingService, AiAccessGuard],
})
export class AiBillingModule {}
