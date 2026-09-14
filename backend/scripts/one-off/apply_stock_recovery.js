/**
 * STEP 2 of recovery — applies the stock deductions computed by
 * recover_missing_sales.js (recovery_stock_deductions.json) as a single
 * dated-today adjustment per product, via the same inventory service path
 * as any other stock correction (ADJUSTMENT_OUT movement type).
 *
 * Does NOT let any product go negative: if the deduction would exceed
 * current stock, it clamps at 0 and logs a warning instead of erroring —
 * per the pre-flight check, only "Vaseline 25 g" (short by 1) hits this.
 *
 * Run with DRY_RUN=1 first (default), DRY_RUN=0 to commit.
 */
const { PrismaClient, StockMovementType } = require('@prisma/client');
const fs = require('fs');
const prisma = new PrismaClient();

const DRY_RUN = process.env.DRY_RUN !== '0';
const branchId = '02e217fa-abfb-4074-a5b8-ea725057ec7d';

async function main() {
  console.log(DRY_RUN ? '=== DRY RUN (no writes) ===' : '=== LIVE RUN (writing to production DB) ===');

  const plan = JSON.parse(fs.readFileSync('recovery_stock_deductions.json', 'utf8'));
  console.log(`Applying deductions for ${plan.length} products.\n`);

  const productIds = plan.map((p) => p.productId);
  const stocks = await prisma.stock.findMany({ where: { branchId, productId: { in: productIds } } });
  const products = await prisma.product.findMany({ where: { id: { in: productIds } }, select: { id: true, name: true } });
  const stockByProduct = new Map(stocks.map((s) => [s.productId, s]));
  const nameByProduct = new Map(products.map((p) => [p.id, p.name]));

  let applied = 0;
  let clamped = 0;
  const RECOVERY_SYSTEM_USER = null; // no specific user attribution; recorded in notes instead

  for (const { productId, qty } of plan) {
    const stock = stockByProduct.get(productId);
    const name = nameByProduct.get(productId) || productId;
    if (!stock) {
      console.log(`SKIP (no stock row exists): ${name}`);
      continue;
    }
    const current = Number(stock.quantity);
    const wanted = current - qty;
    const finalQty = Math.max(0, wanted);
    const actualDeducted = current - finalQty;
    if (wanted < 0) {
      clamped++;
      console.log(`CLAMPED: ${name} current=${current} requested_deduct=${qty} -> clamped to 0 (deducted ${actualDeducted} instead of ${qty})`);
    } else {
      console.log(`${name}: ${current} -> ${finalQty} (deduct ${actualDeducted})`);
    }

    if (!DRY_RUN && actualDeducted > 0) {
      await prisma.$transaction(async (tx) => {
        await tx.stock.update({ where: { id: stock.id }, data: { quantity: finalQty } });
        await tx.stockMovement.create({
          data: {
            branchId,
            productId,
            type: StockMovementType.ADJUSTMENT_OUT,
            quantity: -actualDeducted,
            previousQty: current,
            newQty: finalQty,
            reference: 'recovery-2026-09-14',
            notes: 'Backfill deduction for 77 sales recovered from failed sync events (stock_id/MANUAL payment bugs, fixed 2026-09-14). Deducted today because the original sale dates cannot be safely rewritten into the stock timeline.',
            createdById: null,
          },
        });
      });
    }
    applied++;
  }

  console.log(`\nApplied: ${applied}, Clamped-at-zero: ${clamped}`);
}

main().catch((e) => { console.error(e); process.exit(1); }).finally(() => prisma.$disconnect());
