import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { DesktopLinkController } from './desktop-link.controller';
import { DesktopLinkService } from './desktop-link.service';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PermissionsModule } from '../permissions/permissions.module';
import { ThrottlerProvidersModule } from '../common/throttler/throttler-providers.module';

@Module({
  imports: [
    // Brings JwtModule (signing) + JwtStrategy-adjacent guard wiring.
    AuthModule,
    NotificationsModule,
    PermissionsModule,
    ThrottlerProvidersModule,
  ],
  controllers: [DesktopLinkController],
  providers: [DesktopLinkService],
  exports: [DesktopLinkService],
})
export class DesktopLinkModule {}
