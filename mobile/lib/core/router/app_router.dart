import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/pin_login_screen.dart';
import '../../features/auth/presentation/screens/company_choice_screen.dart';
import '../../features/auth/presentation/screens/company_setup_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
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
import '../../features/payments/presentation/screens/payments_hub_screen.dart';
import '../../features/customers/presentation/screens/customers_screen.dart';
import '../../features/customers/presentation/screens/customer_profile_screen.dart';
import '../../features/finance/presentation/screens/finance_screen.dart';
import '../../features/ai/presentation/screens/ai_chat_screen.dart';
import '../../features/ai-billing/presentation/screens/ai_trial_screen.dart';
import '../../features/ai-billing/presentation/screens/ai_subscribe_screen.dart';
import '../../features/ai-billing/presentation/services/ai_billing_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../di/injection.dart';
import '../auth/app_roles.dart';
import '../../features/clients/presentation/screens/client_management_screen.dart';
import '../../features/clients/presentation/screens/client_detail_screen.dart';
import '../../features/clients/presentation/screens/multi_client_dashboard_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authService = getIt<AuthService>();
  final storageService = getIt<StorageService>();

  // Determine the correct start screen without showing a flash of the wrong
  // screen.  configureDependencies() awaits authService.initialize() before
  // runApp(), so these flags already reflect the real session state when this
  // Provider is first evaluated.
  final String initialLocation;
  if (authService.isAuthenticated) {
    // Returning user with a valid token → go straight to the POS screen.
    initialLocation = '/';
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
      final path = state.matchedLocation;

      // Setup routes (company-choice, company-setup) are always accessible
      final isSetupRoute =
          path == '/company-choice' || path == '/company-setup';

      // Login routes
      final isLoginRoute = path == '/login' || path == '/pin-login';

      // If user is not logged in
      if (!isLoggedIn) {
        // Allow setup and login routes
        if (isSetupRoute || isLoginRoute) {
          return null;
        }
        // Redirect all others to company-choice
        return '/company-choice';
      }

      // If logged in and on setup/login page, go to main app
      if (isLoggedIn && (isSetupRoute || isLoginRoute)) {
        return '/';
      }

      // Role-based route guards
      if (isLoggedIn) {
        final role = AppRole.fromString(authService.userRole);
        final perms = RolePermissions(role);

        // Products & Inventory require stock keeper+
        if ((path == '/products' ||
                path.startsWith('/products/') ||
                path == '/inventory' ||
                path.startsWith('/inventory/')) &&
            !perms.canSeeProducts) {
          return '/';
        }
        // Reports & Dashboard require store manager+
        if ((path == '/reports' || path == '/dashboard') &&
            !perms.canSeeReports) {
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

          // Payments Hub Screen (Manual Payments, Hold Queue, Bulk Payments)
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

          // Finance Screen
          GoRoute(
            path: '/finance',
            name: 'finance',
            builder: (context, state) => const FinanceScreen(),
          ),

          // AI Chat Screen
          GoRoute(
            path: '/ai',
            name: 'ai',
            builder: (context, state) => const AiChatScreen(),
          ),

          // AI Trial Screen
          GoRoute(
            path: '/ai/trial',
            name: 'ai-trial',
            builder: (context, state) {
              final branchId = state.extra as String;
              return AiTrialScreen(
                branchId: branchId,
                branchName: '', // Not used anymore
                onTrialStarted: () => context.go('/ai'),
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

          // Clients Management Screen (admin/supervisor)
          GoRoute(
            path: '/clients',
            name: 'clients',
            builder: (context, state) => const ClientManagementScreen(),
            routes: [
              GoRoute(
                path: ':clientId',
                name: 'client-detail',
                builder: (context, state) => ClientDetailScreen(
                  clientId: state.pathParameters['clientId']!,
                ),
              ),
            ],
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
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final dynamic _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
