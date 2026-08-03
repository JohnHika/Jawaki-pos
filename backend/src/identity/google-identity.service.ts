import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';
import { DEFAULT_GOOGLE_WEB_CLIENT_ID } from '../auth/google-auth.config';

@Injectable()
export class GoogleIdentityService {
  constructor(private readonly config: ConfigService) {}

  async verify(idToken: string) {
    const clientId = this.config.get<string>('GOOGLE_WEB_CLIENT_ID') || DEFAULT_GOOGLE_WEB_CLIENT_ID;
    try {
      const ticket = await new OAuth2Client(clientId).verifyIdToken({ idToken, audience: clientId });
      const payload = ticket.getPayload();
      const email = payload?.email?.trim().toLowerCase();
      if (!email || payload?.email_verified !== true) throw new Error('unverified email');
      return { email, firstName: payload.given_name?.trim(), lastName: payload.family_name?.trim() };
    } catch {
      throw new UnauthorizedException('Invalid Google sign-in token');
    }
  }
}
