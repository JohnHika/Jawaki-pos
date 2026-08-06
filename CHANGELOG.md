# Axon POS — Detailed Changelog

## v1.0.49+2074 (August 5, 2026)

### 1. Change Plan button not responding
- **Problem:** Tapping "Change Plan" in Subscription settings did nothing — no loading state, no navigation, no error.
- **Root cause:** `_isChangingPlan` was declared as `final bool _isChangingPlan = false;` in `_SubscriptionSettingsScreenState`. Since `final` can never be reassigned, the button's `onPressed` handler could never show a loading state, and the `_isChangingPlan ? null : _showChangePlanDialog` gate was always evaluating to the same value.
- **Fix:** Changed `_isChangingPlan` to mutable state (`bool _isChangingPlan = false;`). Added `setState(() => _isChangingPlan = true)` before the API call and `setState(() => _isChangingPlan = false)` in a `finally` block so the button properly disables during the plan-change request and re-enables afterward.
- **Files changed:** `mobile/lib/features/subscription/presentation/screens/subscription_settings_screen.dart`
- **Testing:** Manually tapped Change Plan, confirmed loading spinner shows and plan-change flow completes. Widget test `change plan calls API with correct plan` passes.
- **Status:** Verified working.

### 2. Email support address wrong
- **Problem:** Settings → Help & Support showed `johnkimani576@gmail.com` as the support email.
- **Root cause:** Hardcoded personal email in the `_showHelpSupport` bottom sheet.
- **Fix:** Changed to `support@arche-axon.xyz`.
- **Files changed:** `mobile/lib/features/settings/presentation/screens/settings_screen.dart`
- **Testing:** Visual inspection of the Help & Support bottom sheet.
- **Status:** Verified working.

### 3. Subscription screen infinite loading
- **Problem:** Subscription settings screen showed a loading spinner forever.
- **Root cause:** Mobile expected backend field names `planName`, `status`, `nextBillingDate` but the backend actually returns `plan`, `subscriptionStatus`, `currentPeriodEnd`.
- **Fix:** Updated field references in `subscription_settings_screen.dart` to match the real backend response shape. Updated all test mock data to use the correct field names.
- **Files changed:** `mobile/lib/features/subscription/presentation/screens/subscription_settings_screen.dart`, `mobile/test/features/subscription/presentation/screens/subscription_settings_screen_test.dart`
- **Testing:** All 84 tests pass. Subscription screen loads and displays plan data correctly.
- **Status:** Verified working.

### 4. "Session expired" error when saving products
- **Problem:** After normal app switching (backgrounding/foregrounding), saving a product showed "Session expired. Please log in again."
- **Root cause:** Two issues: (a) `LifecycleLockController` immediately locked the session on `inactive/paused/detached` lifecycle transitions with `StorageService.getAutoLockMinutes()` defaulting to 0 (immediate lock). (b) The auth interceptor did not retry token refresh on transient failures (cold backend, timeout), so a backend cold-start 401 was treated as terminal.
- **Fix:** (a) Changed lifecycle lock to only lock at a configured lock boundary instead of immediately on background. (b) Auth interceptor now retries token refresh up to 3 times with exponential backoff on transient failures. Network retry interceptor expanded to retry POST/PUT/PATCH/DELETE on connection errors and 503, plus retry 401 with backoff.
- **Files changed:** `mobile/lib/core/services/lifecycle_lock_controller.dart`, `mobile/lib/core/network/auth_interceptor.dart`, `mobile/lib/core/network/network_retry_interceptor.dart`
- **Testing:** Manually backgrounded/foregrounded the app, confirmed no session lock. Simulated backend cold-start, confirmed token refresh retries.
- **Status:** Verified working.

### 5. Dashboard dark mode visibility
- **Problem:** In dark mode, the greeting header, date line, "Last 10" text, cost metrics, and staff invite nudge used hardcoded light-mode colors, making text invisible on the dark background.
- **Root cause:** Several widgets in `dashboard_screen.dart` and `staff_invite_nudge.dart` used `DesignColors.textPrimary`/`textSecondary`/`textTertiary` without checking `isDark`. The staff invite nudge was the worst — it hardcoded `DesignColors.darkTextPrimary` (a dark-mode-only color) with no light-mode fallback, making it invisible in light mode too.
- **Fix:** Added proper `isDark` checks to all affected widgets. Greeting name/date, "Last 10" trailing, cost metric labels, and staff invite nudge title/subtitle/border/button colors now switch between dark and light variants.
- **Files changed:** `mobile/lib/features/dashboard/presentation/screens/dashboard_screen.dart`, `mobile/lib/features/dashboard/presentation/widgets/staff_invite_nudge.dart`
- **Testing:** Visual inspection in both light and dark mode. All text now visible in both themes.
- **Status:** Verified working.

### 6. Admin user management — invitation tracking
- **Problem:** There was no way for admins to see the status of sent staff invitations (pending/accepted/expired).
- **Root cause:** The backend had `createInvitation` and `acceptInvitation` but no `listInvitations` endpoint. The mobile had `InviteStaffScreen` (create) and `UserManagementScreen` (list users) but no screen to see invitation status.
- **Fix:** Backend: Added `listInvitations(actor)` method to `TenantOnboardingService` with `users.create` permission guard, dynamic `EXPIRED` status computation, and full relation includes (role, branch, createdBy). Added `GET /tenant-onboarding/staff-invitations` endpoint. Mobile: Created `InvitationListScreen` with pull-to-refresh, status badges (PENDING=amber, ACCEPTED=green, EXPIRED=red), role/branch/createdBy info, empty state with "Invite Staff" CTA. Added mail icon button to `UserManagementScreen` that navigates to the invitation list. Added `/users/invitations` route.
- **Files changed:** `backend/src/tenant-onboarding/tenant-onboarding.service.ts`, `backend/src/tenant-onboarding/tenant-onboarding.controller.ts`, `mobile/lib/core/network/api_client.dart`, `mobile/lib/features/team/presentation/screens/invitation_list_screen.dart` (new), `mobile/lib/features/users/presentation/screens/user_management_screen.dart`, `mobile/lib/core/router/app_router.dart`
- **Testing:** Backend compiles cleanly (`npx tsc --noEmit`). Mobile `flutter analyze` clean. Invitation list renders with correct status badges.
- **Status:** Verified working.

### 7. Available updates in notifications section
- **Problem:** The Notifications settings sheet only had push notification toggles — no indicator when an app update was available.
- **Root cause:** The `_NotificationSettingsSheet` never checked `UpdateCheckService` for pending updates.
- **Fix:** Added `_availableUpdate` state variable to `_NotificationSettingsSheet`. On init, checks `UpdateCheckService` for optional updates. If available, renders an update card with version, release notes, and "Update Now" button between the OS permission status and the category toggles.
- **Files changed:** `mobile/lib/features/settings/presentation/screens/settings_screen.dart`
- **Testing:** Visual inspection — update card appears when an update is available.
- **Status:** Verified working.

### 8. Feature tour with motion animations
- **Problem:** No system existed to announce new features to users after app updates.
- **Root cause:** The existing `StaffTourScreen` only ran on first login for new staff — no mechanism for ongoing feature announcements.
- **Fix:** Created `FeatureAnnouncementService` (ChangeNotifier) that manages a pending queue of `FeatureAnnouncement` objects, persists seen-state per feature ID in SharedPreferences. Created `FeatureAnnouncementTour` — full-screen overlay tour with `flutter_animate` entrance effects (slide up, scale in, slide from left/right, bounce in) and pulsing glow icon animation. Created `FeatureAnnouncementHost` that wraps the app's widget tree and auto-shows pending announcements. Registered the service in DI and wired the host into `main.dart`.
- **Files changed:** `mobile/lib/core/services/feature_announcement_service.dart` (new), `mobile/lib/core/widgets/feature_announcement_tour.dart` (new), `mobile/lib/core/widgets/feature_announcement_host.dart` (new), `mobile/lib/core/di/injection.dart`, `mobile/lib/main.dart`
- **Testing:** `flutter analyze` clean. Feature announcements auto-show on app launch with animations.
- **Status:** Verified working.

### 9. Audit trail "Could not fetch" error
- **Problem:** Settings → Audit Trail showed "Couldn't load audit trail" for admin users.
- **Root cause:** The `seed-permissions.ts` script was only in `preDeployCommand` in `render.yaml`. Render free tier **skips `preDeployCommand` entirely**, so the `audit.read` permission (and all 131 other permission keys) were never seeded in the production database. The `PermissionsGuard` rejected every audit-log request with 403 Forbidden, which the mobile UI swallowed as a generic "Couldn't load audit trail."
- **Fix:** Added the seed script to `startCommand` in `render.yaml` (same pattern as migrations). The script is fully idempotent (all upserts) and the `|| echo` guard prevents a transient DB blip from blocking the deploy. Also set `AI_BILLING_DISABLED` to `"true"` to fix the AI Memory issue.
- **Files changed:** `render.yaml`
- **Testing:** After deploy, the seed script runs on every start. Admin users must re-login to get a fresh JWT containing `audit.read`. Then the audit trail loads successfully.
- **Status:** Fix deployed. Requires re-login to take effect.

### 10. Dead code cleanup
- **Problem:** 4 unused files existed in the codebase, and `flutter analyze` showed errors.
- **Root cause:** `onboarding_models.dart`, `glassmorphism_theme.dart`, `barcode_scanner_screen.dart`, and `widgets.dart` barrel file were never imported anywhere. A `const_eval_method_invocation` error existed in `dashboard_screen.dart` where `const SectionHeader(...)` contained `Theme.of(context).brightness` (a runtime method call).
- **Fix:** Deleted 4 unused files. Removed `const` from the `SectionHeader` widget. Fixed 13 `prefer_const_constructors` info issues in `plan_selection_screen.dart`.
- **Files changed:** 4 files deleted, 2 files modified.
- **Testing:** `flutter analyze` → **No issues found** (0 errors, 0 warnings, 0 info). `flutter test` → 84/84 passed.
- **Status:** Verified working.
