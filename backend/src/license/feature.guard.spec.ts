import { HttpException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { FeatureGuard, REQUIRES_FEATURE_KEY, RequiresFeature } from './feature.guard';
import { LicenseService } from './license.service';

class Demo {
  @RequiresFeature('analytics')
  gated() {}
  open() {}
}

const ctx = (handler: () => void, user: any) =>
  ({
    getHandler: () => handler,
    getClass: () => Demo,
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  }) as any;

describe('FeatureGuard', () => {
  const build = (assertFeature: jest.Mock) =>
    new FeatureGuard(new Reflector(), { assertFeature } as unknown as LicenseService);

  it('records the required module on the route', () => {
    expect(Reflect.getMetadata(REQUIRES_FEATURE_KEY, Demo.prototype.gated)).toBe('analytics');
  });

  it('passes routes that are not part of a licensed module', async () => {
    const assertFeature = jest.fn();
    await expect(build(assertFeature).canActivate(ctx(Demo.prototype.open, { tenantId: 't1' }))).resolves.toBe(true);
    expect(assertFeature).not.toHaveBeenCalled();
  });

  it('asks the licence for the caller company and lets a licensed one through', async () => {
    const assertFeature = jest.fn().mockResolvedValue(undefined);
    await expect(build(assertFeature).canActivate(ctx(Demo.prototype.gated, { tenantId: 't1' }))).resolves.toBe(true);
    expect(assertFeature).toHaveBeenCalledWith('t1', 'analytics');
  });

  it('propagates the 402 for an unlicensed module', async () => {
    const assertFeature = jest.fn().mockRejectedValue(new HttpException({ code: 'FEATURE_NOT_LICENSED' }, 402));
    await expect(build(assertFeature).canActivate(ctx(Demo.prototype.gated, { tenantId: 't1' }))).rejects.toMatchObject({ status: 402 });
  });

  it('never gates a token without a company (platform admin)', async () => {
    const assertFeature = jest.fn();
    await expect(build(assertFeature).canActivate(ctx(Demo.prototype.gated, {}))).resolves.toBe(true);
    expect(assertFeature).not.toHaveBeenCalled();
  });
});
