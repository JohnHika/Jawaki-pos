import { Prisma } from '@prisma/client';

/**
 * New average cost per unit when `receivedQty` units arrive at
 * `receivedUnitCost` on top of `onHandQty` units valued at `currentCost`.
 * With nothing on hand (or no known cost) the new cost is simply what the
 * new units cost.
 */
export function weightedAverageCost(
  onHandQty: number,
  currentCost: number | null,
  receivedQty: number,
  receivedUnitCost: number,
): number {
  const round2 = (n: number) => Math.round(n * 100) / 100;
  if (receivedQty <= 0) return currentCost ?? receivedUnitCost;
  if (onHandQty <= 0 || !currentCost || currentCost <= 0) return round2(receivedUnitCost);
  return round2(
    (onHandQty * currentCost + receivedQty * receivedUnitCost) / (onHandQty + receivedQty),
  );
}

/**
 * Keeps `Product.costPrice` equal to what the stock on the shelf actually
 * cost, every time stock is bought in. Without this the field stays empty for
 * most shops (nothing else ever writes it), so margin reports fall back to a
 * guessed 70% of the selling price and the "sold below cost" check has
 * nothing to compare against.
 *
 * Call inside the same transaction as the stock change. `previousQty` is the
 * quantity on hand BEFORE this receipt. Costs of zero or less are ignored: a
 * free sample or a typing slip must not drag the average to nothing.
 */
export async function applyPurchaseCost(
  tx: Prisma.TransactionClient,
  productId: string,
  previousQty: number,
  receivedQty: number,
  unitCost: number | null | undefined,
): Promise<void> {
  if (unitCost === null || unitCost === undefined || !(unitCost > 0) || !(receivedQty > 0)) return;

  const product = await tx.product.findUnique({
    where: { id: productId },
    select: { costPrice: true },
  });
  if (!product) return;

  const current = product.costPrice === null ? null : Number(product.costPrice);
  const next = weightedAverageCost(previousQty, current, receivedQty, unitCost);
  if (current !== null && Math.abs(next - current) < 0.005) return;

  await tx.product.update({ where: { id: productId }, data: { costPrice: next } });
}
