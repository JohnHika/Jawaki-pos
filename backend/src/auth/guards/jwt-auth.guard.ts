import {
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  handleRequest<TUser = any>(
    err: any,
    user: TUser,
    _info: any,
    context: ExecutionContext,
  ): TUser {
    if (err || !user) {
      throw err || new UnauthorizedException('Authentication required');
    }

    const activationStatus = (user as any).activationStatus;
    if (activationStatus === 'PENDING' && !this.isActivationRoute(context)) {
      throw new HttpException(
        'Company activation payment is required before using Axon POS.',
        HttpStatus.PAYMENT_REQUIRED,
      );
    }

    return user;
  }

  private isActivationRoute(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const path = `${request.baseUrl ?? ''}${request.path ?? request.url ?? ''}`;
    return (
      path.includes('/tenant-activation') ||
      path.includes('/branches/tenants/current') ||
      path.includes('/uploads/')
    );
  }
}
