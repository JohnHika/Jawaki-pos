import { Injectable, OnModuleDestroy, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly client: Redis;
  private readonly logger = new Logger(RedisService.name);

  constructor(private configService: ConfigService) {
    this.client = new Redis({
      host: this.configService.get<string>('REDIS_HOST', 'localhost'),
      port: this.configService.get<number>('REDIS_PORT', 6379),
      password: this.configService.get<string>('REDIS_PASSWORD') || undefined,
    });
  }

  getClient(): Redis {
    return this.client;
  }

  /**
   * Reads/writes below fail soft (log + return null/no-op) rather than
   * throwing. Redis here is purely a performance cache and a sequence
   * counter store — a Redis outage must degrade to "slightly slower" or
   * "counter recalculated from the DB," never "the request fails," since a
   * cache being unavailable is not the same as the data being unavailable.
   * This distinguishes cache/counter reads (soft-fail) from anything that
   * would be a correctness issue if silently skipped — there is currently
   * no such usage of RedisService in this codebase.
   */
  async get(key: string): Promise<string | null> {
    try {
      return await this.client.get(key);
    } catch (error) {
      this.logger.warn(`Redis GET failed for key ${key}: ${error.message}`);
      return null;
    }
  }

  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    try {
      if (ttlSeconds) {
        await this.client.set(key, value, 'EX', ttlSeconds);
      } else {
        await this.client.set(key, value);
      }
    } catch (error) {
      this.logger.warn(`Redis SET failed for key ${key}: ${error.message}`);
    }
  }

  async del(key: string): Promise<void> {
    try {
      await this.client.del(key);
    } catch (error) {
      this.logger.warn(`Redis DEL failed for key ${key}: ${error.message}`);
    }
  }

  async exists(key: string): Promise<boolean> {
    try {
      const result = await this.client.exists(key);
      return result === 1;
    } catch (error) {
      this.logger.warn(`Redis EXISTS failed for key ${key}: ${error.message}`);
      return false;
    }
  }

  async setJson(key: string, value: object, ttlSeconds?: number): Promise<void> {
    await this.set(key, JSON.stringify(value), ttlSeconds);
  }

  async getJson<T>(key: string): Promise<T | null> {
    const value = await this.get(key);
    if (!value) return null;
    try {
      return JSON.parse(value) as T;
    } catch (error) {
      this.logger.warn(`Redis value for key ${key} was not valid JSON: ${error.message}`);
      return null;
    }
  }

  async invalidatePattern(pattern: string): Promise<void> {
    try {
      const keys = await this.client.keys(pattern);
      if (keys.length > 0) {
        await this.client.del(...keys);
      }
    } catch (error) {
      this.logger.warn(`Redis invalidatePattern failed for pattern ${pattern}: ${error.message}`);
    }
  }

  // Cache-aside pattern helper. On any cache failure (get or set), falls
  // through to calling factory() directly — a slow/unavailable cache must
  // never be the reason a real request fails.
  async getOrSet<T>(
    key: string,
    factory: () => Promise<T>,
    ttlSeconds: number,
  ): Promise<T> {
    const cached = await this.getJson<T>(key);
    if (cached) return cached;

    const value = await factory();
    await this.setJson(key, value as object, ttlSeconds);
    return value;
  }

  async onModuleDestroy() {
    await this.client.quit();
  }
}
