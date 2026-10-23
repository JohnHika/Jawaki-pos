# Merchant product payments

Counterbase activation and monthly subscriptions continue to use the platform
Paystack account. Merchant product sales use a separate Paystack subaccount for
each workspace. The owner connects a Kenyan business bank account during the
"Set up payments" onboarding step or later in Settings > Money & plan. Paystack
creates the subaccount; Counterbase retains its code, bank name, resolved name
when supplied, and account number's last four digits. The complete account
number is sent only to Paystack for setup and is not stored locally.

The bank picker is populated from Paystack's Kenya/KES bank catalogue, across
all API pages. It includes active `kepss` bank-account entries and excludes
mobile-money channels such as M-Pesa and Airtel.

For an M-Pesa sale, the backend validates branch, cart, stock, and amount,
creates a durable intent with a client request ID, and asks Paystack to charge
with the merchant subaccount and merchant-paid fees. The app never creates a
paid receipt from a mobile prompt alone. The backend verifies the exact
reference, KES amount, successful status, and settlement subaccount before
creating the sale and payment record. Webhooks and the status route can both
finish the same intent. A paid charge that cannot produce a receipt remains
`NEEDS_REVIEW` and appears in the Payments screen for reconciliation.

This first merchant checkout supports **one M-Pesa payment for one sale**.
Cash and debt can still be split; mixed M-Pesa tenders are disabled until each
tender has a verified merchant settlement path. Paystack's Charge API requires
an email, so Counterbase sends `PAYSTACK_PAYER_EMAIL` (default
`billing@archeaxon.com`) and does not ask the payer for an email. Paystack
transactions and any provider email notices use that billing address. Paystack
settles the merchant share on its provider schedule; checkout confirmation is
not instant bank settlement. Subaccount availability and bank acceptance
depend on the Paystack integration.

## Deployment order

1. Apply `prisma/migrations/20261022130000_merchant_payouts` to the isolated
   Neon staging database through its authorized direct connection or SQL editor.
2. Deploy the backend to `counterbase-pos-staging-api` with the Paystack **test**
   key. Confirm the webhook points to staging.
3. Build a staging mobile app against that API. Connect a disposable merchant
   test bank account accepted by Paystack and complete a test M-Pesa charge.
   Check that the verified subaccount matches the merchant, the sale and one
   payment record appear, and a repeated client request ID does not prompt
   a second charge.
4. Review Paystack's live subaccount eligibility and settlement terms for the
   integration before applying the migration and deploying to production.
   A live customer charge should be attempted only after the merchant payout
   destination has been confirmed.

Never paste or log Paystack secret keys, full bank account numbers, or customer
payment credentials. Merchant bank setup asks for no password, PIN, or OTP.
