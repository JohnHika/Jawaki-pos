import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
  Optional,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PrismaService } from '../common/prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { resolveLicense } from '../license/license.catalog';
import { isTenantRestricted } from './recurring-billing.service';
import { PUBLIC_SUBSCRIPTION_EXEMPT_KEY } from './subscription-exempt.decorator';

/**
 * Restricted-mode gate for the subscription billing model.
 *
 * Rules (per John's requirement — never block historical data):
 *  - GET/HEAD requests always pass: read-only access is never blocked, so
 *    staff can still view past sales, expenses, and receipts while suspended.
 *  - ACTIVE or TRIAL tenants pass everything.
 *  - PAST_DUE within the grace window passes (grace keeps write access).
 *  - PAST_DUE beyond grace (or SUSPENDED/CANCELLED): mutating requests are
 *    rejected with 402 Payment Required.
 *
 * Applied per-route (sales create, expenses create, supplier invoice
 * create) rather than globally, so unguarded modules keep their current
 * behaviour until they are opted in.
 */
@Injectable()
export class SubscriptionGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
    @Optional() private readonly config?: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    // Routes explicitly marked exempt (e.g. billing recovery endpoints)
    // always pass.
    const exempt = this.reflector.getAllAndOverride<boolean>(
      PUBLIC_SUBSCRIPTION_EXEMPT_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (exempt) return true;

    const request = context.switchToHttp().getRequest();
    const method: string = (request.method ?? 'GET').toUpperCase();
    // Read-only verbs are never blocked — historical data must stay visible.
    if (method === 'GET' || method === 'HEAD' || method === 'OPTIONS') {
      return true;
    }

    const tenantId: string | undefined = request.user?.tenantId;
    if (!tenantId) {
      // No tenant in the JWT (e.g. platform-admin JWTs): the guard only
      // governs tenant staff, so pass through.
      return true;
    }

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: {
        subscriptionStatus: true,
        currentPeriodEnd: true,
        plan: true,
        maxBranches: true,
        maxUsers: true,
        settings: true,
      },
    });
    if (!tenant) return true;

    // An enforced licence that has run out stops new records the same way an
    // unpaid subscription does; viewing history stays open (GET passes above).
    const license = resolveLicense(tenant, {
      defaultMode:
        this.config?.get<'off' | 'warn' | 'enforce'>('LICENSE_ENFORCEMENT') ?? 'off',
    });
    if (license.enforced && license.expired) {
      throw new HttpException(
        {
          message:
            'Your licence has expired. Contact support to renew it. Viewing existing data is still available.',
          code: 'LICENSE_EXPIRED',
          validUntil: license.validUntil,
        },
        HttpStatus.PAYMENT_REQUIRED,
      );
    }

    const verdict = isTenantRestricted(tenant);
    if (verdict.restricted) {
      throw new HttpException(
        {
          message:
            'Your subscription payment is overdue. Please complete payment to continue creating new records. Viewing existing data is still available.',
          code: 'SUBSCRIPTION_PAYMENT_REQUIRED',
          reason: verdict.reason,
        },
        HttpStatus.PAYMENT_REQUIRED,
      );
    }
    return true;
  }
}