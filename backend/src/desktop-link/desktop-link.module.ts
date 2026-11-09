import { Module } from '@nestjs/common';
import { DesktopLinkController } from './desktop-link.controller';
import { DesktopLinkService } from './desktop-link.service';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ThrottlerProvidersModule } from '../common/throttler/throttler-providers.module';

@Module({
  imports: [
    // AuthService issues the session, the same way a password sign-in does.
    AuthModule,
    NotificationsModule,
    ThrottlerProvidersModule,
  ],
  controllers: [DesktopLinkController],
  providers: [DesktopLinkService],
  exports: [DesktopLinkService],
})
export class DesktopLinkModule {}
