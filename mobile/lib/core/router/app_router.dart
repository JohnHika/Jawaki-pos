import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/pin_login_screen.dart';
import '../../features/auth/presentation/screens/company_choice_screen.dart';
import '../../features/auth/presentation/screens/company_setup_screen.dart';
import '../../features/auth/presentation/screens/owner_welcome_screen.dart';
import '../../features/auth/presentation/screens/company_activation_screen.dart';
import '../../features/team/presentation/screens/invite_staff_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/staff_tour_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/profit_adjustment_screen.dart';
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
import '../../features/settings/presentation/screens/user_guide_screen.dart';
import '../../features/settings/presentation/screens/operating_hours_screen.dart';
import '../../features/ai/presentation/screens/ai_memory_screen.dart';
import '../../features/payments/presentation/screens/payments_hub_screen.dart';
import '../../features/customers/presentation/screens/customers_screen.dart';
import '../../features/customers/presentation/screens/customer_profile_screen.dart';
import '../../features/finance/presentation/screens/finance_screen.dart';
import '../../features/finance/presentation/screens/cash_flow_screen.dart';
import '../../features/finance/presentation/screens/cash_reconciliation_screen.dart';
import '../../features/finance/presentation/screens/end_of_day_screen.dart';
import '../../features/inventory/presentation/screens/restock_suggestions_screen.dart';
import '../../features/ai/presentation/screens/ai_chat_screen.dart';
import '../../features/ai-billing/presentation/screens/ai_trial_screen.dart';
import '../../features/ai-billing/presentation/screens/ai_subscribe_screen.dart';
import '../../features/users/presentation/screens/user_management_screen.dart';
import '../../features/users/presentation/screens/role_editor_screen.dart';
import '../../features/users/presentation/screens/user_permission_override_screen.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../di/injection.dart';
import '../auth/app_roles.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authService = getIt<AuthService>();
  final storageService = getIt<StorageService>();

  // Determine the correct start screen without showing a flash of the wrong
  // screen.  configureDependencies() awaits authService.initialize() before
  // runApp(), so these flags already reflect the real session state when this
  // Provider is first evaluated.
  final String initialLocation;
  if (authService.isAuthenticated) {
    if (authService.requiresTenantActivation) {
      initialLocation = '/activation';
    } else {
      // Returning owner/manager accounts should land on the business overview;
      // staff without that capability continue to land on POS.
      final canSeeDashboard = RolePermissions(
        authService.currentUser?['permissions'] as List<dynamic>?,
      ).canSeeDashboard;
      initialLocation = canSeeDashboard
          ? '/dashboard'
          : (storageService.hasSeenStaffTour() ? '/' : '/staff-tour');
    }
  } else if (authService.isLocked) {
    // Session exists but is soft-locked (backgrounded past the auto-lock
    // window, or "remember me" kept it across a relaunch) — send them to
    // the fast PIN/biometric unlock instead of making them retype a
    // password they already gave us this session.
    initialLocation = '/pin-login';
  } else if (storageService.getTenantSlug()?.isNotEmpty == true) {
    // Company is already set up; user just needs to log in.
    initialLocation = '/login';
  } else {
    // Fresh install — show the company-choice/setup screen.
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

      // Setup routes (company-choice, company-setup) are always accessible
      final isSetupRoute =
          path == '/company-choice' || path == '/company-setup';
      final isActivationRoute = path == '/activation';

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
        // Allow setup and login routes
        if (isSetupRoute || isLoginRoute) {
          return null;
        }
        // Redirect all others to company-choice
        return '/company-choice';
      }

      if (authService.requiresTenantActivation && !isActivationRoute) {
        return '/activation';
      }

      if (!authService.requiresTenantActivation && isActivationRoute) {
        return '/dashboard';
      }

      // If logged in and on setup/login page, go to main app — unless this
      // device has never seen the first-login staff tour yet, in which
      // case that runs once before the user ever reaches the real POS
      // screen unguided. The tour itself sets hasSeenStaffTour(true) when
      // it finishes/is skipped, so this only ever fires once per device.
      if (isLoggedIn && (isSetupRoute || isLoginRoute)) {
        final canSeeDashboard = RolePermissions(
          authService.currentUser?['permissions'] as List<dynamic>?,
        ).canSeeDashboard;
        return canSeeDashboard
            ? '/dashboard'
            : (storageService.hasSeenStaffTour() ? '/' : '/staff-tour');
      }

      // Role-based route guards
      if (isLoggedIn) {
        final perms = RolePermissions(
          authService.currentUser?['permissions'] as List<dynamic>?,
        );

        // Products & Inventory require stock keeper+
        if ((path == '/products' ||
                path.startsWith('/products/') ||
                path == '/inventory' ||
                path.startsWith('/inventory/')) &&
            !perms.canSeeProducts) {
          return '/';
        }
        // Reports require reporting capability. Dashboard is the shared
        // overview and remains reachable for every signed-in role.
        if (path == '/reports' && !perms.canSeeReports) {
          return '/';
        }
      }

      return null;
    },
    routes: [
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
        path: '/activation',
        name: 'activation',
        builder: (context, state) => CompanyActivationScreen(
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
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>;
                  return ProfitAdjustmentScreen(
                    date: extra['date'] as DateTime,
                    currentRevenue: extra['currentRevenue'] as double,
                    currentCost: extra['currentCost'] as double,
                  );
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
                builder: (context, state) =>
                    ReceiptScreen(saleId: state.pathParameters['saleId']!),
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
                builder: (context, state) => ProductDetailScreen(
                  productId: state.pathParameters['productId']!,
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

          // Customers Screen
          GoRoute(
            path: '/customers',
            name: 'customers',
            builder: (context, state) => const CustomersScreen(),
            routes: [
              GoRoute(
                path: ':customerId',
                name: 'customer-profile',
                builder: (context, state) => CustomerProfileScreen(
                  customerId: state.pathParameters['customerId']!,
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
            builder: (context, state) => const UserManagementScreen(),
            routes: [
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

          // AI Subscription Landing Screen (shown when a branch is unpaid)
          GoRoute(
            path: '/ai/trial',
            name: 'ai-trial',
            builder: (context, state) {
              final branchId = state.extra as String;
              return AiTrialScreen(
                branchId: branchId,
                branchName: '', // Not used anymore
                onSubscribe: () =>
                    context.push('/ai/subscribe', extra: branchId),
              );
            },
          ),

          // AI Subscribe Screen
          GoRoute(
            path: '/ai/subscribe',
            name: 'ai-subscribe',
            builder: (context, state) {
              final branchId = state.extra as String;
              return AiSubscribeScreen(
                branchId: branchId,
                branchName: '', // Not used anymore
              );
            },
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.error}'))),
  );
});

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
