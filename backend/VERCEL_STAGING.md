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
- `PUBLIC_API_URL` — the assigned Vercel API URL after the first deployment.
  The activation and monthly checkout return URLs are derived from it.

Email OTP delivery also needs one working provider. The app supports `EMAIL_*`
SMTP settings or `ZEPTOMAIL_SEND_API_KEY` plus optional `ZEPTOMAIL_API_URL`.
The latter requires a verified sending domain and an agent-specific API key.

Firebase push, Cloudinary uploads, AI, Redis, and Jenga/M-Pesa settings are
optional for the first Paystack checkout validation. Add their staging values
before validating those features.

## Database migration

After Neon has been connected and `DATABASE_URL` is available, run from this
directory:

```powershell
vercel env run -e production -- npx prisma migrate deploy
```

This applies the repository's migrations to the isolated staging database. Do
not point this command at the Render production database.

## Payment test callback

Once the Vercel URL is assigned, configure Paystack's **Test** webhook URL as:

```text
https://<vercel-staging-api>/api/v1/billing/paystack/webhook
```

That endpoint handles both one-time activation and monthly invoice events.
The callback pages for activation and monthly checkout are derived from
`PUBLIC_API_URL`.

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
