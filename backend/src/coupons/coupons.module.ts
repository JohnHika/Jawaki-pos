import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { AccountabilityModule } from '../accountability/accountability.module';
import { PermissionsModule } from '../permissions/permissions.module';
import { CouponsController } from './coupons.controller';
import { CouponsService } from './coupons.service';

/**
 * Shop coupons. Depends only on leaf modules so the sales module can import it
 * without creating a cycle.
 */
@Module({
  imports: [AuditModule, AccountabilityModule, PermissionsModule],
  controllers: [CouponsController],
  providers: [CouponsService],
  exports: [CouponsService],
})
export class CouponsModule {}
