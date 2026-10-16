import { Module } from '@nestjs/common';
import { FeatureGuard } from './feature.guard';
import { LicenseController } from './license.controller';
import { LicenseService } from './license.service';

/**
 * Software licensing and module gating. Depends only on Prisma and config
 * (both global), so any feature module can import it without pulling the
 * payments graph in.
 */
@Module({
  controllers: [LicenseController],
  providers: [LicenseService, FeatureGuard],
  exports: [LicenseService, FeatureGuard],
})
export class LicenseModule {}
