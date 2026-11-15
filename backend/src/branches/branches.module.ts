import { Module } from '@nestjs/common';
import { BranchesController } from './branches.controller';
import { BranchesService } from './branches.service';
import { LayoutRequestsController } from './layout-requests.controller';
import { LayoutRequestsService } from './layout-requests.service';
import { AuditModule } from '../audit/audit.module';
import { LicenseModule } from '../license/license.module';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [AuditModule, LicenseModule, NotificationsModule],
  // LayoutRequestsController first: its fixed path must win over BranchesController's :id.
  controllers: [LayoutRequestsController, BranchesController],
  providers: [BranchesService, LayoutRequestsService],
  exports: [BranchesService, LayoutRequestsService],
})
export class BranchesModule {}
