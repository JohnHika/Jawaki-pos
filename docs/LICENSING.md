# Software licensing and gatekeeping

Controls which modules a company can use, how many branches and staff it can
have, and for how long. **Off by default.** Deploying this changes nothing for
any existing client until you switch a company to `enforce`.

## What is gated

| Module key        | What it unlocks                                                        | Gated routes (server) |
|-------------------|------------------------------------------------------------------------|-----------------------|
| `analytics`       | Trends, top products, category / cashier / payment breakdowns          | `GET /reports/sales/trend`, `products/top`, `categories`, `cashiers`, `payments`, `branches`, `inventory/movements`, `profit-loss` |
| `customReports`   | Custom report builder and exports                                      | `POST /reports/export`, `POST /reports/chart` |
| `aiAssistant`     | Plan flag for the AI assistant (the AI add-on keeps its own billing)   | not yet enforced on AI routes |
| `multiCurrency`   | Multi-currency                                                         | flag only |
| `prioritySupport` | Priority support                                                       | flag only |

Always open on every plan, so a client is never locked out of the shop itself:
sales, inventory, customers, expenses, the dashboard, the daily summary, the
daily profit card, End of Day, Cash Flow, and **reading** historical data.

Seat limits: a new branch (`POST /branches`) or a new staff invitation is
refused with `402 LICENSE_LIMIT_REACHED` when the plan's allowance is used up.

An enforced licence that has **expired** also stops new records (sales,
expenses, supplier invoices) exactly like an unpaid subscription, while
viewing stays open.

## Plans (price list in `subscription.service.ts`)

| Plan       | Branches | Users | analytics | customReports | aiAssistant | multiCurrency |
|------------|---------:|------:|:---------:|:-------------:|:-----------:|:-------------:|
| TRIAL      | 1        | 3     |           |               |             |               |
| CORE       | 3        | 10    | yes       |               |             |               |
| BUSINESS   | 10       | 50    | yes       | yes           | yes         |               |
| ENTERPRISE | unlimited| unlimited | yes   | yes           | yes         | yes           |

A company whose plan name is **not** in this table (a legacy row such as
`PRO`) is never locked by guesswork: all modules stay open and its seat limits
come from its own `maxBranches` / `maxUsers` columns. The dry run flags these
as `unknownPlan`.

> Note: the activation flow currently sets `plan = TRIAL` after the setup fee
> is paid. Moving a client onto CORE/BUSINESS before enforcing is part of the
> rollout below.

## Modes

* `off` – nothing is gated; the licence is only reported. **Default.**
* `warn` – nothing is gated, but each would-be block is written to the server log
  (`[licence/warn] ...`) so you can see the impact before enforcing.
* `enforce` – unlicensed modules, limits and expired licences are refused (402).

Platform-wide default: env `LICENSE_ENFORCEMENT` (`off` | `warn` | `enforce`).
A company's own setting always wins. Leave the env var unset.

## Operating it (platform admin API)

Log in as a platform admin (`POST /api/v1/platform-admin/auth/login`) and use the
bearer token.

```bash
# 1. DRY RUN - what would switching everyone to enforce lock today?
GET  /api/v1/platform-admin/licenses/preview

# 2. Inspect one company
GET  /api/v1/platform-admin/tenants/:id/license

# 3. Turn gating on for one company that has not paid for a module
PUT  /api/v1/platform-admin/tenants/:id/license
{ "enforcement": "enforce",
  "note": "Setup fee outstanding since 12 Oct" }

# Grant or revoke a single module regardless of plan (null clears the override)
{ "overrides": { "analytics": false, "customReports": true } }

# Hard stop for a licence not tied to a subscription period
{ "validUntil": "2027-01-01T00:00:00Z" }        # null removes it

# Explicit seat limits (beat the plan)
{ "maxBranches": 2, "maxUsers": 8 }

# Issue a new licence key (a key is created automatically on first save)
{ "reissueKey": true }
```

Every change is written to the audit log as `PLATFORM_ADMIN_LICENSE_UPDATED`.

## Suggested rollout

1. Deploy (nothing changes). Run the dry run and read the list.
2. Fix any company that would be unfairly locked (move it to the right plan, or
   add an override / explicit limits).
3. Put one friendly company in `warn` for a few days; check the log.
4. Put the client that has not paid into `enforce`.
5. Only then consider `LICENSE_ENFORCEMENT=enforce` as the platform default.

## What the client sees

* A locked module shows "<Module> isn't included in your plan" with **See plans**.
* **Plan & Billing -> Your licence** lists what is included, the seat limits and
  the licence key.
* The server is the real gate; the app only mirrors it. The last known licence is
  kept on the device so locks stay consistent offline.

## Where it lives

* Rules: `backend/src/license/license.catalog.ts` (pure, fully unit-tested)
* Service, guard, `/license` endpoint: `backend/src/license/`
* App: `mobile/lib/features/billing/` (`ClientLicense`, `FeatureGate`,
  `ensureFeature`)
