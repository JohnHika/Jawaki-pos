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
- `PAYSTACK_SECRET_KEY` and `PAYSTACK_PUBLIC_KEY` — Paystack **test** keys.
- `PUBLIC_API_URL` — `https://counterbase-pos-staging-api.vercel.app`.
  The activation and monthly checkout return URLs are derived from it.

Email OTP delivery also needs one working provider. The app supports `EMAIL_*`
SMTP settings or `ZEPTOMAIL_SEND_API_KEY` plus optional `ZEPTOMAIL_API_URL`.
The latter requires a verified sending domain and an agent-specific API key.

Firebase push, Cloudinary uploads, AI, Redis, and Jenga/M-Pesa settings are
optional for the first Paystack checkout validation. Add their staging values
before validating those features.

## Database migration

All 36 Prisma migrations were applied to the isolated Neon staging database on
2026-10-22 using its direct connection URL (`DATABASE_URL_UNPOOLED`). Keep the
pooled `DATABASE_URL` for runtime traffic. For future schema changes, supply the
direct URL as `DATABASE_URL` to `prisma migrate deploy`; do not point migrations
at the Render production database.

## Payment test callback

Configure Paystack's **Test** webhook URL as:

```text
https://counterbase-pos-staging-api.vercel.app/api/v1/billing/paystack/webhook
```

That endpoint handles both one-time activation and monthly invoice events.
The callback pages for activation and monthly checkout are derived from
`PUBLIC_API_URL`.

## Current status

- The staging API is deployed and its `/health` and `/health/db` endpoints
  return `200`; Neon reports `connected`.
- Add Paystack test keys and a staging email provider before testing account
  verification and one-time or monthly checkout. Never put live Paystack keys
  in this project.

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
