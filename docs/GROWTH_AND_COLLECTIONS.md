# Growth and collections: coupons, referrals, debt statements, M-Pesa matching, price list

Built for the same market as [SHOP_CONTROL.md](SHOP_CONTROL.md): traders who sell a lot on credit,
chase customers on WhatsApp, and win new shops by word of mouth. Everything here is **additive**.

## What it does

| Feature | For the shop | For you |
|---|---|---|
| **Coupons** | Discount codes (percent or KES, minimum spend, expiry, usage limits, per product or customer). The till takes the discount off, offline too, and records it against the cashier. | Reason to sign up: coupons are a controlled way to give discounts. |
| **Promo codes** (platform) | n/a | Codes that give a company free subscription days. Created by platform staff. |
| **Referrals** | Each shop has a code. A shop that signs up with it gets 14 extra days when it activates, the referrer gets 30 free days. | Growth through traders who already trust each other. |
| **Debt statement link** | Send a customer or peer shop a link (WhatsApp) that opens a page with what they owe, a PDF, and buttons "I have paid" / "I will pay on". Opened/not-opened is visible. | Every statement carries the shop's referral code and an app download button. |
| **M-Pesa matching** | Paste M-Pesa messages or a statement; each payment is matched to who owes it, one tap to record. A code can only settle one payment. | |
| **Price list** | One tap sends today's prices (with wholesale tiers) as WhatsApp text or PDF. | |
| **Daily summary** | Now also shows coupons used, replies waiting, supplier bills overdue or due this week. | |

## Rolling it out

1. **Migration** (additive, no drops): `20261024100000_coupons_referrals_statements`. `npx prisma migrate deploy` in `backend/`.
2. **Permissions**: `npx ts-node scripts/seed-permissions.ts`, then everyone signs in again.
3. **Environment** (all optional): `PUBLIC_API_URL` (or `API_PUBLIC_URL`) so statement links are full addresses;
   `REFERRAL_REFERRED_DAYS` / `REFERRAL_REFERRER_DAYS` to change 14 / 30; `APP_DOWNLOAD_URL` to add a store link to the share text.
4. Ship the mobile build. Until staff update, tills cannot enter coupon codes (the server still accepts and records one).

| Role | New permissions |
|---|---|
| Supervisor and above | `statements.share` |
| Manager | + `coupons.view`, `coupons.manage`, `statements.manage`, `mpesa.reconcile` |
| Admin | + `referrals.view` |

## How coupons behave

* The phone caches the shop's coupons (30 min) and applies a code with no signal. The sale carries `couponCode`
  and the discount; the server re-checks on sync.
* A coupon is an approved discount: it does **not** count against the cashier's own discount limit, but its
  money comes off the items it applies to, so a coupon that pushes a price below cost is still flagged.
* The server **never refuses a sale that already happened** (offline sale, or M-Pesa already paid). A coupon
  that does not check out (expired, used up, wrong customer, unknown) is flagged to the owner as
  `COUPON_REJECTED`, and one used past its limit as `COUPON_OVERUSE`.
* Per-customer limits cannot be checked offline; the server enforces them when the sale syncs.
* Voiding a sale gives the coupon use back.
* Report: `GET /coupons/report` (uses and KES given away, by code and by cashier).
* Not in the app yet: locking a coupon to one customer or to chosen products (the API supports both).

## Referrals and promo codes

* Both only ever add **free days** (`currentPeriodEnd` pushed forward), never touch invoices or prices.
* Referral reward is paid exactly once, when the referred company's KES 35,000 activation payment lands.
* A promo code entered before activation waits and lands when the company activates (activation starts a fresh
  trial that would otherwise overwrite it). One promo code per company, ever.
* A repeat confirmation of the same activation payment (webhook plus the app) no longer restarts the trial.
* Platform staff manage promo codes at `GET/POST /platform-admin/promo-codes`, `POST .../:id/active`
  (permission `billing.manage`). There is **no screen for this in the staff app (`aca`) yet**.

## Debt statement link

* `POST /statements/links` makes an unguessable link (default 14 days, revocable) at `https://<server>/s/<token>`.
  The page is served by the API itself and needs no sign-in or app. English and Kiswahili (`?lang=sw`).
* The page shows live data: a payment recorded in the app disappears from the page.
* "I have paid" asks for the M-Pesa code and amount; "I will pay on" asks for a date. Both land in
  **Debt Replies**; confirming a payment records it through the normal finance code (oldest debt first) and
  burns the M-Pesa code.
* Link previews (WhatsApp, Telegram) and the owner's own PDF download are **not** counted as "opened".
* Payment instructions ("Paybill 123456, account...") are set once under Send statement; they are stored in
  `tenant.settings.statements`.
* The page shows only that one debtor's own debts and the sending shop's name and phone. It never shows other customers, and nothing here lists who owes whom across shops.
* Throttles are generous because the API does not trust the proxy's forwarded address, so behind Vercel every
  visitor can look like one IP. The real protection is the long token and the cap of 10 open replies per link.

## M-Pesa matching

* Reads the "you have received" SMS wording for a personal number, a till and a paybill, and an M-Pesa
  statement CSV. Money sent or paid out is ignored. Repeats are dropped.
* Match signals: the code a customer sent from a statement link (strongest), the sender's phone (masked numbers
  like `0722***456` match), the sender's name, and the amount. Only a HIGH match is pre-ticked.
* Each M-Pesa code is stored once per company (`mpesa_entries`), so the same payment can never clear two debts.

## Known limits

* No eTIMS (KRA) integration: it needs the taxpayer's own KRA credentials and device certification.
* No Swahili in the app itself. The customer-facing statement page, PDF and WhatsApp text are bilingual; the app
  has no localisation system yet, so translating its screens is a separate piece of work. The Swahili text
  should be reviewed by a native speaker.
* The staff app has no promo-code screen; use the API.
* Statement links need internet on the sending phone (they are made by the server).
* The daily summary text now carries more lines; very long summaries may be cut by some phones' notification shade.
