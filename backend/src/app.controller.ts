import { Controller, Get, VERSION_NEUTRAL, ServiceUnavailableException } from '@nestjs/common';
import { PrismaService } from './common/prisma/prisma.service';

@Controller({ version: VERSION_NEUTRAL })
export class AppController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('/')
  root() {
    return {
      status: 'ok',
      name: 'Arche Axon POS API',
      message: 'Backend is running successfully',
      docs: '/api/docs',
      health: '/health',
      timestamp: new Date(),
    };
  }

  @Get('/health')
  health() {
    return {
      status: 'ok',
      message: 'POS System is running',
      timestamp: new Date(),
    };
  }

  /**
   * Database-touching health check for the keep-alive cron. /health only
   * proves the HTTP layer is alive — it never reaches Postgres, so Neon's
   * free compute still suspends after 5 idle minutes and the first user's
   * first query pays the full wake penalty. This endpoint runs SELECT 1
   * so pinging it keeps BOTH Render and Neon warm.
   */
  @Get('/health/db')
  async healthDb() {
    try {
      const started = Date.now();
      await this.prisma.$queryRaw`SELECT 1`;
      return {
        status: 'ok',
        database: 'connected',
        queryMs: Date.now() - started,
        timestamp: new Date(),
      };
    } catch {
      throw new ServiceUnavailableException('Database unreachable');
    }
  }
}