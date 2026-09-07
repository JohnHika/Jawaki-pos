import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule } from '@nestjs/config';
import { AuditModule } from '../audit/audit.module';
import { ThrottlerProvidersModule } from '../common/throttler/throttler-providers.module';
import { PlatformAdminController } from './platform-admin.controller';
import { PlatformAdminGuard } from './guards/platform-admin.guard';
import {
  PlatformAdminAuthService,
  PlatformAdminBootstrapService,
} from './platform-admin-auth.service';
import { PlatformAdminService } from './platform-admin.service';

@Module({
  imports: [
    ConfigModule,
    JwtModule.register({}),
    AuditModule,
    // Re-exports the throttler options/storage so ThrottlerGuard on the
    // controller's login route can resolve its dependencies.
    ThrottlerProvidersModule,
  ],
  controllers: [PlatformAdminController],
  providers: [
    PlatformAdminGuard,
    PlatformAdminAuthService,
    PlatformAdminBootstrapService,
    PlatformAdminService,
  ],
  exports: [],
})
export class PlatformAdminModule {}