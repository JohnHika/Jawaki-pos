# Shop control: accountability, stock counts, landed cost, news

Built for small importers and wholesalers (the Kamukunji model): goods come in
by shared container from China or Dubai, are sold by staff the owner cannot
always watch, and a good share of the sales are on credit. The aim is that the
owner can see what happened without being in the shop.

Everything here is **additive**. Defaults never refuse a sale; the owner turns
strictness up when staff are used to the rules.

## What it does

| Area | What the owner gets |
|---|---|
| **Price guard** | The till warns, or blocks, a sale below cost, below a product's minimum price, or with a discount over the cashier limit. |
| **Credit control** | A per-customer credit limit (with ID + guarantor), a company default, and a stop on credit to someone long overdue. A credit sale with no customer is flagged. |
| **Audit trail** | Voids, refunds, stock adjustments, price/cost changes, credit-limit changes, container costs and payments are written to the audit log with who did them. |
| **Shop alerts** | A feed of anything odd (HIGH ones are pushed to the owner's phone), plus a dashboard card with an all-clear. |
| **Daily summary** | Each evening: sales by payment type, voids/refunds, below-price sales, credit given, till balance, what customers owe. |
| **Stock counts** | Blind counts (counter cannot see system quantities), a second person approves, adjustments are `counted - expected-at-start` so sales made during the count are kept. Losses are valued at cost and ranked per counter. |
| **Containers / landed cost** | Goods priced in USD/CNY/AED, every cost on top (freight, duty, clearing...) spread across the goods, so each item has a true KES cost. Shared containers track each trader's goods, cost share, payments and balance. Receiving books stock at landed cost and warns when the price no longer covers it. |
| **Business news** | Headlines that can touch a trader (KRA/customs/tax, imports and bans, money, county/markets, fuel), scored by relevance, with the urgent ones pushed. Indicative USD/CNY/AED/EUR rates. |

## Rolling it out

1. **Migration** (additive, no drops): `20261023120000_accountability_stocktake_imports_news`.
   Run `npx prisma migrate deploy` in `backend/`.
2. **Permissions**: new keys exist only after `npx ts-node scripts/seed-permissions.ts`
   (idempotent; adds the new keys to the four system roles of every company).
   Users get the new permissions the next time they sign in.
3. **Cron** (already in `vercel.json`): `/api/cron/accountability-summaries` (hourly),
   `/api/cron/news-refresh` (every 30 min), `/api/cron/exchange-rates` (daily).
   On a long-running server the same jobs run via `@Cron`.
4. **No new environment variables.**
5. Ship the mobile build. Until staff update, their tills do not apply the rules
   locally, but the server still records anything that slips through.

### Who gets what (default roles)

| Role | New permissions |
|---|---|
| Cashier | `news.view`, `inventory.stocktake.view`, `inventory.stocktake.count` |
| Supervisor | + `inventory.stocktake.create`, `sales.price_override` |
| Manager | + `accountability.view`, `inventory.stocktake.approve`, `sales.credit_override`, `imports.*` |
| Admin (owner) | + `accountability.manage`, `news.manage` |

## How strictness works

Settings live in `tenant.settings.accountability` (no schema change) and are
edited in the app under **Shop Alerts > Rules** (`PUT /accountability/settings`).

* `priceGuard.mode` / `credit.mode`: `OFF`, `FLAG` (default: warn the cashier, record, tell the owner) or `BLOCK`.
* **BLOCK is enforced on the phone**, from rules cached by `GET /accountability/till-rules`,
  because a sale rung up with no signal reaches the server after it has already
  happened. The server never refuses a sale that carries an `offlineId` (it is
  flagged instead); it does refuse a live API sale it was asked to check.
* Overrides: `sales.price_override` (sell below cost/minimum), `sales.discount`
  (discount past the cashier limit), `sales.credit_override` (credit over the limit).

## Cost, and why it matters

`Product.costPrice` used to be written by nothing, so profit reports guessed
70% of the selling price and a below-cost check had nothing to compare to. It is
now kept as a **weighted average of what stock really cost**:

* supplier invoices (unit cost per line),
* batch receipts (cost per base unit),
* container receipts (landed cost).

A cost of zero or less is ignored (a free sample must not drag the average to 0).
Expect cost to fill in over a few restocks; the below-cost check works per product
as soon as that product has a cost or a minimum price.

## API

All under `/api/v1`, JWT required.

* `GET  /accountability/till-rules` (any user) - rules, this user's overrides, per-product floors
* `GET|PUT /accountability/settings`, `GET /accountability/alerts`, `POST /accountability/alerts/acknowledge`, `GET /accountability/summary?branchId=`
* `GET /customers/:id/credit`; `PATCH /customers/:id` accepts `creditLimit`, `idNumber`, `guarantorName`, `guarantorPhone`
* `POST|GET /stocktake`, `GET /stocktake/:id`, `POST /stocktake/:id/{counts,submit,approve,cancel}`, `GET /stocktake/:id/report`
* `GET|POST /imports`, `GET|PATCH /imports/:id`, `POST /imports/:id/{participants,items,costs,payments,receive}` (+ `DELETE` on each child)
* `GET /market/news`, `/market/news/digest`, `/market/news/sources`, `POST /market/news/refresh`; `GET /market/rates`

## News and rates: sources and terms

* Headlines come from publishers' own RSS feeds (Capital FM, The Standard, Kenyans.co.ke) and the
  Central Bank of Kenya. Only the headline, a ~280-character excerpt and the link back are stored.
  **Google News RSS is deliberately not used**: its terms limit it to personal, non-commercial readers.
* Check each publisher's terms for commercial use before relying on this in a paid product.
* A feed that fails 6 times in a row is reported unhealthy in `GET /market/news/sources`.
  (Nation's feed returned 404 when this was built, so it is not included.)
* Rates come from ExchangeRate-API's free endpoint (attribution is returned with the data).
  They are indicative mid-market rates, not what a bank or forex bureau will give.
* There is no KRA feed; the app links to KRA's public notices page instead.

## Known limits

* The phone caches the rules for 6 hours; a manager who changes them waits up to that long for tills that stay online all day.
* The mobile test runner in this environment cannot start (`flutter test` fails for the whole repo because the
  installed engine is older than its framework). The till-guard rules were verified on the plain Dart VM
  (18 cases) and mirror the server's, which has its own tests.
* M-Pesa statement matching and KRA eTIMS are not covered.
