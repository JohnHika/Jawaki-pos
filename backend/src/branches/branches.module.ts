import { Module } from '@nestjs/common';
import { BranchesController } from './branches.controller';
import { BranchesService } from './branches.service';
import { AuditModule } from '../audit/audit.module';
import { LicenseModule } from '../license/license.module';

@Module({
  imports: [AuditModule, LicenseModule],
  controllers: [BranchesController],
  providers: [BranchesService],
  exports: [BranchesService],
})
export class BranchesModule {}
