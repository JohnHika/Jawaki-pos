import { THROTTLER_LIMITERS } from './throttler-limiters';

describe('THROTTLER_LIMITERS', () => {
  it('registers only the default limiter', () => {
    // A second named limiter is applied by ThrottlerGuard to every guarded
    // route and cannot be overridden by @Throttle({ default }).
    expect(THROTTLER_LIMITERS.map((limiter) => limiter.name)).toEqual(['default']);
  });

  it('leaves room for polling routes that set their own limit', () => {
    const [limiter] = THROTTLER_LIMITERS;
    expect(limiter.limit).toBeGreaterThanOrEqual(100);
  });
});
