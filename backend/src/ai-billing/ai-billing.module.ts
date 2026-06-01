import { Module } from '@nestjs/common';
import { AiBillingController } from './ai-billing.controller';
import { AiBillingService } from './ai-billing.service';
import { AiBillingAdminController } from './admin/admin.controller';
import { AiAccessGuard } from './ai-billing.guard';

@Module({
  controllers: [AiBillingController, AiBillingAdminController],
  providers: [AiBillingService, AiAccessGuard],
  exports: [AiBillingService, AiAccessGuard],
})
export class AiBillingModule {}
