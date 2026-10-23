import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ThrottlerProvidersModule } from '../common/throttler/throttler-providers.module';
import { ReferralsController } from './referrals.controller';
import { ReferralsService } from './referrals.service';
import { PromoService } from './promo.service';

/**
 * Referral and promo codes. Both only ever add free subscription days, so this
 * module never touches invoices or prices. Depends on leaf modules only, so
 * tenant activation and the platform admin can import it without a cycle.
 */
@Module({
  imports: [AuditModule, NotificationsModule, ThrottlerProvidersModule],
  controllers: [ReferralsController],
  providers: [ReferralsService, PromoService],
  exports: [ReferralsService, PromoService],
})
export class ReferralsModule {}
