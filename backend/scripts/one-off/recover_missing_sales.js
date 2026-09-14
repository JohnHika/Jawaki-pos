/**
 * ONE-TIME RECOVERY SCRIPT — replays sales that failed to sync due to the
 * stock_id / MANUAL-payment-method bugs (fixed in 73abc00 / 1e37000).
 *
 * For each distinct offlineId with a FAILED SALE_CREATED sync event and NO
 * matching row in the sales table:
 *   - Creates the Sale + SaleItems, backdated to the original sale time.
 *   - Deducts stock (dated today — per user decision, since we can't
 *     retroactively rewrite the stock timeline safely).
 *   - Creates Payment rows for SPLIT sales' tenders.
 *   - Does NOT touch the cash ledger (per user decision — a per-date total
 *     is printed instead for manual reconciliation).
 *   - Marks the recovered sync events PROCESSED with entityId = new sale id.
 *
 * Run with DRY_RUN=1 first (default) to preview with zero writes.
 * Run with DRY_RUN=0 to actually commit.
 */
const { PrismaClient, PaymentMethod, PaymentStatus, StockMovementType, SaleStatus } = require('@prisma/client');
const { todayInTimezone, getDayBoundsInTimezone } = require('./dist/src/common/operating-hours');
const prisma = new PrismaClient();

const DRY_RUN = process.env.DRY_RUN !== '0';
const RECOVERY_NOTE = 'RECOVERED: sale failed to sync due to a backend bug (stock_id column / missing MANUAL payment method), fixed 2026-09-14. Backdated to original sale time; stock deducted today.';

function computeTotals(payload) {
  const items = payload.items || [];
  let subtotal = 0;
  for (const it of items) {
    const lineTotal = it.total ?? (Number(it.unitPrice) * Number(it.quantity));
    subtotal += Number(lineTotal) - Number(it.discount || 0);
  }
  const taxAmount = Number(payload.taxAmount || 0);
  const discountAmount = Number(payload.discountAmount || 0);
  const totalAmount = payload.totalAmount != null ? Number(payload.totalAmount) : subtotal + taxAmount - discountAmount;
  return { subtotal, taxAmount, discountAmount, totalAmount };
}

function originalTimestamp(payload, firstSyncEvent) {
  // Shape B payloads carry their own createdAt as a naive local wall-clock
  // string with NO timezone suffix (e.g. "2026-08-15T13:24:23.000") — this
  // is the device's local time in the branch's timezone (Africa/Nairobi,
  // fixed UTC+3, no DST). Append the offset explicitly rather than relying
  // on the host process's ambient timezone happening to match.
  // Shape A payloads have no createdAt; fall back to the earliest sync
  // attempt's deviceTimestamp (already a proper UTC ISO string).
  if (payload.createdAt) {
    const naive = payload.createdAt.replace(/(\.\d+)?$/, ''); // strip fractional seconds, keep 'YYYY-MM-DDTHH:mm:ss'
    return new Date(`${naive}+03:00`);
  }
  return firstSyncEvent.deviceTimestamp;
}

async function main() {
  console.log(DRY_RUN ? '=== DRY RUN (no writes) ===' : '=== LIVE RUN (writing to production DB) ===');

  const events = await prisma.syncEvent.findMany({
    where: { eventType: 'SALE_CREATED', status: 'FAILED' },
    orderBy: { createdAt: 'asc' },
  });

  // Group by offlineId, keep ALL events per id (need the earliest for
  // originalTimestamp fallback and ALL ids to mark PROCESSED at the end).
  const byOfflineId = new Map();
  for (const e of events) {
    const oid = e.payload?.offlineId;
    if (!oid) continue;
    if (!byOfflineId.has(oid)) byOfflineId.set(oid, []);
    byOfflineId.get(oid).push(e);
  }

  const candidateOfflineIds = [...byOfflineId.keys()];
  const existingSales = await prisma.sale.findMany({
    where: { offlineId: { in: candidateOfflineIds } },
    select: { offlineId: true },
  });
  const existingSet = new Set(existingSales.map((s) => s.offlineId));
  const trulyMissing = candidateOfflineIds.filter((oid) => !existingSet.has(oid));

  console.log(`Found ${trulyMissing.length} sales to recover.\n`);

  // Resolve tenantId once (single branch/tenant confirmed by prior analysis).
  const branchId = '02e217fa-abfb-4074-a5b8-ea725057ec7d';
  const branch = await prisma.branch.findUnique({ where: { id: branchId }, select: { tenantId: true } });
  const tenantId = branch.tenantId;

  let recovered = 0;
  let failed = 0;
  const cashByDate = {};
  const stockDeductions = new Map(); // productId -> total qty to deduct

  for (const oid of trulyMissing) {
    const attempts = byOfflineId.get(oid).sort((a, b) => a.createdAt - b.createdAt);
    const firstEvent = attempts[0];
    const payload = firstEvent.payload; // items/method are stable across retries
    const when = originalTimestamp(payload, firstEvent);
    const { subtotal, taxAmount, discountAmount, totalAmount } = computeTotals(payload);
    const paidAmount = payload.paidAmount != null ? Number(payload.paidAmount) : totalAmount;
    const changeAmount = Math.max(0, paidAmount - totalAmount);
    const method = payload.paymentMethod;
    const cashierId = payload.cashierId || payload.userId;

    console.log(`[${recovered + failed + 1}/${trulyMissing.length}] offlineId=${oid} when=${when.toISOString()} total=${totalAmount} method=${method}`);

    try {
      if (!DRY_RUN) {
        const receiptNumber = await generateHistoricalReceiptNumber(branchId, when);

        const sale = await createSaleWithRetry(prisma, {
          branchId,
          cashierId,
          receiptNumber,
          payload,
          subtotal,
          taxAmount,
          discountAmount,
          totalAmount,
          paidAmount,
          changeAmount,
          method,
          when,
          oid,
        });

        // Mark ALL sync attempts for this offlineId as recovered (outside
        // the sale transaction — this is bookkeeping, not business data).
        await prisma.syncEvent.updateMany({
          where: { id: { in: attempts.map((a) => a.id) } },
          data: { status: 'PROCESSED', entityId: sale.id, resolution: 'manually_recovered_2026-09-14', processedAt: new Date() },
        });
      }

      recovered++;
      const dateKey = when.toISOString().slice(0, 10);
      cashByDate[dateKey] = cashByDate[dateKey] || { count: 0, amount: 0, byMethod: {} };
      cashByDate[dateKey].count++;
      cashByDate[dateKey].amount += totalAmount;
      cashByDate[dateKey].byMethod[method] = (cashByDate[dateKey].byMethod[method] || 0) + totalAmount;

      for (const it of payload.items || []) {
        stockDeductions.set(it.productId, (stockDeductions.get(it.productId) || 0) + Number(it.quantity));
      }
    } catch (err) {
      failed++;
      console.error(`  FAILED to recover ${oid}:`, err.message);
    }
  }

  console.log(`\n=== SUMMARY ===`);
  console.log(`Recovered: ${recovered}, Failed: ${failed}`);
  console.log(`\nCash reconciliation needed, by date:`);
  for (const [date, v] of Object.entries(cashByDate).sort()) {
    console.log(`${date}: ${v.count} sales, KES ${v.amount} total | by method: ${JSON.stringify(v.byMethod)}`);
  }
  console.log(`\nStock deductions needed (${stockDeductions.size} products):`);
  if (DRY_RUN) {
    console.log('(Will be applied via a separate adjustStock step after sales are created.)');
  }

  // Persist the deduction map for the next step.
  require('fs').writeFileSync(
    'recovery_stock_deductions.json',
    JSON.stringify([...stockDeductions.entries()].map(([productId, qty]) => ({ productId, qty })), null, 2),
  );
  console.log('\nStock deduction plan written to recovery_stock_deductions.json');
}

async function createSaleWithRetry(prismaClient, params) {
  const { branchId, cashierId, payload, subtotal, taxAmount, discountAmount, totalAmount, paidAmount, changeAmount, method, when, oid } = params;
  let receiptNumber = params.receiptNumber;

  // The referenced customer may have been deleted since the original sale
  // attempt (observed for one record) — check once up front rather than
  // let the FK violation abort the transaction on every retry attempt.
  let customerId = payload.customerId || null;
  if (customerId) {
    const customerExists = await prismaClient.customer.findUnique({ where: { id: customerId }, select: { id: true } });
    if (!customerExists) customerId = null;
  }

  const buildData = (rn) => ({
    branchId,
    // deviceId intentionally omitted: the real sync replay path
    // (sync.service.ts createSale call) never sets it either — devices
    // get re-registered/replaced over time, and these payloads' deviceIds
    // no longer exist in the devices table.
    userId: cashierId,
    receiptNumber: rn,
    customerId,
    status: SaleStatus.COMPLETED,
    subtotal,
    taxAmount,
    discountAmount,
    totalAmount,
    paidAmount,
    changeAmount,
    paymentMethod: method,
    notes: RECOVERY_NOTE,
    offlineId: oid,
    metadata: {
      recovered: true,
      recoveredAt: new Date().toISOString(),
      originalPaymentReference: payload.paymentReference || null,
      originalCustomerId: payload.customerId && payload.customerId !== customerId ? payload.customerId : undefined,
    },
    createdAt: when,
    updatedAt: when,
    items: {
      create: (payload.items || []).map((it) => ({
        productId: it.productId,
        productName: it.productName,
        quantity: Number(it.quantity),
        unitPrice: Number(it.unitPrice),
        discount: Number(it.discount || 0),
        taxRate: 0,
        taxAmount: 0,
        totalAmount: Number(it.total ?? (it.unitPrice * it.quantity)),
        unit: it.unit || it.saleUnit || null,
        quantityPerUnit: it.quantityPerUnit || it.unitConversionFactor || null,
      })),
    },
  });

  // Historical receipt-number collisions can happen against pre-existing
  // real sales whose numbering predates some edge case in the day-boundary
  // logic (observed once, for the tenant's very first-ever recorded sale).
  // Postgres aborts the ENTIRE transaction after any error inside it, so
  // the retry must re-run the whole $transaction block with a bumped
  // sequence number — retrying just the failed query inside the same tx
  // throws "current transaction is aborted" on every subsequent statement.
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      return await prismaClient.$transaction(async (tx) => {
        const newSale = await tx.sale.create({ data: buildData(receiptNumber), include: { items: true } });

        if (method === PaymentMethod.SPLIT && payload.tenders) {
          await tx.payment.createMany({
            data: payload.tenders.map((t) => ({
              saleId: newSale.id,
              method: t.method,
              amount: t.amount,
              status: PaymentStatus.COMPLETED,
              transactionId: t.reference || null,
              paidAt: when,
            })),
          });
        }

        return newSale;
      });
    } catch (err) {
      const isReceiptCollision = err?.code === 'P2002' && err?.meta?.target?.includes?.('receiptNumber');
      if (!isReceiptCollision) throw err;
      const m = receiptNumber.match(/^(.*-)(\d{4})$/);
      if (!m) throw err;
      const nextSeq = String(Number(m[2]) + 1).padStart(4, '0');
      receiptNumber = `${m[1]}${nextSeq}`;
    }
  }
  throw new Error(`Could not find a free receipt number after 20 attempts starting from ${params.receiptNumber}`);
}

async function generateHistoricalReceiptNumber(branchId, when) {
  const branch = await prisma.branch.findUnique({ where: { id: branchId }, select: { code: true, timezone: true } });
  const timezone = branch?.timezone || 'Africa/Nairobi';

  // Mirror SalesService.generateReceiptNumber exactly: format the
  // historical instant's calendar date in the branch's own timezone using
  // the same helper the live create-sale path uses, so recovered receipts
  // are indistinguishable in format from ones the app generated itself.
  const fmt = new Intl.DateTimeFormat('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' });
  const parts = fmt.formatToParts(when).reduce((acc, p) => ({ ...acc, [p.type]: p.value }), {});
  const dateStr = `${parts.year}-${parts.month}-${parts.day}`;
  const datePrefix = dateStr.replace(/-/g, '');
  const prefix = `${branch?.code || 'POS'}-${datePrefix}`;

  const { start, end } = getDayBoundsInTimezone(dateStr, timezone);
  const count = await prisma.sale.count({ where: { branchId, createdAt: { gte: start, lt: end } } });
  const seq = String(count + 1).padStart(4, '0');
  return `${prefix}-${seq}`;
}

main().catch((e) => { console.error(e); process.exit(1); }).finally(() => prisma.$disconnect());
