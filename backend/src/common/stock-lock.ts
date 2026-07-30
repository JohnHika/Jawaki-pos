import { Prisma } from '@prisma/client';

export type LockedStock = {
  id: string;
  quantity: unknown;
};

/**
 * Serializes every writer for one branch/product pair, including creation of
 * the first Stock row, then returns the quantity protected by FOR UPDATE.
 * Callers must calculate previous/new movement balances only from this row.
 */
export async function lockStockForUpdate(
  tx: Prisma.TransactionClient,
  branchId: string,
  productId: string,
  createIfMissing = false,
): Promise<LockedStock | null> {
  await tx.$executeRaw`
    SELECT pg_advisory_xact_lock(
      hashtext(${branchId}),
      hashtext(${productId})
    )
  `;

  let stock = await tx.stock.findUnique({
    where: {
      branchId_productId: { branchId, productId },
    },
    select: { id: true },
  });

  if (!stock && createIfMissing) {
    stock = await tx.stock.create({
      data: { branchId, productId, quantity: 0 },
      select: { id: true },
    });
  }

  if (!stock) return null;

  const [lockedStock] = await tx.$queryRaw<LockedStock[]>`
    SELECT id, quantity
    FROM stock
    WHERE id = ${stock.id}
    FOR UPDATE
  `;

  return lockedStock ?? null;
}
