import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { RedisService } from './common/redis/redis.service';
import { AppModule } from './app.module';
import { PrismaService } from './common/prisma/prisma.service';
import { AccountabilityService } from './accountability/accountability.service';
import { StocktakeService } from './stocktake/stocktake.service';
import { ImportsService } from './imports/imports.service';
import { NewsService } from './news/news.service';
import { ExchangeRatesService } from './exchange-rates/exchange-rates.service';
import { SalesService } from './sales/sales.service';
import { InventoryService } from './inventory/inventory.service';
import { CatalogService } from './catalog/catalog.service';
import { CustomersService } from './customers/customers.service';
import { CashReconciliationService } from './cash-flow/cash-reconciliation.service';

/**
 * Guards against the failure unit tests cannot see: a provider that needs
 * something its module never imported, or a module cycle. Nest only reports
 * that when the app boots, which is too late (it would take the API down).
 * No database is touched - Prisma is stubbed and lifecycle hooks never run.
 */
/** Placeholder config shaped like the real thing, so constructors that validate their input still boot. */
function dummy(key: string): string {
  if (/EMAIL/i.test(key)) return 'test@example.com';
  if (/URL|URI|HOST/i.test(key)) return 'https://example.com';
  return `test-${key}`;
}

describe('AppModule dependency graph', () => {
  it('resolves every provider, including the accountability wiring', async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaService)
      .useValue({ $connect: jest.fn(), $disconnect: jest.fn() })
      // Never talk to real Redis or read real credentials from a developer's .env.
      .overrideProvider(RedisService)
      .useValue({ invalidatePattern: jest.fn(), onModuleDestroy: jest.fn() })
      .overrideProvider(ConfigService)
      .useValue({ get: (key: string, fallback?: unknown) => fallback ?? dummy(key), getOrThrow: (key: string) => dummy(key) })
      .compile();

    expect(moduleRef.get(AccountabilityService, { strict: false })).toBeDefined();
    expect(moduleRef.get(StocktakeService, { strict: false })).toBeDefined();
    expect(moduleRef.get(ImportsService, { strict: false })).toBeDefined();
    expect(moduleRef.get(NewsService, { strict: false })).toBeDefined();
    expect(moduleRef.get(ExchangeRatesService, { strict: false })).toBeDefined();

    // The optional accountability dependency must actually be injected in
    // production, or the guards silently do nothing.
    for (const token of [
      SalesService,
      InventoryService,
      CatalogService,
      CustomersService,
      CashReconciliationService,
    ]) {
      const service = moduleRef.get(token as any, { strict: false }) as any;
      expect(service.accountability).toBeInstanceOf(AccountabilityService);
    }

    await moduleRef.close();
  }, 120_000);
});
