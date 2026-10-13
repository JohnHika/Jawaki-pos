import { ValidationPipe } from '@nestjs/common';
import { ReportFilterDto } from './reporting.dto';

/**
 * The app's global ValidationPipe rejects unknown query properties, so every
 * parameter the mobile app sends must be declared on the DTO. `limit` wasn't,
 * which made Reports -> Top Products fail with HTTP 400 on every request.
 */
describe('ReportFilterDto through the global ValidationPipe', () => {
  const pipe = new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
    transformOptions: { enableImplicitConversion: true },
  });
  const run = (query: Record<string, unknown>) =>
    pipe.transform(query, { type: 'query', metatype: ReportFilterDto });

  it('accepts the exact top-products query the mobile app sends', async () => {
    const parsed: any = await run({
      startDate: '2026-10-13',
      endDate: '2026-10-13',
      branchId: 'a780552d-f7b7-4638-a8dd-fc46d0ba0180',
      limit: '20',
    });
    expect(parsed.limit).toBe(20);
  });

  it('rejects out-of-range or non-numeric limits', async () => {
    await expect(run({ limit: '0' })).rejects.toBeDefined();
    await expect(run({ limit: '101' })).rejects.toBeDefined();
    await expect(run({ limit: 'abc' })).rejects.toBeDefined();
  });

  it('still rejects genuinely unknown parameters', async () => {
    await expect(run({ nonsense: '1' })).rejects.toBeDefined();
  });

  it('works without a limit', async () => {
    const parsed: any = await run({ startDate: '2026-10-13', endDate: '2026-10-13' });
    expect(parsed.limit).toBeUndefined();
  });
});
