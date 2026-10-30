# Handoff: Arche Axon POS ("Axon POS")

Written 2026-10-17 for ChatGPT (or any engineer) taking over. Everything here comes from the working session; where something is unverified it says so. No secrets are in this file. Never put keys, passwords or tokens in it.

## 1. What this is

A point-of-sale and small-business system for Kenyan shops (inventory, customers and credit, finance, team and access, AI helper, offline-first sales).

- **Company:** Arche Axon. The app is currently called "Axon POS". The owner asked whether to rename it to just **Axon** ("a product of Arche Axon"). Recommended, **not done yet** (waiting on the owner's one-word confirmation).
- **Repo:** `C:\Projects\POS\pos-system` (GitHub `JohnHika/Jawaki-pos`, branch `main`).
  - `mobile/` Flutter app (Riverpod, go_router, Dio, get_it, drift/SQLite).
  - `backend/` NestJS + Prisma + Postgres, deployed on Render at `https://arche-axon-pos-api.onrender.com` (API prefix `/api/v1`).
  - `docs/` includes `LICENSING.md`.
- The Claude session cwd was `C:\Projects\pos` (NOT a git repo). Always `cd` into `pos-system` for git.

## 2. Release pipeline (important)

- A push to `main` triggers a Render backend deploy and the GitHub workflow **"Build and Publish Android Update"** (about 10 minutes): builds the APK, uploads to Cloudflare R2 (`android/latest.json` manifest) and creates a GitHub Release.
- **In-app "Recent changes" text** is generated from conventional-commit subjects over the pushed range (`feat:` becomes "Adds", `fix:` becomes "Fixes"). If a CI run fails, those commits fall outside the next push's range, so put the user-facing change in the last pushed commit, or push once after tests pass. A published manifest cannot be edited.
- Bump `mobile/pubspec.yaml` `version:` every release (current **1.0.71+2114**). The manifest's `latestVersion` is an internal always-increasing compatibility number (e.g. 1.0.109); the visible version comes from the release name ("Axon POS 1.0.71"). Do not show `latestVersion` to users.
- The app signs the user out after each update (by design, shows a "What's new" screen then "Continue to sign in").
- Package id: `com.archeaxon.axonpos` (debug variant `.debug`). Signing certificate still says "Arche Axon Intelligence" and cannot change without breaking updates.

## 3. Rules of engagement learned the hard way

- Stage **explicit paths only**; check `git diff --cached --name-only`. The repo root has lots of untracked noise (`.claude/worktrees/`, `.hermes/`, `emu_*.png`, PDFs). Never `git add -A`.
- Commit trailer used: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (match whatever the new tool requires).
- Before pushing: `flutter analyze` (must be clean) and `flutter test` (388 passing at last run). Backend: `npx jest src/sync` (4 passing).
- **CI-only Flutter assert:** "ListTile background color or ink splashes may be invisible". Any decorated panel (background colour) that contains a `ListTile`, `SwitchListTile` or `ExpansionTile` must be a `Material`, not `Container(decoration: ...)`. Local `flutter test` does not catch it; CI does. It broke 1.0.62 and 1.0.63.
- flutter_test uses the very wide Ahem font, so narrow-width overflow tests can give false positives. Confirm layout on a device/emulator.
- Windows quirks: heredocs with apostrophes/backslashes/backticks break in the shell tool; write patch scripts to files and run them. Files are CRLF; patch scripts preserve line endings.
- Never read or commit: `node_modules`, `build`, `.dart_tool`, `*.g.dart` (generated), `.env*`, keystores, APKs.

## 4. Shared UI kit (mobile)

`mobile/lib/core/widgets/form_kit.dart`: `kitFieldDecoration`, `kitNumber`, `kitCount`, `QuickAddChips`, `kitAddToField`, `ChoicePill`, `FormLabel`, `PinnedActionBar`. Redesigned with it (owner called the old versions "not pleasing"):

- Add Customer (`features/customers/.../add_customer_sheet.dart`): name, phone (digits, min 9), optional location, "Add a note", credit switch with amount and due-date shortcuts, pinned Save.
- Receive Stock (`features/inventory/.../batch_receive_screen.dart`): on-hand stock, quantity chips, unit dropdown, "Add another batch", summary row, pinned action bar.
- Request Stock (`.../stock_request_screen.dart`): product card with on-hand, quantity and chips, priority pills, quick reasons, photo, pinned Send.
- Add/Edit Product sheet is Expanded + pinned Save; do not wrap it in a scroll view. `AppBackButton` centres itself and needs a fixed-size slot.

## 5. Work done in the latest session (all pushed; release 1.0.71)

1. Real-phone update flow verified end to end (prompt, 52.9 MB download, Play Protect scan, install, What's new).
2. **Update screens fixed:** removed the leaking internal version ("1.0.109") via `releaseVersionFrom(releaseName)`; release date now persists across the install (`pending_update_notice_published_at`).
3. Start screen now shows the orange app icon (`assets/images/axon_app_icon_512.png`) instead of the old hexagon.
4. "Arche Axon Intelligence" becomes "Arche Axon" in Settings and code comments.
5. **Important bug fixed:** on a fresh install the `local_stock` table lacked the `UNIQUE(product_id, branch_id)` rule (only added by the v12 upgrade migration), so every stock save (`upsertAuthoritativeStock`, `incrementLocalStock`) threw and Receive Stock showed "Could not receive stock" even though the server accepted it. Fix: `_ensureLocalStockUniqueKey()` runs in `beforeOpen` (dedupes keeping newest row, then creates `ux_local_stock_product_branch`). Test: `test/database_fresh_install_stock_test.dart`. Verified on a real phone.
6. Backend sync: `CUSTOMER_CREATED` is now idempotent (existing id in tenant returns success). Spec added. The cause of one HTTP 500 on the very first customer push was **not identified** (server console was not captured); retries were the visible problem.
7. Login: explicit focus order (company code, then email, then password) with `FocusNode`s and `scrollPadding`. Tested in code, **not yet seen on the phone**.
8. Also earlier in the session: invite staff defaults to Cashier, Team/Invitations/Settings/Finance/Inventory/Products/Trade Partners reviews, release-note comma fix, and more (see git log).

## 6. Verified vs not verified

Verified on a real Samsung SM-S938B (Android 17) with the real keyboard: update flow, sign-in screens (back button clear of the form), Dashboard, Customers list, Add Customer (saved), Inventory, Receive Stock (after fix).
Verified on emulator and by tests: Add Product, Invite Staff, Team, Invitations, Settings (Opening hours, Tax, Branches), Report a Bug, Adjust Profit, Finance, Products, small-phone (720x1280, 130% text) sign-in, Trade Partners, Invoice Review via manual entry.

**Not verified:**
- Request Stock on the real phone.
- Sign-in keyboard Next order on the real phone.
- Invoice Review with scanned lines (needs a live AI key and a real receipt).
- The new/"living" app icon on clients' launchers.
- Push notifications (Firebase not configured on Render).

## 7. Open items and who owns them

| # | Item | Owner | Notes |
|---|------|-------|-------|
| 1 | Firebase env vars on Render: `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` | Owner | App ships `google-services.json` for project **`axon-pos-prod`**, package `com.archeaxon.axonpos`. Service-account key from Firebase console, Project settings, Service accounts. The project may belong to a different Google account than the one signed in. Paste `private_key` whole with its `\n` characters, no surrounding quotes (backend converts `\n`). Success = startup log no longer says "Firebase Admin credentials not configured". Never paste the key into chat or git. |
| 2 | App rename to "Axon" | Owner decides | Display name only is cheap; package id stays. Appears on clients' launchers. |
| 3 | Real-phone checks (Request Stock, login keyboard order) | Owner + device | Keep Axon open and unlocked. A Truecaller overlay (personal SMS) once covered the app; do not tap or read other apps. |
| 4 | Invoice Review with a real scan | Owner | Needs live AI key and a real receipt. |
| 5 | Cloudflare key for voice calling | Owner | Cloudflare Realtime TURN was chosen; calling is not built. |
| 6 | Licence enforcement | Owner | Needs the unpaid client's name. Then dry-run `GET /api/v1/platform-admin/licenses/preview`, then `PUT /tenants/:id/license {enforcement:'enforce', note}` for that company only. Note: the activation flow sets plan=TRIAL after the setup fee, so use the dry run first. |

Decisions already made on the owner's behalf: licence enforcement stays **off** by default (modes off|warn|enforce, settings-JSON based, server gate with 402 codes; see `docs/LICENSING.md`), AI is ungated, Cloudflare TURN for voice.

## 8. Known gaps and risks

- Offline sales synced before 1.0.56 keep `RCP-` receipt numbers.
- The platform admin has no web UI.
- In-app release notes for builds 2105-2111 list only the last fix commit (failed CI pushes).
- Team & Access once showed a blank list for several seconds on the emulator (cause unknown).
- Dashboard/Customers headers still show the hexagon mark when a tenant has no logo; the AI tab uses the hexagon deliberately. Consider whether the header fallback should match the orange icon.
- `release_notes_test.dart` previously had two test groups (`main2`) that never ran; they are now invoked from `main()`.

## 9. Local test setup

- Demo tenant: company code `mama-njeri`, user `admin@demo.test`, password `Demo12345` (local demo data only). Local Postgres `localhost:55434`, backend `node dist/src/main.js` with `DATABASE_URL` and `JWT_SECRET` env vars. No local Redis (warnings are harmless; Redis errors are swallowed).
- Debug build: `GRADLE_OPTS=-Dorg.gradle.java.home=C:/Android/jdk/jdk-17.0.18+8 flutter build apk --debug --dart-define=API_URL=http://localhost:3000/api/v1`, plus `adb reverse tcp:3000 tcp:3000` for a USB phone (emulator uses `http://10.0.2.2:3000/api/v1`).
- adb tooling: `C:\Android\platform-tools`. A USB phone appears on the default adb server (port 5037); the emulator used a separate server on port 5038 (`ANDROID_SERIAL=emulator-5560`).
- Small-phone test: `wm size 720x1280`, `wm density 320`, `settings put system font_scale 1.3`, then reset.
- When driving a real phone: only tap when the Axon app is in the foreground (check `dumpsys window | grep mCurrentFocus`), and revert any setting changed (for example `svc power stayon false`).

## 10. Suggested next steps for the new owner of this work

1. After the owner confirms, set the Firebase variables and verify the startup log line, then test a real push on a phone.
2. On a real phone with 1.0.71: Request Stock, sign-in Next order, then a pass through every remaining page with the real keyboard.
3. On the owner's go-ahead, rename the product to "Axon" (strings, launcher label, update screens, docs) and ship one release.
4. When the AI key and a receipt exist, test Invoice Review with scanned lines.
5. Decide whether to find the root cause of the first-push 500 on customer sync (capture server logs on a fresh install).
6. Keep every release: analyze, full tests, explicit staging, one push, watch the workflow, confirm the release appears.

## 11. Honest status summary

Goal given to the previous assistant: "check the UI/UX and fix it all for every page". Most pages were reviewed and fixed, 1.0.71 is live, and 388 Flutter tests pass with a clean analyze. It is **not** complete: items 1 to 6 above need the owner or hardware.

## 12. Follow-up audit (Codex, 2026-10-17)

- Reconciled the handoff with `main` at `b54d265` (the sign-in keyboard-order fix); no newer committed source changes were found.
- Reviewed the main tabs and key pages on the attached Android emulator: Dashboard, POS, AI, Products, Customers and Customer Profile, Inventory and Request Stock, Cart, Reports, Payments, Settings, Finance, and Trade Partners. No sales or stock requests were submitted.
- Request Stock looks complete in the emulator at 1080x2400; the real-phone check in Section 6 remains open.
- The emulator was running `1.0.68-debug` (version code 2111), not the current `1.0.71` source. The local API on port 3000 was unavailable, so Finance and Trade Partners displayed their saved/offline states. Do not treat these screenshots as proof of the latest release or online behavior.
- The new debug APK was not installed over that emulator session: updates sign the user out by design, and the local API was unavailable to restore the demo session.
- Local, uncommitted UI fixes: moved Add Product out of the Products grid overlay into its catalog header; made EmptyState action icons configurable for shopping, add-customer, and clear-search actions; added a visible Try again action when cached Trade Partners or Notifications cannot refresh.
- `flutter analyze` passed on the follow-up source. A local debug APK build succeeded, but it was not installed on the emulator. No release was built or published.

- Further visual checks covered Inventory Low Stock, Stock Requests, Restock Suggestions, Payments, Manual Payments, Payment Analytics, Reports, Sales Report, Product Detail, Cash Flow, Receipts and Receipt Detail, Notifications, Team, Roles, and New Role. The no-backend state showed explicit connection/retry guidance on Restock Suggestions, Manual Payments, Reports, Sales Report, and Cash Flow. No payment, day-close, or role-management action was submitted.
- The stale emulator still shows the Products Add Product FAB covering the bottom-right card. The source change moves this action into the Catalog header, but it has not been built and rechecked on-device.
- Payment Analytics fell back to local records and showed zero sales without identifying the data as device-local. The source now labels the offline fallback and shows an actionable error if both server and local loads fail. Screen-specific `dart analyze` passed; the old emulator build does not include this change.
- End of Day had been swallowing cash-balance and daily-close request failures, which could make a failed close lookup look like an open day. Those failures now reach its existing retry screen; the API represents a successful “not closed” result as null. Screen-specific `dart analyze` passed. No close action was performed, and the stale emulator does not include this change.
- Receipts list screenshot exposed a right-edge RenderFlex overflow where a long receipt number competed with the payment chip. The row now ellipsizes the number/date and constrains the amount column; `dart analyze` passed. Receipt detail was also viewed read-only. The overflow fix still needs a rebuilt-device visual check.
- Team, Roles, and New Role showed full Dio connection exceptions on the old emulator build. User/role load and mutation errors now use the plain-language helper; role/permission error states can retry, and Save Role is hidden until its required data is available. Targeted `dart analyze` passed. The old build does not include these fixes; Edit Role and User Permissions still need a screen review.
- Code-owned finding: Stock Requests showed “No pending requests” after a failed fetch, making a network error look like an empty queue. It now displays an inline retry state, keeps any loaded requests visible with a retry banner, ties results to the selected status, and ignores late responses from earlier tab loads. The All tab empty-state wording is also clearer. Screen-specific `dart analyze` passed.
- Manual Payments had identical error title and fallback subtitle when offline. The subtitle now gives connection guidance. Screen-specific `dart analyze` passed. The old emulator build was not changed, so these source fixes were not visually exercised on the device.

The owner-, credential-, and device-dependent checks above remain open. In particular, this emulator review does not close the real-phone checks, Firebase push setup, AI receipt-scan check, launcher-icon check on clients' phones, or the pending app-name decision.

## 13. Route review status (Codex, 2026-10-17)

The source-level review of the remaining routes is complete. These checks confirm routing, permission rules, loading/error states, and available actions in the current Flutter source. They are not current-build visual or online verification: the emulator still has `1.0.68-debug`, and the local API was unavailable. Do not submit sales, payment approvals, stock requests, invitations, product edits, purchases, or day closes merely to reach a screen.

- **Auth and onboarding:** `/company-choice`, `/company-setup`, `/owner-welcome`, `/activation`, `/plan-selection`, `/accept-invite`, `/set-password-after-invite`, and `/pin-login`. The blank API-address reset now removes the stored override and restores the actual default. Activation and plan errors show user-facing messages. No activation, invite acceptance, or payment was completed.
- **Dashboard and checkout:** `/staff-tour`, `/dashboard/day/:date`, and `/payment`. The old emulator showed Day Summary's retry state with a clear “Couldn't load this day” message. No sale or day close was submitted.
- **Inventory and reports:** both receive-batch aliases, `/reports/analytics`, and `/reports/inventory-forecast`. Direct routes now use the inventory and report permissions that match the backend.
- **Account and help:** `/billing` and its legacy subscription redirect, `/user-guide`, `/ai/memory`, and `/ai/upgrade`. No plan change or purchase was attempted.
- **Team and collaboration:** Edit Role, User Permissions, and `/partners/:id`. Role create/update/delete controls and direct routes follow their specific permissions; partner access follows the backend Admin/Manager rule. No role, permission, or partner data was changed.
- **Finance and settings:** Shop Ledger, `/cash-flow/reconciliation`, `/cash-flow/end-of-day`, Operating Hours, and branch management. Finance, receivables, and branch add/edit/delete controls now follow their backend permissions. Operating Hours load failure offers retry and cannot be mistaken for safe-to-save defaults. No reconciliation or close was performed.

Other code-owned fixes in this pass align Finance actions with `finance.view`, `finance.manage_receivables`, `suppliers.invoices_create`, and `cash_flow.settings_view`; expose Request Stock to sales makers and stock managers; replace its raw Dio error; and replace the generic router error's raw exception with a recovery screen.

Final targeted `dart analyze` over all changed `mobile/lib` files passed (`No issues found!`), and `git diff --check` passed. No tests were run, no files were staged, and no build, commit, or release was made.

The local source audit is complete. Owner-, credential-, and device-dependent checks remain open in Sections 6–8: real-phone behavior, Firebase push configuration, live AI receipt scanning, the launcher icon on client devices, the product-name decision, and server logs to identify the first customer-sync 500.