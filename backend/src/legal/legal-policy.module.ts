import { Module } from '@nestjs/common';
import { PrismaModule } from '../common/prisma/prisma.module';
import { LegalPolicyController } from './legal-policy.controller';
import { LegalPolicyService } from './legal-policy.service';

@Module({
  imports: [PrismaModule],
  controllers: [LegalPolicyController],
  providers: [LegalPolicyService],
  exports: [LegalPolicyService],
})
export class LegalPolicyModule {}
