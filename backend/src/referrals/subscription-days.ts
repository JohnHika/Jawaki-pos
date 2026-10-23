import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';

const DAY_MS = 86_400_000;

/**
 * Pushes a company's paid-until date forward by `days`. Counts from today when
 * the period has already ended, so free days are never wasted on the past.
 * The same move the platform team's "goodwill extension" makes.
 */
export async function extendSubscriptionDays(
  client: PrismaService | Prisma.TransactionClient,
  tenantId: string,
  days: number,
  now: Date = new Date(),
): Promise<Date> {
  const tenant = await client.tenant.findUnique({
    where: { id: tenantId },
    select: { currentPeriodEnd: true },
  });
  const base = tenant?.currentPeriodEnd && tenant.currentPeriodEnd > now ? tenant.currentPeriodEnd : now;
  const periodEnd = new Date(base.getTime() + days * DAY_MS);
  await client.tenant.update({ where: { id: tenantId }, data: { currentPeriodEnd: periodEnd } });
  return periodEnd;
}
