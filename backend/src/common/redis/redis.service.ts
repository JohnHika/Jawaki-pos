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

  async get(key: string): Promise<string | null> {
    try {
      return await this.client.get(key);
    } catch (error) {
      this.logger.error(`Redis GET failed for key ${key}: ${error.message}`);
      throw new Error('Redis service unavailable. Please try again later.');
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
      this.logger.error(`Redis SET failed for key ${key}: ${error.message}`);
      throw new Error('Redis service unavailable. Please try again later.');
    }
  }

  async del(key: string): Promise<void> {
    try {
      await this.client.del(key);
    } catch (error) {
      this.logger.error(`Redis DEL failed for key ${key}: ${error.message}`);
      throw new Error('Redis service unavailable. Please try again later.');
    }
  }

  async exists(key: string): Promise<boolean> {
    try {
      const result = await this.client.exists(key);
      return result === 1;
    } catch (error) {
      this.logger.error(`Redis EXISTS failed for key ${key}: ${error.message}`);
      throw new Error('Redis service unavailable. Please try again later.');
    }
  }

  async setJson(key: string, value: object, ttlSeconds?: number): Promise<void> {
    await this.set(key, JSON.stringify(value), ttlSeconds);
  }

  async getJson<T>(key: string): Promise<T | null> {
    const value = await this.get(key);
    if (!value) return null;
    return JSON.parse(value) as T;
  }

  async invalidatePattern(pattern: string): Promise<void> {
    try {
      const keys = await this.client.keys(pattern);
      if (keys.length > 0) {
        await this.client.del(...keys);
      }
    } catch (error) {
      this.logger.error(`Redis invalidatePattern failed for pattern ${pattern}: ${error.message}`);
      throw new Error('Redis service unavailable. Please try again later.');
    }
  }

  // Cache-aside pattern helper
  async getOrSet<T>(
    key: string,
    factory: () => Promise<T>,
    ttlSeconds: number,
  ): Promise<T> {
    try {
      const cached = await this.getJson<T>(key);
      if (cached) return cached;

      const value = await factory();
      await this.setJson(key, value as object, ttlSeconds);
      return value;
    } catch (error) {
      this.logger.error(`Redis getOrSet failed for key ${key}: ${error.message}`);
      throw new Error('Redis service unavailable. Please try again later.');
    }
  }

  async onModuleDestroy() {
    await this.client.quit();
  }
}
