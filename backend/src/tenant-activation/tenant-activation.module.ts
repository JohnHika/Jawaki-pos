import { Module } from '@nestjs/common';
import { AiBillingModule } from '../ai-billing/ai-billing.module';
import { ReferralsModule } from '../referrals/referrals.module';
import { TenantActivationController } from './tenant-activation.controller';
import { TenantActivationService } from './tenant-activation.service';

@Module({
  imports: [AiBillingModule, ReferralsModule],
  controllers: [TenantActivationController],
  providers: [TenantActivationService],
  exports: [TenantActivationService],
})
export class TenantActivationModule {}
