# Counterbase Vercel staging API

The Vercel project `counterbase-pos-staging-api` is isolated from the Render
production service. Its root directory is `backend`; it runs the NestJS app on
Node 22 in Frankfurt (`fra1`), next to the planned Neon staging database.

## Secrets and environment

Add values in the Vercel project's **Production** environment only. This Vercel
project is the staging environment, so its `Production` target is still staging.
Keep the Render production values and Paystack live key out of this project.

Required before deploying the API:

- `DATABASE_URL` — supplied by the Neon integration after the account owner
  accepts its marketplace terms.
- `NODE_ENV=production`
- `JWT_SECRET`, `JWT_REFRESH_SECRET`, and `OTP_PEPPER` — unique random staging
  values, separate from Render.
- `CRON_SECRET` — a long random value used to authorize scheduled task routes.
- `PAYSTACK_SECRET_KEY` — Paystack **test** key. The current backend-hosted
  checkout does not use `PAYSTACK_PUBLIC_KEY`.
- `PAYSTACK_PAYER_EMAIL` — optional email attached to merchant M-Pesa charges;
  defaults to `billing@archeaxon.com`. Customer checkout asks only for the
  payer's phone number.
- `PUBLIC_API_URL` — `https://counterbase-pos-staging-api.vercel.app`.
  The activation and monthly checkout return URLs are derived from it.

Email OTP delivery also needs one working provider. The app supports `EMAIL_*`
SMTP settings or `ZEPTOMAIL_SEND_API_KEY` plus optional `ZEPTOMAIL_API_URL`.
The latter requires a verified sending domain and an agent-specific API key.

Firebase push, Cloudinary uploads, AI, Redis, and Jenga/M-Pesa settings are
optional for the first Paystack checkout validation. Add their staging values
before validating those features.

## Database migration

The existing Prisma migrations are applied to the isolated Neon staging
database using its direct connection URL (`DATABASE_URL_UNPOOLED`). Keep the
pooled `DATABASE_URL` for runtime traffic. The merchant-charge payer-email
column rename must be applied with `prisma migrate deploy`; do not point
migrations at the Render production database.

The `20261022130000_merchant_payouts` and
`20261022140000_policy_acceptances` migrations are applied. The staging API now
includes merchant payout setup, merchant M-Pesa charge routes, policy
acceptance records, and explicit Auto-Renew authorization checks.

## Payment test callback

Configure Paystack's **Test** webhook URL as:

```text
https://counterbase-pos-staging-api.vercel.app/api/v1/billing/paystack/webhook
```

The staging endpoint handles one-time activation, monthly invoice, and merchant
product M-Pesa charge events. Use Paystack **Test** mode only for any checkout
validation; no payment transactions were run during the policy deployment.
The callback pages for activation and monthly checkout are derived from
`PUBLIC_API_URL`.

## Current status

- The staging API is deployed and its `/health` and `/health/db` endpoints
  return `200`; Neon reports `connected`.
- Vercel has a `PAYSTACK_SECRET_KEY` variable and the staging email settings;
  verify that the key is a test key (`sk_test_`) before charging in staging.
  Never put live Paystack keys in this project.
- Merchant-payment and policy-acceptance migrations are applied to Neon staging;
  the API deployment is ready and the health and database-health endpoints
  return `200`.

## Scheduled tasks

Vercel Cron invokes the same five schedules used by the existing backend. The
routes require `Authorization: Bearer $CRON_SECRET` and store a unique UTC slot
in `scheduled_task_runs` so duplicate deliveries cannot repeat a billing run.
The half-hour reminder uses Vercel Pro's supported schedule interval.

## Current platform limit

Vercel Functions reject request or response bodies above 4.5 MB. The existing
Express parser accepts 12 MB for inline base64 photos, so large receipt/product
images must stay under Vercel's platform limit or be uploaded directly to
Cloudinary. The regular Paystack checkout/webhook payloads fit comfortably.
