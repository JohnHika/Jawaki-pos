import { Module } from '@nestjs/common';
import { AiBillingModule } from '../ai-billing/ai-billing.module';
import { SubscriptionGuard } from '../billing/subscription.guard';
import { SalesModule } from '../sales/sales.module';
import { LegalPolicyModule } from '../legal/legal-policy.module';
import { FinanceModule } from '../finance/finance.module';
import { MerchantPaymentsController } from './merchant-payments.controller';
import { MerchantPaymentsService } from './merchant-payments.service';

@Module({
  imports: [AiBillingModule, SalesModule, LegalPolicyModule, FinanceModule],
  controllers: [MerchantPaymentsController],
  providers: [MerchantPaymentsService, SubscriptionGuard],
  exports: [MerchantPaymentsService],
})
export class MerchantPaymentsModule {}
