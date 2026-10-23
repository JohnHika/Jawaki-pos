# ACA — Axon Counterbase Admin

ACA is the staff app that runs Counterbase from the owner's side: client companies, subscriptions and billing,
the Counterbase team (roles and access), and platform security. Android only.

- App: `aca/` (Flutter). Package `com.archeaxon.aca`, launcher name **ACA**.
- API: the existing Counterbase backend (`backend/src/platform-admin/`), version-1 routes under
  `/api/v1/platform-admin/*`. ACA has **no demo mode and no local data**: its one data source is the live
  server the Counterbase POS app also uses, `https://api.archeaxon.com/api/v1`.

## Roles

| Role     | Can do |
|----------|--------|
| OWNER    | Everything, including the team and other owners. At least one active owner must always exist. |
| ADMIN    | Everything operational; manages staff **below** admin (security, finance, support, viewer). |
| SECURITY | Security centre, full audit log, lock/unlock staff, sign users out, lock a company out, suspend. |
| FINANCE  | Invoices, mark paid, goodwill credits, claims. |
| SUPPORT  | Extend subscriptions, notes, see company staff and devices. |
| VIEWER   | Read-only: overview, clients, billing. |

The matrix lives in `backend/src/platform-admin/rbac/platform-permissions.ts` and is enforced server-side on
every route (routes without an annotation are denied). The app only mirrors it to hide actions.

## Security model

- Sign-in: email + password (+ authenticator code or one-time backup code when two-step is on).
  5 failed attempts lock the account for 15 minutes. Locked/disabled/unknown accounts get the same generic error.
- Sessions: 15-minute access token + rotating 14-day refresh token (stored hashed). Replaying a retired refresh
  token revokes the whole session and raises a CRITICAL alert. Disabling a staff member, changing their role, or
  revoking a session takes effect on the very next request.
- New staff get a one-time temporary password and must set their own (12+ chars, upper/lower/number/symbol)
  before anything else works.
- Everything is attributed in the `platform_audit_logs` table: who, what, when, from which IP/device.
- On the phone: Android keystore for tokens, optional biometric/screen-lock app lock (re-locks after 20 s in the
  background), and screenshots/recent-apps hidden (both switchable in Account).

## Deploying the backend part

The platform-staff features need migration `20261021161501_platform_staff_rbac_security` (additive: new columns on
`platform_admins`, new tables `platform_admin_sessions`, `platform_audit_logs`, `platform_tenant_notes`).
The Vercel backend build runs `prisma migrate deploy`. Existing platform admin rows become `OWNER`.

Optional Vercel backend env var: `PLATFORM_2FA_KEY` (secret used to seal staff authenticator secrets; falls back to
`JWT_REFRESH_SECRET`). **If you rotate whatever key is in use, staff must re-enrol two-step sign-in.**

## Building

```bash
cd aca
# JDK 17 and an Android SDK are required. On this machine:
export JAVA_HOME="C:\\Android\\jdk\\jdk-17.0.18+8" ANDROID_HOME="C:\\Android"
export GRADLE_OPTS="-Dorg.gradle.java.home=C:/Android/jdk/jdk-17.0.18+8"   # ~/.gradle/gradle.properties points at a JDK Gradle can't probe
flutter build apk --release          # production: signed, live server only
flutter build apk --debug --dart-define=ACA_API_BASE_URL=http://localhost:3100/api/v1   # QA build (id ...aca.qa)
```

Release signing key: `C:\Users\admin\.aca\aca-release.jks` with passwords in `C:\Users\admin\.aca\key.properties`
(outside the repo; override the path with `ACA_KEY_PROPERTIES`). **Back this folder up — if it is lost, installed
copies can only be replaced by uninstalling first.** A release build refuses to start if it was somehow built
against anything but production, and `flutter build apk --debug` builds get a separate `.qa` application id so
they can never overwrite the real app.

## Tests

- Backend: `cd backend && npm test -- src/platform-admin` (73 tests: RBAC, TOTP, login lockout, refresh-token
  replay, team rules, guard).
- App contract: `flutter test --dart-define=ACA_API_BASE_URL=<QA server> test/live_contract_test.dart` runs the real
  repository/models against a QA backend (skipped automatically against production).
