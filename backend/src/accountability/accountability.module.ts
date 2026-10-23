import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PermissionsModule } from '../permissions/permissions.module';
import { AccountabilityController } from './accountability.controller';
import { AccountabilityService } from './accountability.service';
import { AccountabilitySummaryService } from './accountability-summary.service';

/**
 * Rules, alerts and the owner's daily summary. Deliberately depends only on
 * leaf modules (audit, notifications, permissions) so sales, inventory,
 * catalog and the rest can import it without creating a module cycle.
 */
@Module({
  imports: [AuditModule, NotificationsModule, PermissionsModule],
  controllers: [AccountabilityController],
  providers: [AccountabilityService, AccountabilitySummaryService],
  exports: [AccountabilityService, AccountabilitySummaryService],
})
export class AccountabilityModule {}
