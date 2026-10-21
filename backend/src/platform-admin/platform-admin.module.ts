import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule } from '@nestjs/config';
import { AuditModule } from '../audit/audit.module';
import { LicenseModule } from '../license/license.module';
import { ThrottlerProvidersModule } from '../common/throttler/throttler-providers.module';
import { PlatformAuditService } from './audit/platform-audit.service';
import { PlatformAdminController } from './platform-admin.controller';
import { PlatformAdminGuard } from './guards/platform-admin.guard';
import {
  PlatformAdminAuthService,
  PlatformAdminBootstrapService,
} from './platform-admin-auth.service';
import { PlatformAdminService } from './platform-admin.service';
import { PlatformSecurityController, PlatformTeamController } from './platform-team.controller';
import { PlatformSecurityService } from './platform-security.service';
import { PlatformTeamService } from './platform-team.service';
import { PlatformTenantSupportController } from './platform-tenant-support.controller';
import { PlatformTenantSupportService } from './platform-tenant-support.service';

@Module({
  imports: [
    ConfigModule,
    JwtModule.register({}),
    AuditModule,
    LicenseModule,
    // Re-exports the throttler options/storage so ThrottlerGuard on the
    // controller's login route can resolve its dependencies.
    ThrottlerProvidersModule,
  ],
  controllers: [
    PlatformAdminController,
    PlatformTeamController,
    PlatformSecurityController,
    PlatformTenantSupportController,
  ],
  providers: [
    PlatformAdminGuard,
    PlatformAuditService,
    PlatformAdminAuthService,
    PlatformAdminBootstrapService,
    PlatformAdminService,
    PlatformTeamService,
    PlatformSecurityService,
    PlatformTenantSupportService,
  ],
  exports: [],
})
export class PlatformAdminModule {}
