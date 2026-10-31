import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/pin_login_screen.dart';
import '../../features/auth/presentation/screens/company_choice_screen.dart';
import '../../features/auth/presentation/screens/company_setup_screen.dart';
import '../../features/auth/presentation/screens/owner_welcome_screen.dart';
import '../../features/auth/presentation/screens/local_workspace_transition_screen.dart';
import '../../features/auth/presentation/screens/company_activation_screen.dart';
import '../../features/subscription/presentation/screens/plan_selection_screen.dart';
import '../../features/team/presentation/screens/invite_staff_screen.dart';
import '../../features/team/presentation/screens/invitation_list_screen.dart';
import '../../features/team/presentation/screens/accept_invite_screen.dart';
import '../../features/team/presentation/screens/set_password_after_invite_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/staff_tour_screen.dart';
import '../../features/home/presentation/screens/local_feature_unavailable_screen.dart';
import '../../features/settings/presentation/screens/local_archive_history_screen.dart';
import '../../features/settings/presentation/screens/desktop_approvals_screen.dart';
import '../../features/billing/presentation/screens/subscription_billing_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/partners/presentation/screens/partner_chat_screen.dart';
import '../../features/partners/presentation/screens/partners_screen.dart';
import '../../features/accountability/presentation/screens/accountability_rules_screen.dart';
import '../../features/accountability/presentation/screens/shop_alerts_screen.dart';
import '../../features/stocktake/presentation/screens/stock_count_screen.dart';
import '../../features/stocktake/presentation/screens/stock_counts_screen.dart';
import '../../features/imports/presentation/screens/import_detail_screen.dart';
import '../../features/imports/presentation/screens/imports_screen.dart';
import '../../features/news/presentation/screens/business_news_screen.dart';
import '../../features/coupons/presentation/screens/coupons_screen.dart';
import '../../features/referrals/presentation/screens/referrals_screen.dart';
import '../../features/statements/presentation/screens/mpesa_match_screen.dart';
import '../../features/statements/presentation/screens/statement_replies_screen.dart';
import '../../features/pricelist/presentation/screens/price_list_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/profit_adjustment_screen.dart';
import '../../features/dashboard/presentation/screens/day_summary_screen.dart';
import '../../features/sales/presentation/screens/pos_screen.dart';
import '../../features/sales/presentation/screens/cart_screen.dart';
import '../../features/sales/presentation/screens/payment_screen.dart';
import '../../features/sales/presentation/screens/receipt_screen.dart';
import '../../features/sales/presentation/screens/receipts_list_screen.dart';
import '../../features/catalog/presentation/screens/products_screen.dart';
import '../../features/catalog/presentation/screens/product_detail_screen.dart';
import '../../features/inventory/presentation/screens/inventory_screen.dart';
import '../../features/inventory/presentation/screens/stock_request_screen.dart';
import '../../features/inventory/presentation/screens/stock_requests_list_screen.dart';
import '../../features/inventory/presentation/screens/batch_receive_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/reports/presentation/screens/analytics_dashboard_screen.dart';
import '../../features/reports/presentation/screens/inventory_forecasting_screen.dart';
import '../../features/payments/presentation/screens/payment_analytics_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/business_layout_screen.dart';
import '../../features/settings/presentation/screens/user_guide_screen.dart';
import '../../features/settings/presentation/screens/operating_hours_screen.dart';
import '../../features/settings/presentation/screens/bug_report_screen.dart';
import '../../features/settings/presentation/screens/axon_gateway_settings_screen.dart';
import '../../features/legal/presentation/screens/legal_document_screen.dart';
import '../../features/ai/presentation/screens/ai_memory_screen.dart';
import '../../features/payments/presentation/screens/payments_hub_screen.dart';
import '../../features/payments/presentation/screens/merchant_payout_setup_screen.dart';
import '../../features/customers/presentation/screens/customers_screen.dart';
import '../../features/customers/presentation/screens/customer_profile_screen.dart';
import '../../features/finance/presentation/screens/finance_screen.dart';
import '../../features/finance/presentation/screens/cash_flow_screen.dart';
import '../../features/finance/presentation/screens/cash_reconciliation_screen.dart';
import '../../features/finance/presentation/screens/end_of_day_screen.dart';
import '../../features/inventory/presentation/screens/restock_suggestions_screen.dart';
import '../../features/ai/presentation/screens/ai_chat_screen.dart';
import '../../features/ai-billing/presentation/screens/ai_upgrade_screen.dart';
import '../../features/users/presentation/screens/user_management_screen.dart';
import '../../features/users/presentation/screens/local_staff_screen.dart';
import '../../features/users/presentation/screens/role_editor_screen.dart';
import '../../features/users/presentation/screens/user_permission_override_screen.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../di/injection.dart';
import '../auth/app_roles.dart';
import '../providers/business_layout_provider.dart';
import '../providers/local_workspace_capabilities.dart';
import '../theme/design_system.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authService = getIt<AuthService>();
  final storageService = getIt<StorageService>();

  // Determine the correct start screen without showing a flash of the wrong
  // screen.  configureDependencies() awaits authService.initialize() before
  // runApp(), so these flags already reflect the real session state when this
  // Provider is first evaluated.
  final String initialLocation;
  if (authService.isAuthenticated) {
    if (storageService.hasLocalWorkspace()) {
      // A saved device workspace beats any stale cloud session: reopening it
      // with its PIN replaces the session with the local profile. This is
      // what a device upgraded from a hosted-POS release lands on instead of
      // an impossible "adopt again" screen.
      initialLocation = '/pin-login';
    } else if (authService.requiresLocalWorkspaceAdoption) {
      // A saved cloud session must be adopted locally before entering screens
      // that used to depend on the now-retired POS API.
      initialLocation = '/workspace/localize';
    } else if (authService.requiresTenantActivation) {
      initialLocation = '/activation';
    } else {
      // Open the first work surface available to this account. Staff tour is
      // still shown once before that surface when the device has not seen it.
      final permissions = RolePermissions(
        authService.currentUser?['permissions'] as List<dynamic>?,
      );
      final businessLayout = businessLayoutFromUser(authService.currentUser);
      final startPath = authService.isLocalWorkspace
          ? LocalWorkspaceCapabilities.homePathFor(permissions, businessLayout)
          : businessLayout.homePathFor(permissions);
      initialLocation = permissions.canSeeDashboard
          ? startPath
          : (storageService.hasSeenStaffTour() ? startPath : '/staff-tour');
    }
  } else if (authService.isLocked) {
    // Session exists but is soft-locked (backgrounded past the auto-lock
    // window, or "remember me" kept it across a relaunch) — send them to
    // the fast PIN/biometric unlock instead of making them retype a
    // password they already gave us this session.
    initialLocation = '/pin-login';
  } else if (storageService.hasLocalWorkspace()) {
    // Local-first installs reopen the device-owned workspace with its owner
    // PIN. They never fall through to the retired server login screen.
    initialLocation = '/pin-login';
  } else if (authService.isUsingConfiguredLocalServer) {
    // A user who explicitly configured a private-LAN server can still sign
    // back in to that server. A remembered tenant slug alone is not enough:
    // the retired hosted POS has no login route in the downloadable edition.
    initialLocation = '/login';
  } else {
    // Standalone installs always return to local setup, even if an older
    // cloud-only install left a tenant slug or remembered email behind.
    initialLocation = '/company-choice';
  }

  return GoRouter(
    initialLocation: initialLocation,
    debugLogDiagnostics: true,
    refreshListenable: GoRouterRefreshStream(authService.authStatusStream),
    redirect: (context, state) {
      final isLoggedIn = authService.isAuthenticated;
      final isLocked = authService.isLocked;
      final path = state.matchedLocation;

      // Setup routes (company-choice, company-setup) are always accessible.
      // Plan selection is a POST-activation, authenticated step (the user
      // already has a session by the time activation completes) and is
      // deliberately NOT included here — folding it in would let the
      // "logged-in user on a setup route" rule below immediately bounce
      // them back to the dashboard before they can choose a plan.
      final isSetupRoute =
          path == '/company-choice' || path == '/company-setup';
      final isActivationRoute = path == '/activation';
      final isLegalRoute = path == '/legal' || path.startsWith('/legal/');

      // Login routes
      final isLoginRoute = path == '/login' || path == '/pin-login';

      // A locked session should only ever see the fast-unlock screen —
      // not the full login form, and not setup/onboarding, and not the
      // main app until it unlocks.
      if (isLocked) {
        return path == '/pin-login' ? null : '/pin-login';
      }

      // If user is not logged in (and not merely locked)
      if (!isLoggedIn) {
        if (storageService.hasLocalWorkspace()) {
          return path == '/pin-login' || isLegalRoute ? null : '/pin-login';
        }
        // Setup and legal routes are available while signed out. The only
        // login route retained by this edition is for an explicitly
        // configured private-LAN server; hosted login and invitations need
        // the retired online POS service.
        // Plan selection always requires an active session by the time it
        // is reached (activation itself needs one), so it is intentionally
        // not allowed here — an unauthenticated visit falls through to the
        // company-choice redirect below like any other protected route.
        if (isSetupRoute ||
            isLegalRoute ||
            (authService.isUsingConfiguredLocalServer && path == '/login')) {
          return null;
        }
        // Redirect all others to company-choice
        return '/company-choice';
      }

      // A legacy cloud session alongside a saved device workspace means the
      // workspace can simply be reopened with its PIN — adopting again is
      // impossible and pointless. Park the stale session on the local
      // sign-in screen; a successful owner-PIN sign-in replaces the session
      // with the local profile.
      final pendingLocalSignIn =
          authService.isAuthenticated &&
              !authService.isLocalWorkspace &&
              storageService.hasLocalWorkspace();
      if (pendingLocalSignIn && path != '/pin-login' && !isLegalRoute) {
        return '/pin-login';
      }

      // The cloud POS is retired. Keep an unlocked legacy session on the
      // local-adoption screen instead of exposing pages whose data refreshes
      // can only hit the retired API.
      if (authService.requiresLocalWorkspaceAdoption && !isLegalRoute) {
        return path == '/workspace/localize' ? null : '/workspace/localize';
      }

      if (authService.requiresTenantActivation &&
          !isActivationRoute &&
          !isLegalRoute) {
        return '/activation';
      }

      if (!authService.requiresTenantActivation && isActivationRoute) {
        return _preferredHomePath(
          authService.currentUser,
          isLocalWorkspace: authService.isLocalWorkspace,
        );
      }

      // If logged in and on setup/login page, go to main app — unless this
      // device has never seen the first-login staff tour yet, in which
      // case that runs once before the user ever reaches the real POS
      // screen unguided. The tour itself sets hasSeenStaffTour(true) when
      // it finishes/is skipped, so this only ever fires once per device.
      // Plan selection is deliberately excluded (see isSetupRoute above).
      if (isLoggedIn && (isSetupRoute || isLoginRoute)) {
        final permissions = RolePermissions(
          authService.currentUser?['permissions'] as List<dynamic>?,
        );
        final businessLayout = businessLayoutFromUser(authService.currentUser);
        final homePath = authService.isLocalWorkspace
            ? LocalWorkspaceCapabilities.homePathFor(
                permissions, businessLayout)
            : businessLayout.homePathFor(permissions);
        return permissions.canSeeDashboard
            ? homePath
            : (storageService.hasSeenStaffTour() ? homePath : '/staff-tour');
      }

      // Role-based route guards
      if (isLoggedIn) {
        // This downloadable edition is device-local. Redirect stale links and
        // hidden cloud-only work areas to the owner's permitted local home
        // instead of letting them wait on the retired POS API.
        if (authService.isLocalWorkspace &&
            !LocalWorkspaceCapabilities.supportsPath(path)) {
          final feature =
              LocalWorkspaceCapabilities.unavailableFeatureFor(path);
          return '/workspace/unavailable'
              '?feature=${Uri.encodeQueryComponent(feature)}'
              '&from=${Uri.encodeQueryComponent(path)}';
        }

        if (path == '/workspace/unavailable' && !authService.isLocalWorkspace) {
          return _preferredHomePath(
            authService.currentUser,
          );
        }

        final perms = RolePermissions(
          authService.currentUser?['permissions'] as List<dynamic>?,
        );

        if ((path == '/' || path == '/cart' || path == '/payment') &&
            !perms.canMakeSales) {
          return businessLayoutFromUser(authService.currentUser)
              .homePathFor(perms);
        }
        if (path.startsWith('/receipt/') &&
            !perms.canMakeSales &&
            !perms.has('sales.view')) {
          return businessLayoutFromUser(authService.currentUser)
              .homePathFor(perms);
        }

        if ((path == '/customers' || path.startsWith('/customers/')) &&
            !perms.has('customers.view')) {
          return '/';
        }
        if (path == '/receipts' && !perms.has('sales.view')) {
          return '/';
        }
        if (path == '/payments' &&
            !perms.has('payments.view_status') &&
            !perms.has('payments.view_methods')) {
          return '/';
        }
        // Products and Inventory have separate view permissions. Keep direct
        // links aligned with the distinct bottom-nav entries as well.
        if ((path == '/products' || path.startsWith('/products/')) &&
            !perms.canSeeProducts) {
          return '/';
        }
        if (path == '/inventory' && !perms.canSeeInventory) {
          return '/';
        }
        if (path == '/price-list' && !perms.canSeeProducts) {
          return '/';
        }
        if (path == '/inventory/request-stock' &&
            !perms.canMakeSales &&
            !perms.canManageStock) {
          return '/';
        }
        if ((path == '/inventory/receive-batch' ||
                path == '/inventory/batch-receive') &&
            !perms.canManageStock) {
          return '/';
        }
        if (path == '/inventory/restock-suggestions' &&
            !perms.canRecordRestock) {
          return '/';
        }
        if (path == '/inventory/stock-requests' &&
            !perms.has('inventory.stock_requests.resolve')) {
          return '/';
        }
        if (path.startsWith('/inventory/') &&
            path != '/inventory/request-stock' &&
            path != '/inventory/receive-batch' &&
            path != '/inventory/batch-receive' &&
            path != '/inventory/stock-requests' &&
            path != '/inventory/restock-suggestions' &&
            !perms.canSeeInventory) {
          return '/';
        }
        // Reports require reporting capability. Dashboard is the shared
        // overview and remains reachable for every signed-in role. Child
        // report routes need the same guard as the reports index.
        if ((path == '/reports' || path.startsWith('/reports/')) &&
            !perms.canSeeReports) {
          return '/';
        }
        // Each report surface has its own permission in the API. Keep direct
        // links and restored app state aligned with those permissions so a
        // user lands somewhere useful instead of seeing a predictable 403.
        if (path == '/payment-analytics' &&
            !perms.has('reporting.payment_breakdown')) {
          return '/payments';
        }
        // The dashboard calls shop-wide reporting endpoints. Keep it out of
        // reach for cashier roles that cannot read reporting data, including
        // direct links and restored navigation state.
        if ((path == '/dashboard' || path.startsWith('/dashboard/')) &&
            !perms.canSeeDashboard) {
          return '/';
        }
        if (path == '/dashboard/profit-adjustment' && !perms.canRecordRestock) {
          return '/dashboard';
        }
        // Finance endpoints use finance.view. Reporting permissions do not
        // grant access to receivables or supplier ledgers.
        if (path == '/finance' && !perms.canViewFinance) {
          return '/';
        }
        if (path == '/payments/setup' && !perms.canManageMerchantPayout) {
          return '/settings';
        }
        if (path == '/statements/replies' && !perms.has('statements.share')) {
          return '/finance';
        }
        if (path == '/coupons' && !perms.has('coupons.view')) {
          return '/';
        }
        if (path == '/referrals' && !perms.has('referrals.view')) {
          return '/';
        }
        if ((path == '/users' || path.startsWith('/users/')) &&
            path != '/users/invitations' &&
            !perms.canManageUsers) {
          return '/';
        }
        if (path == '/news' && !perms.has('news.view')) {
          return '/';
        }
        if ((path == '/stock-counts' || path.startsWith('/stock-counts/')) &&
            !perms.has('inventory.stocktake.view')) {
          return '/';
        }
        if ((path == '/containers' || path.startsWith('/containers/')) &&
            !perms.has('imports.view')) {
          return '/';
        }
        if (path == '/shop-alerts' && !perms.has('accountability.view')) {
          return '/';
        }
        if (path == '/shop-alerts/rules' &&
            !perms.has('accountability.manage')) {
          return '/shop-alerts';
        }
        if (path == '/cash-flow' && !perms.canViewCashFlow) {
          return '/';
        }
        if (path == '/cash-flow/reconciliation' &&
            !perms.has('cash_reconciliation.view') &&
            !perms.canReconcileCash) {
          return '/';
        }
        if (path == '/cash-flow/end-of-day' && !perms.canCloseEndOfDay) {
          return '/';
        }
        // Operating hours, roles, and per-user permission overrides are
        // branch/user-management actions — only reachable directly (deep
        // link, bookmark, restored nav state) by someone who actually holds
        // the relevant capability. The Settings menu itself already hides
        // these entries from everyone else; this closes the direct-route
        // gap flagged in the settings audit.
        if (path == '/settings/operating-hours' && !perms.canUpdateBranches) {
          return '/settings';
        }
        // Layout actions change the shared checkout, terminology, dashboard,
        // and work-area configuration. The screen disables saving for other
        // roles, but direct links should land them in Settings rather than
        // opening an editor they cannot use.
        if (path == '/settings/business-layout' &&
            !perms.has('branches.tenant.update')) {
          return '/settings';
        }
        if (path == '/settings/ai-gateway' &&
            (!authService.isLocalWorkspace ||
                !authService.isLocalWorkspaceOwner)) {
          return '/settings';
        }
        if (path.startsWith('/settings/archive-history') &&
            authService.isLocalWorkspace &&
            !authService.isLocalWorkspaceOwner) {
          return '/settings';
        }
        if ((path == '/ai' || path.startsWith('/ai/')) &&
            !perms.has('ai.chat')) {
          return businessLayoutFromUser(authService.currentUser)
              .homePathFor(perms);
        }
        if ((path == '/invite-staff' || path == '/users/invitations') &&
            !perms.canInviteStaff) {
          return '/';
        }
        if ((path == '/users/roles' || path.startsWith('/users/roles/')) &&
            !perms.canManageRoles) {
          return '/users';
        }
        if (path == '/users/roles/new' && !perms.canCreateRoles) {
          return '/users/roles';
        }
        if (path.startsWith('/users/roles/') &&
            path != '/users/roles/new' &&
            !perms.canUpdateRoles) {
          return '/users/roles';
        }
        if (path.startsWith('/users/') &&
            path.endsWith('/permissions') &&
            !perms.canOverrideUserPermissions) {
          return '/users';
        }
        // Billing/plan management is currently enforced backend-side as
        // legacy-ADMIN-only (see billing.controller.ts, subscription
        // controller). Mirror that at the route level so a non-admin deep
        // link lands somewhere useful instead of a screen full of actions
        // that will 403.
        if (path == '/billing') {
          final legacyRole =
              authService.currentUser?['role']?.toString().toUpperCase();
          if (legacyRole != 'ADMIN') {
            return '/settings';
          }
        }
        if (path == '/partners' || path.startsWith('/partners/')) {
          final legacyRole = authService.userRole?.toUpperCase();
          if (legacyRole != 'ADMIN' && legacyRole != 'MANAGER') {
            return '/';
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/legal',
        name: 'legal-index',
        builder: (context, state) => const LegalDocumentScreen(),
      ),
      GoRoute(
        path: '/legal/:document',
        name: 'legal-document',
        builder: (context, state) => LegalDocumentScreen(
          documentSlug: state.pathParameters['document'],
        ),
      ),
      // Setup/Onboarding Routes (for fresh installs)
      GoRoute(
        path: '/company-choice',
        name: 'company-choice',
        builder: (context, state) => const CompanyChoiceScreen(),
      ),
      GoRoute(
        path: '/company-setup',
        name: 'company-setup',
        builder: (context, state) => const CompanySetupScreen(),
      ),
      GoRoute(
        path: '/workspace/localize',
        name: 'workspace-localize',
        builder: (context, state) => const LocalWorkspaceTransitionScreen(),
      ),
      GoRoute(
        path: '/owner-welcome',
        name: 'owner-welcome',
        builder: (context, state) =>
            OwnerWelcomeScreen(companyName: state.extra as String?),
      ),
      GoRoute(
        path: '/invite-staff',
        name: 'invite-staff',
        builder: (context, state) => const InviteStaffScreen(),
      ),
      GoRoute(
        path: '/accept-invite',
        name: 'accept-invite',
        builder: (context, state) {
          final extra = state.extra as Map<String, String>? ?? {};
          return AcceptInviteScreen(
            invitationId: extra['invitationId'] ?? '',
            challengeId: extra['challengeId'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/set-password-after-invite',
        name: 'set-password-after-invite',
        builder: (context, state) {
          final extra = state.extra as Map<String, String>? ?? {};
          return SetPasswordAfterInviteScreen(
            invitationId: extra['invitationId'] ?? '',
            setupToken: extra['setupToken'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/activation',
        name: 'activation',
        builder: (context, state) => CompanyActivationScreen(
          companyName: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/plan-selection',
        name: 'plan-selection',
        builder: (context, state) => PlanSelectionScreen(
          companyName: state.extra as String?,
        ),
      ),

      // Auth Routes
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/pin-login',
        name: 'pin-login',
        builder: (context, state) => const PinLoginScreen(),
      ),

      // Main Shell Route with Bottom Navigation
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          // Dashboard (store manager+)
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
            routes: [
              GoRoute(
                path: 'profit-adjustment',
                name: 'profit-adjustment',
                // Needs the figures handed over by the dashboard; a bare link
                // (no extra) would otherwise crash on the cast below.
                redirect: (context, state) =>
                    state.extra is Map<String, dynamic> ? null : '/dashboard',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>;
                  return ProfitAdjustmentScreen(
                    date: extra['date'] as DateTime,
                    currentRevenue: extra['currentRevenue'] as double,
                    currentCost: extra['currentCost'] as double,
                  );
                },
              ),
              GoRoute(
                path: 'day/:date',
                name: 'day-summary',
                builder: (context, state) {
                  final dateStr = state.pathParameters['date']!;
                  return DaySummaryScreen(date: DateTime.parse(dateStr));
                },
              ),
            ],
          ),

          // First-login staff coach-mark tour (see redirect logic above)
          GoRoute(
            path: '/staff-tour',
            name: 'staff-tour',
            builder: (context, state) => const StaffTourScreen(),
          ),
          GoRoute(
            path: '/workspace/unavailable',
            name: 'local-feature-unavailable',
            builder: (context, state) {
              final auth = getIt<AuthService>();
              final user = auth.currentUser;
              final permissions = RolePermissions(
                user?['permissions'] as List<dynamic>?,
              );
              final homePath = LocalWorkspaceCapabilities.homePathFor(
                permissions,
                businessLayoutFromUser(user),
              );
              return LocalFeatureUnavailableScreen(
                featureName:
                    state.uri.queryParameters['feature'] ?? 'This feature',
                sourcePath: state.uri.queryParameters['from'] ?? '',
                homePath: homePath,
                alternative: LocalWorkspaceCapabilities.alternativeFor(
                  state.uri.queryParameters['from'] ?? '',
                  permissions,
                  isWorkspaceOwner: auth.isLocalWorkspaceOwner,
                ),
              );
            },
          ),

          // POS / Sales Screen
          GoRoute(
            path: '/',
            name: 'pos',
            builder: (context, state) => const POSScreen(),
            routes: [
              GoRoute(
                path: 'cart',
                name: 'cart',
                builder: (context, state) => const CartScreen(),
              ),
              GoRoute(
                path: 'payment',
                name: 'payment',
                builder: (context, state) => const PaymentScreen(),
              ),
              GoRoute(
                path: 'receipt/:saleId',
                name: 'receipt',
                builder: (context, state) => ReceiptScreen(
                  saleId: state.pathParameters['saleId']!,
                  // ?fresh=1 is set by the payment screen right after a sale:
                  // that is the only time the receipt celebrates.
                  celebrate: state.uri.queryParameters['fresh'] == '1',
                ),
              ),
            ],
          ),

          // Receipts List Screen
          GoRoute(
            path: '/receipts',
            name: 'receipts',
            builder: (context, state) => const ReceiptsListScreen(),
          ),

          // Products Screen
          GoRoute(
            path: '/products',
            name: 'products',
            builder: (context, state) => const ProductsScreen(),
            routes: [
              GoRoute(
                path: ':productId',
                name: 'product-detail',
                pageBuilder: (context, state) => PageTransition.slideInPage(
                  ProductDetailScreen(
                    productId: state.pathParameters['productId']!,
                  ),
                  key: state.pageKey,
                ),
              ),
            ],
          ),

          // Inventory Screen
          GoRoute(
            path: '/inventory',
            name: 'inventory',
            builder: (context, state) => const InventoryScreen(),
            routes: [
              // Create stock request (cashier+)
              GoRoute(
                path: 'request-stock',
                name: 'request-stock',
                builder: (context, state) => const StockRequestScreen(),
              ),
              // View/manage stock requests (supervisor+)
              GoRoute(
                path: 'stock-requests',
                name: 'stock-requests',
                builder: (context, state) => const StockRequestsListScreen(),
              ),
              // Receive batch with multi-unit (supervisor+)
              GoRoute(
                path: 'receive-batch',
                name: 'receive-batch',
                builder: (context, state) => BatchReceiveScreen(
                  productId: state.uri.queryParameters['productId'],
                  productName: state.uri.queryParameters['productName'],
                  branchId: state.uri.queryParameters['branchId'],
                ),
              ),
              GoRoute(
                path: 'batch-receive',
                name: 'batch-receive',
                builder: (context, state) => BatchReceiveScreen(
                  productId: state.uri.queryParameters['productId'],
                  productName: state.uri.queryParameters['productName'],
                  branchId: state.uri.queryParameters['branchId'],
                ),
              ),
              // AI-powered, cash-budget-aware restock suggestions (stock keeper+)
              GoRoute(
                path: 'restock-suggestions',
                name: 'restock-suggestions',
                builder: (context, state) => const RestockSuggestionsScreen(),
              ),
            ],
          ),

          // Reports Screen
          GoRoute(
            path: '/reports',
            name: 'reports',
            builder: (context, state) => const ReportsScreen(),
            routes: [
              // Analytics Dashboard
              GoRoute(
                path: 'analytics',
                name: 'analytics',
                builder: (context, state) => const AnalyticsDashboardScreen(),
              ),
              // Inventory Forecasting
              GoRoute(
                path: 'inventory-forecast',
                name: 'inventory-forecast',
                builder: (context, state) => const InventoryForecastingScreen(),
              ),
            ],
          ),

          // Payment Analytics Screen
          GoRoute(
            path: '/payment-analytics',
            name: 'payment-analytics',
            builder: (context, state) => const PaymentAnalyticsScreen(),
          ),

          // Payments Hub Screen (today's takings, receipts, analytics, credit)
          GoRoute(
            path: '/payments',
            name: 'payments',
            builder: (context, state) => const PaymentsHubScreen(),
          ),

          GoRoute(
            path: '/payments/setup',
            name: 'merchant-payout-setup',
            builder: (context, state) => const MerchantPayoutSetupScreen(),
          ),

          // Customers Screen
          GoRoute(
            path: '/customers',
            name: 'customers',
            builder: (context, state) => const CustomersScreen(),
            routes: [
              GoRoute(
                path: ':customerId',
                name: 'customer-profile',
                pageBuilder: (context, state) => PageTransition.slideInPage(
                  CustomerProfileScreen(
                    customerId: state.pathParameters['customerId']!,
                  ),
                  key: state.pageKey,
                ),
              ),
            ],
          ),

          // Settings Screen
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/settings/business-layout',
            name: 'business-layout',
            builder: (context, state) => const BusinessLayoutScreen(),
          ),
          GoRoute(
            path: '/settings/ai-gateway',
            name: 'axon-ai-gateway-settings',
            builder: (context, state) => const AxonGatewaySettingsScreen(),
          ),
          GoRoute(
            path: '/settings/archive-history',
            name: 'local-archive-history',
            builder: (context, state) => const LocalArchiveHistoryScreen(),
          ),
          // Desktop sign-in approvals (QR / approval-mode pairing).
          GoRoute(
            path: '/settings/desktop-approvals',
            name: 'desktop-approvals',
            builder: (context, state) => const DesktopApprovalsScreen(),
          ),
          GoRoute(
            path: '/settings/archive-history/:archiveId',
            name: 'local-archive-history-detail',
            builder: (context, state) => LocalArchiveHistoryDetailScreen(
              archiveId: state.pathParameters['archiveId']!,
            ),
          ),

          // Legacy route: redirects into the consolidated Plan & Billing
          // screen. Kept (rather than deleted) so old deep links/bookmarks
          // and any external links still resolve somewhere sensible.
          GoRoute(
            path: '/settings/subscription',
            name: 'subscription-settings',
            redirect: (context, state) => '/billing',
          ),

          // Subscription & Billing Screen (Settings → Subscription & Billing)
          GoRoute(
            path: '/billing',
            name: 'billing',
            builder: (context, state) => const SubscriptionBillingScreen(),
          ),

          // User Guide (Help & Support)
          GoRoute(
            path: '/user-guide',
            name: 'user-guide',
            builder: (context, state) => const UserGuideScreen(),
          ),

          // Per-branch operating hours
          GoRoute(
            path: '/settings/operating-hours',
            name: 'operating-hours',
            builder: (context, state) => const OperatingHoursScreen(),
          ),

          // Bug Report
          GoRoute(
            path: '/settings/report-bug',
            name: 'report-bug',
            builder: (context, state) => const BugReportScreen(),
          ),

          // AI's durable shop memory (view/add/remove)
          GoRoute(
            path: '/ai/memory',
            name: 'ai-memory',
            builder: (context, state) => const AiMemoryScreen(),
          ),

          // User & role management
          GoRoute(
            path: '/users',
            name: 'users',
            builder: (context, state) => authService.isLocalWorkspace
                ? const LocalStaffScreen()
                : const UserManagementScreen(),
            routes: [
              GoRoute(
                path: 'invitations',
                name: 'invitations',
                builder: (context, state) => const InvitationListScreen(),
              ),
              GoRoute(
                path: 'roles',
                name: 'roles',
                builder: (context, state) => const RoleListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: 'role-new',
                    builder: (context, state) => const RoleEditorScreen(),
                  ),
                  GoRoute(
                    path: ':roleId',
                    name: 'role-edit',
                    builder: (context, state) => RoleEditorScreen(
                      roleId: state.pathParameters['roleId'],
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: ':userId/permissions',
                name: 'user-permissions',
                builder: (context, state) => UserPermissionOverrideScreen(
                  userId: state.pathParameters['userId']!,
                ),
              ),
            ],
          ),

          // Notification inbox
          GoRoute(
            path: '/notifications',
            name: 'notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),

          // Trade partners (business-to-business connections + chat)
          GoRoute(
            path: '/partners',
            name: 'partners',
            builder: (context, state) => const PartnersScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'partner-chat',
                builder: (context, state) => PartnerChatScreen(
                  partnershipId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),

          // Shop control: owner alerts and rules, stock counts, containers, news
          GoRoute(
            path: '/shop-alerts',
            name: 'shop-alerts',
            builder: (context, state) => const ShopAlertsScreen(),
            routes: [
              GoRoute(
                path: 'rules',
                name: 'shop-rules',
                builder: (context, state) => const AccountabilityRulesScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/stock-counts',
            name: 'stock-counts',
            builder: (context, state) => const StockCountsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'stock-count',
                builder: (context, state) =>
                    StockCountScreen(countId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/containers',
            name: 'containers',
            builder: (context, state) => const ImportsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'container',
                builder: (context, state) =>
                    ImportDetailScreen(importId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/news',
            name: 'business-news',
            builder: (context, state) => const BusinessNewsScreen(),
          ),

          // Growth and collections: coupons, referrals, debt statements,
          // M-Pesa matching, price list
          GoRoute(
            path: '/coupons',
            name: 'coupons',
            builder: (context, state) => const CouponsScreen(),
          ),
          GoRoute(
            path: '/referrals',
            name: 'referrals',
            builder: (context, state) => const ReferralsScreen(),
          ),
          GoRoute(
            path: '/statements/replies',
            name: 'statement-replies',
            builder: (context, state) => const StatementRepliesScreen(),
          ),
          GoRoute(
            path: '/mpesa-match',
            name: 'mpesa-match',
            builder: (context, state) => const MpesaMatchScreen(),
          ),
          GoRoute(
            path: '/price-list',
            name: 'price-list',
            builder: (context, state) => const PriceListScreen(),
          ),

          // Finance Screen
          GoRoute(
            path: '/finance',
            name: 'finance',
            builder: (context, state) => FinanceScreen(
              prefill: state.extra as RestockPrefill?,
            ),
          ),

          // Cash Flow Screen (store manager+)
          GoRoute(
            path: '/cash-flow',
            name: 'cash-flow',
            builder: (context, state) => const CashFlowScreen(),
            routes: [
              GoRoute(
                path: 'reconciliation',
                name: 'cash-reconciliation',
                builder: (context, state) => const CashReconciliationScreen(),
              ),
              GoRoute(
                path: 'end-of-day',
                name: 'end-of-day',
                builder: (context, state) => const EndOfDayScreen(),
              ),
            ],
          ),

          // AI Chat Screen
          GoRoute(
            path: '/ai',
            name: 'ai',
            builder: (context, state) => const AiChatScreen(),
          ),

          // AI upgrade screen (shown when the tenant's plan doesn't include AI)
          GoRoute(
            path: '/ai/upgrade',
            name: 'ai-upgrade',
            builder: (context, state) {
              final branchId = state.extra as String? ?? '';
              return AiUpgradeScreen(
                branchId: branchId,
                branchName: '', // Not used anymore
                onViewPlans: () => context.push('/billing'),
              );
            },
          ),
        ],
      ),
    ],
    errorBuilder: (context, _) => Scaffold(
      body: Center(
        child: EmptyState(
          icon: Icons.link_off_rounded,
          title: 'Could not open this page',
          subtitle: 'The link may be outdated or incomplete.',
          actionLabel: 'Go to POS',
          onAction: () => context.go('/'),
        ),
      ),
    ),
  );
});

String _preferredHomePath(
  Map<String, dynamic>? user, {
  bool isLocalWorkspace = false,
}) {
  final permissions = RolePermissions(user?['permissions'] as List<dynamic>?);
  final layout = businessLayoutFromUser(user);
  return isLocalWorkspace
      ? LocalWorkspaceCapabilities.homePathFor(permissions, layout)
      : layout.homePathFor(permissions);
}

// Helper class to convert Stream to Listenable for GoRouter
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  StreamSubscription<dynamic>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
