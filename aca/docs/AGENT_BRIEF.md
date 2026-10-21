# ACA (Axon Counterbase Admin) — build brief for feature work

ACA is the staff-only Flutter app that runs Counterbase (the POS product by Arche Axon). It manages client
companies ("tenants"), their subscriptions and billing, the Counterbase support/security/finance **team**, and
platform security. Android only. Project root: `C:\Projects\POS\pos-system\aca` (Flutter 3.38 / Dart 3.10, Material 3).

## Hard rules (from the product owner — non-negotiable)

1. **No demo data, no mock data, no local/fake fallbacks, no hard-coded sample content. Ever.** Every number,
   name and list on screen comes from the live Counterbase API through `AcaRepository`. If data is missing,
   show a real empty state; if a call fails, show a real error state with retry.
2. **Never hard-code a server URL.** `AcaConfig` (lib/core/config.dart) is the only place that knows the server.
3. **Never invent endpoints or fields.** The contract is `lib/data/repository.dart` + `lib/data/models.dart`.
   The backend source is the authority: `C:\Projects\POS\pos-system\backend\src\platform-admin\` (controllers,
   services, DTOs) and `...\backend\src\license\` for licences.
4. **The server enforces permissions; the UI mirrors them.** Hide/disable actions the signed-in role cannot do,
   using `context.watch<SessionController>().can(Perm.x)` or the `Gate` widget. A 403 must still render
   gracefully (`ErrorState` does it).
5. Money is Kenyan shillings (`Fmt.kes`). Dates through `Fmt`. Never show raw IDs/UUIDs as primary text.
6. **Do not edit files outside your own feature folders** (see your task). Other people are editing the
   other folders at the same time. If you need a new repository method / model field / shared widget, DO NOT
   edit the shared file: implement it locally in your folder (e.g. a private helper, or an
   `extension on AcaRepository` that calls `repo.api.getMap/postMap/...`) and list it in your final report.
7. `write_file` on this machine sometimes truncates large files. After writing every file: `wc -l`, check the
   last lines, and run `flutter analyze`. Re-write if the tail is missing.

## What already exists (read these first, in this order)

- `lib/core/theme.dart` — `context.aca` palette (bg, surface, surfaceHigh, border, text, textMuted, textFaint,
  brand, success, warning, danger, info), `Tone` enum, `p.toneColor(t)`, `p.toneFill(t)`. **Never hard-code colours**
  (the one exception is the QR code, which must be black on white).
- `lib/core/widgets/widgets.dart` — `AcaCard`, `SectionHeader`, `StatTile`, `StatusPill`, `Avatar`,
  `KeyValueRow`, `EmptyState`, `ErrorState`, `Skeleton`, `ListSkeleton`, `LoadBuilder<T>` (skeleton → data/error,
  pull-to-refresh, `reload()`), `toast`, `runAction` (busy overlay + success/error toast around a mutation),
  `confirmAction` (bottom-sheet confirm), `promptText`, `Gate`, `StatusTone` (colour mapping for statuses/roles/severity).
- `lib/core/format.dart` — `Fmt.kes / kesCompact / date / dateTime / ago / daysUntil / initials / label / monthLabel`.
- `lib/core/permissions.dart` — `Perm.*` keys and `Roles.all`.
- `lib/data/models.dart` — typed models for every endpoint (`J` = safe JSON helpers, `Paged<T>`).
- `lib/data/repository.dart` — `AcaRepository`: one typed method per endpoint. Get it with
  `context.read<AcaRepository>()`. `repo.api` is the raw `AcaApi` if you really need it.
- `lib/data/api_client.dart` — `ApiException` (`status`, `message`, `code`, `isForbidden`, `isNetwork`, ...).
  Show `e.message` to the user; it is already human-readable.
- `lib/state/session.dart` — `SessionController`: `me`, `can(perm)`, `signOut()`, `reloadProfile()`, app-lock and
  privacy switches (`lockEnabled`, `deviceCanLock`, `hideContent`, `setLockEnabled`, `setHideContent`, `unlock`).
- `lib/features/shell/` — bottom-nav shell and the "More" tab. `lib/features/auth/` — sign-in, forced password change, lock.
- Placeholder files exist for every screen below with the **exact class names and constructor signatures that other
  screens already import**. Keep those signatures; you may add optional parameters.

Placeholders you must keep compatible:
`OverviewScreen()`, `TenantsScreen({initialStatus})`, `TenantDetailScreen({required tenantId, tenantName})`,
`BillingScreen()`, `SecurityScreen()`, `AuditScreen({tenantId, actorId, title})`, `TeamScreen()`,
`StaffDetailScreen({required staffId, name})`, `AccountScreen()`.

Tab screens (`OverviewScreen`, `TenantsScreen`, `BillingScreen`, `SecurityScreen`) are shown inside the shell's
bottom navigation **and** may also be pushed as a normal route; each returns its own `Scaffold` + `AppBar`.

## Packages already in pubspec

`provider`, `http`, `intl`, `fl_chart` (charts), `qr_flutter` (QR), `url_launcher` (tel:/mailto:),
`flutter_secure_storage`, `local_auth`, `shared_preferences`, `package_info_plus`, `device_info_plus`.
Do not add packages; if you believe one is essential, say so in your report instead.

## Quality bar

- Feels like a polished operations console: calm dark-first surfaces, clear hierarchy, generous touch targets
  (min 44dp), consistent 16dp page padding, 12–16dp radii (use `AcaCard`).
- Every list: skeleton while loading, empty state with an explanation, error state with retry, pull-to-refresh.
- Every mutation: `confirmAction` for anything destructive/irreversible, `runAction` for the call, reload after
  success, toast result. Reasons/notes via `promptText`.
- Must not overflow at 360dp wide or with system font scale 1.3: use `Expanded`/`Flexible`, `maxLines` +
  `TextOverflow.ellipsis`, `Wrap` for pill rows.
- Bottom sheets with text fields must be keyboard-safe (`isScrollControlled: true`, `viewInsets.bottom` padding).
- No `print`, no TODOs, no placeholder text, no dead buttons. Everything you render must work.
- `flutter analyze` must report **no errors and no warnings in your files** (infos about style are fine but
  prefer to fix them). Other folders may be mid-edit by other people; ignore their diagnostics.
- Add focused unit tests (`test/<feature>_test.dart`) for any pure logic you write (filters, rule helpers,
  formatting of domain values). Run them with `flutter test test/<file>`. Don't write widget tests that need a network.

## Seeing real response shapes

A QA copy of the backend with throwaway fixture data runs at `http://localhost:3100/api/v1/platform-admin`
(sign in: `POST /auth/login` `{"email":"qa-owner@aca.test","password":"QaOwner-Passw0rd!x"}`; logins are
rate-limited to 10/min). Use `curl` to inspect JSON if a model is unclear. That server is for *your inspection
only* — the app itself never mentions it.

## Final report (what I need back)

A short list: files created, anything you had to add locally that probably belongs in shared code,
anything in the shared files that looked wrong/insufficient, and anything you could not finish.
