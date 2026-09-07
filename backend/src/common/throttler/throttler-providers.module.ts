import { Module } from '@nestjs/common';
import { ThrottlerModule } from '@nestjs/throttler';

/**
 * Shared wiring for @nestjs/throttler. ThrottlerModule.forRoot() lives in
 * AppModule; importing it again here (Nest dedupes dynamic-module config to
 * the first registration, so options are not duplicated) re-exports the
 * THROTTLER_OPTIONS and ThrottlerStorage providers into the importing
 * feature module's injector context. Without this, ThrottlerGuard injected
 * via @UseGuards(ThrottlerGuard) in another module cannot resolve its
 * options/storage and the route 500s on first request.
 *
 * ThrottlerGuard itself is NOT globally registered in this app, so a route
 * must opt in explicitly:
 *   @UseGuards(ThrottlerGuard)
 *   @Throttle({ default: { ttl: 60000, limit: 5 } })
 * The `default` named limiter maps to the first (name: 'default') entry of
 * ThrottlerModule.forRoot in app.module.ts; without @Throttle the global
 * default (100/min) would apply instead.
 */
@Module({
  imports: [ThrottlerModule.forRoot([])],
  exports: [ThrottlerModule],
})
export class ThrottlerProvidersModule {}