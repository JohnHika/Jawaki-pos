/**
 * The app's one rate limiter.
 *
 * ThrottlerGuard applies EVERY limiter registered in ThrottlerModule.forRoot
 * to every route it guards, and `@Throttle({ default: ... })` only overrides
 * the one named `default`. A second named limiter therefore caps all guarded
 * routes at its own limit no matter what the route asks for (a `bug-report`
 * limiter of 5 per minute once refused the computer's third sign-in poll, and
 * also capped login, refresh, billing and payments).
 *
 * Keep this list to the single `default` entry. A route that needs a different
 * limit sets it with `@Throttle({ default: { ttl, limit } })`; a route that
 * must not be limited uses `@SkipThrottle()`.
 */
export const THROTTLER_LIMITERS = [
  {
    name: 'default',
    ttl: 60_000,
    limit: 100,
  },
];
