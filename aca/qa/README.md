# ACA QA harness (throwaway data only)

Everything here runs against a **throwaway local Postgres** with obviously fake fixture companies. The
scripts refuse to run unless `DATABASE_URL` points at localhost. ACA itself never uses any of this data:
the shipped app talks only to the live Counterbase API.

1. `node start-local-postgres.mjs` (after `npm i embedded-postgres` in a scratch dir) - Postgres on :54329
2. In `backend/`: `DATABASE_URL=postgresql://aca:aca_local_only@localhost:54329/aca_dev npx prisma migrate deploy && npm run build`
3. `DATABASE_URL=... node seed-fixtures.js` - 3 fixture companies, users, a device, invoices, a claim
4. Start the API from an EMPTY working directory so it cannot read backend/.env (production secrets):
   `env -i ... DATABASE_URL=... JWT_SECRET=qa-only... PLATFORM_ADMIN_EMAIL=qa-owner@aca.test PLATFORM_ADMIN_PASSWORD='QaOwner-Passw0rd!x' PORT=3100 node ../backend/dist/src/main.js`
5. `python e2e.py` - 85 checks over HTTP (RBAC, lockout, 2FA, refresh replay, audit). The API rate-limits logins to
   10/min; the script waits it out, so a full run takes several minutes.
6. `node reset-qa.js` wipes QA staff/audit state between runs.
7. `adb reverse tcp:3100 tcp:3100` then install the debug (`.qa`) build to look at the real screens.

`make_icons.py` regenerates the launcher icons from the brand mark.
