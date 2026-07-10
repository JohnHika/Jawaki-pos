import { Injectable, ExecutionContext } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/**
 * Like JwtAuthGuard but never rejects: if a valid bearer token is present,
 * `req.user` is populated; if it's missing or invalid, the request still
 * proceeds with `req.user` undefined. Used on AI endpoints so features that
 * need identity (shared per-shop history) light up for authenticated
 * clients, without breaking older app builds that don't send the token yet.
 */
@Injectable()
export class OptionalJwtAuthGuard extends AuthGuard('jwt') {
  // Passport throws when there's no/invalid user unless we override this.
  handleRequest(_err: any, user: any) {
    return user || undefined;
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    try {
      await super.canActivate(context);
    } catch {
      // ignore — unauthenticated is allowed
    }
    return true;
  }
}
