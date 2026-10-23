import { Module } from '@nestjs/common';
import { SubscriptionController } from './subscription.controller';
import { SubscriptionService } from './subscription.service';
import { LegalPolicyModule } from '../legal/legal-policy.module';

@Module({
  controllers: [SubscriptionController],
  imports: [LegalPolicyModule],
  providers: [SubscriptionService],
  exports: [SubscriptionService],
})
export class SubscriptionModule {}
