import { Module } from '@nestjs/common';
import { EmailOtpService } from './email-otp.service';
import { GoogleIdentityService } from './google-identity.service';
import { TransactionalEmailService } from './transactional-email.service';

@Module({
  providers: [TransactionalEmailService, EmailOtpService, GoogleIdentityService],
  exports: [TransactionalEmailService, EmailOtpService, GoogleIdentityService],
})
export class IdentityModule {}
