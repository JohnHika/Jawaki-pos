import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../common/prisma/prisma.service';

/** Currencies a Kamukunji importer is likely to buy or pay freight in. */
export const TRACKED_CURRENCIES = [
  'USD',
  'CNY',
  'AED',
  'EUR',
  'GBP',
  'TRY',
  'INR',
  'JPY',
  'ZAR',
  'UGX',
  'TZS',
] as const;

const PROVIDER_URL = 'https://open.er-api.com/v6/latest/USD';
const FRESH_MS = 12 * 60 * 60 * 1000;
const FETCH_TIMEOUT_MS = 10_000;

export interface RateBoard {
  /** Every rate below is "KES for 1 unit of this currency". */
  base: 'KES';
  updatedAt: Date | null;
  stale: boolean;
  rates: Record<string, number>;
  attribution: string;
  disclaimer: string;
}

/** KES per 1 unit of `currency`, from USD-based provider rates. */
export function kesPer(usdRates: Record<string, number>, currency: string): number | null {
  const code = currency.toUpperCase();
  if (code === 'KES') return 1;
  const kes = usdRates.KES;
  const other = code === 'USD' ? 1 : usdRates[code];
  if (!Number.isFinite(kes) || !Number.isFinite(other) || !kes || !other) return null;
  return Math.round((kes / other) * 10_000) / 10_000;
}

@Injectable()
export class ExchangeRatesService {
  private readonly logger = new Logger(ExchangeRatesService.name);

  constructor(private readonly prisma: PrismaService) {}

  /** Pulls fresh rates and stores a snapshot. Returns false (and keeps the old rates) if the provider is down. */
  async refresh(): Promise<boolean> {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
      const response = await fetch(PROVIDER_URL, { signal: controller.signal }).finally(() =>
        clearTimeout(timer),
      );
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const body = (await response.json()) as {
        result?: string;
        rates?: Record<string, number>;
        time_last_update_unix?: number;
      };
      if (body.result !== 'success' || !body.rates?.KES) {
        throw new Error('Unexpected response from the rates provider');
      }

      const wanted: Record<string, number> = { USD: 1, KES: body.rates.KES };
      for (const code of TRACKED_CURRENCIES) {
        if (typeof body.rates[code] === 'number') wanted[code] = body.rates[code];
      }
      await this.prisma.exchangeRateSnapshot.create({
        data: {
          base: 'USD',
          rates: wanted,
          providerUpdatedAt: body.time_last_update_unix
            ? new Date(body.time_last_update_unix * 1000)
            : null,
        },
      });
      // Keep the table small: a month of snapshots is plenty.
      await this.prisma.exchangeRateSnapshot.deleteMany({
        where: { fetchedAt: { lt: new Date(Date.now() - 30 * 86_400_000) } },
      });
      return true;
    } catch (error) {
      this.logger.warn(`Exchange rate refresh failed: ${error instanceof Error ? error.message : error}`);
      return false;
    }
  }

  @Cron('15 */6 * * *')
  async scheduledRefresh() {
    await this.refresh();
  }

  private async latestSnapshot() {
    return this.prisma.exchangeRateSnapshot.findFirst({ orderBy: { fetchedAt: 'desc' } });
  }

  /** Latest board, refreshing first when the stored one is old. Falls back to stale rates rather than none. */
  async getBoard(): Promise<RateBoard> {
    let snapshot = await this.latestSnapshot();
    if (!snapshot || Date.now() - snapshot.fetchedAt.getTime() > FRESH_MS) {
      await this.refresh();
      snapshot = await this.latestSnapshot();
    }

    const usd = (snapshot?.rates ?? {}) as Record<string, number>;
    const rates: Record<string, number> = {};
    for (const code of TRACKED_CURRENCIES) {
      const value = kesPer(usd, code);
      if (value !== null) rates[code] = value;
    }

    return {
      base: 'KES',
      updatedAt: snapshot?.providerUpdatedAt ?? snapshot?.fetchedAt ?? null,
      stale: !snapshot || Date.now() - snapshot.fetchedAt.getTime() > 2 * FRESH_MS,
      rates,
      attribution: 'Rates by ExchangeRate-API (exchangerate-api.com)',
      disclaimer:
        'Indicative mid-market rates. Your bank, forex bureau or clearing agent will use a different rate — check it before you pay.',
    };
  }

  /** KES per 1 unit of `currency`, or null when unknown. */
  async rateFor(currency: string): Promise<number | null> {
    const code = currency.toUpperCase();
    if (code === 'KES') return 1;
    const board = await this.getBoard();
    return board.rates[code] ?? null;
  }
}
