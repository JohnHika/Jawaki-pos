import { Module } from '@nestjs/common';
import { IdentityModule } from '../identity/identity.module';
import { TenantOnboardingController } from './tenant-onboarding.controller';
import { TenantOnboardingService } from './tenant-onboarding.service';

@Module({ imports: [IdentityModule], controllers: [TenantOnboardingController], providers: [TenantOnboardingService], exports: [TenantOnboardingService] })
export class TenantOnboardingModule {}
