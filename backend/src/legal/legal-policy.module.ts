import { Module } from '@nestjs/common';
import { LegalPolicyController } from './legal-policy.controller';
import { LegalPolicyService } from './legal-policy.service';

@Module({
  controllers: [LegalPolicyController],
  providers: [LegalPolicyService],
  exports: [LegalPolicyService],
})
export class LegalPolicyModule {}
