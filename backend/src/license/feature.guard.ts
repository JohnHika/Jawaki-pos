import {
  CanActivate,
  ExecutionContext,
  Injectable,
  SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { LicenseFeature } from './license.catalog';
import { LicenseService } from './license.service';

export const REQUIRES_FEATURE_KEY = 'requires_license_feature';

/** Marks a route (or controller) as part of a licensable module. */
export const RequiresFeature = (feature: LicenseFeature) =>
  SetMetadata(REQUIRES_FEATURE_KEY, feature);

/**
 * Refuses the request with 402 FEATURE_NOT_LICENSED when the caller's company
 * has not paid for the module. A no-op unless that company's licence is in
 * `enforce` mode, so adding the decorator to a route never changes behaviour
 * on its own. Unlike the subscription guard this blocks reads too: the module
 * itself is what is not licensed, not the company's historical data.
 */
@Injectable()
export class FeatureGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly license: LicenseService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const feature = this.reflector.getAllAndOverride<LicenseFeature | undefined>(
      REQUIRES_FEATURE_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (!feature) return true;

    const tenantId: string | undefined = context
      .switchToHttp()
      .getRequest().user?.tenantId;
    // Platform-admin tokens carry no tenant and are never gated.
    if (!tenantId) return true;

    await this.license.assertFeature(tenantId, feature);
    return true;
  }
}
