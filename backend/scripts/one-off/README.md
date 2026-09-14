# One-off recovery scripts — DO NOT RE-RUN

These scripts were run exactly once, on 2026-09-14, to recover 77 sales
that failed to sync to production due to two now-fixed bugs:

1. `sales.service.ts` raw SQL referenced a non-existent `stock_id` column
   (real column is camelCase `"stockId"`) — fixed in commit `73abc00`.
2. The `PaymentMethod` enum was missing `MANUAL`, which the mobile app's
   "Manual" payment option sends — fixed in commit `1e37000`.

Both bugs caused affected sales to print a receipt on-device (local
SQLite committed) while silently failing to ever reach the `sales` table
on the server, from at least 2026-07-09 through 2026-09-14.

## What ran

- `recover_missing_sales.js` — replayed each failed sync event's payload
  into a real `Sale` + `SaleItem` (+ `Payment` rows for SPLIT sales),
  backdated to the original sale time, idempotent on `Sale.offlineId`.
- `apply_stock_recovery.js` — deducted stock for the recovered sales'
  items, dated the day the fix shipped (not backdated — the stock
  timeline can't be safely rewritten), clamping at zero instead of
  going negative.

**Result: 77/77 sales recovered, KES 89,440 total, verified against
item-level sums with zero discrepancies.** Cash-ledger entries were
deliberately NOT created (per owner decision) — reconcile the affected
dates manually against physical cash/M-Pesa records instead:

| Date | Sales | KES |
|---|---|---|
| 2026-07-09 | 1 | 6,000 |
| 2026-07-11 | 1 | 6,150 |
| 2026-08-14 | 17 | 7,055 |
| 2026-08-15 | 21 | 18,230 |
| 2026-08-17 | 19 | 29,750 |
| 2026-08-19 | 1 | 1,080 |
| 2026-08-26 | 2 | 2,560 |
| 2026-09-12 | 13 | 11,905 |
| 2026-09-14 | 2 | 6,710 |

Recovered sales are tagged `notes` containing `"RECOVERED"` and
`metadata.recovered = true` for easy identification/audit later.

## Why not to re-run

- `recover_missing_sales.js` is idempotent (checks `Sale.offlineId`
  first) so re-running it is harmless by itself — but there is nothing
  left to recover; a re-run against current data will just report 0.
- `apply_stock_recovery.js` reads from `recovery_stock_deductions.json`,
  which was deleted after use — it has no input file to run against.
- If a similar backend bug causes silent sync failures again in the
  future, don't reuse these scripts as-is: re-derive the failed-event
  set and payload shapes fresh, since sync payload formats have already
  been observed to vary across app versions (see the two payload
  "shapes" handled in `recover_missing_sales.js`).
