import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/pin_login_screen.dart';
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
import '../services/auth_service.dart';
import '../di/injection.dart';
import '../auth/app_roles.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authService = getIt<AuthService>();
  
  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: true,
    refreshListenable: GoRouterRefreshStream(authService.authStatusStream),
    redirect: (context, state) {
      final isLoggedIn = authService.isAuthenticated;
      final isLoggingIn = state.matchedLocation == '/login' || 
                          state.matchedLocation == '/pin-login';
      
      if (!isLoggedIn && !isLoggingIn) {
        return '/login';
      }
      
      if (isLoggedIn && isLoggingIn) {
        return '/';
      }
      
      // Role-based route guards
      if (isLoggedIn) {
        final role = AppRole.fromString(authService.userRole);
        final perms = RolePermissions(role);
        final path = state.matchedLocation;
        
        // Products & Inventory require stock keeper+
        if ((path == '/products' || path.startsWith('/products/') ||
             path == '/inventory') && !perms.canSeeProducts) {
          return '/';
        }
        // Reports & Dashboard require store manager+
        if ((path == '/reports' || path == '/dashboard') && !perms.canSeeReports) {
          return '/';
        }
      }
      
      return null;
    },
    routes: [
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
                builder: (context, state) => ReceiptScreen(
                  saleId: state.pathParameters['saleId']!,
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
                builder: (context, state) => const BatchReceiveScreen(),
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
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.error}'),
      ),
    ),
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
