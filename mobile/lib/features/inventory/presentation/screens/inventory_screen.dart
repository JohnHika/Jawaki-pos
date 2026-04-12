import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/auth/app_roles.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authService = getIt<AuthService>();
    final role = AppRole.fromString(authService.userRole);
    final permissions = RolePermissions(role);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          // Stock Requests button (for managers/supervisors)
          if (permissions.canManageStock && role.isAtLeast(AppRole.stockKeeper))
            IconButton(
              icon: const Icon(Icons.assignment_outlined),
              tooltip: 'Stock Requests',
              onPressed: () => context.push('/inventory/stock-requests'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Refresh inventory
            },
          ),
        ],
      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Container(
              color: AppColors.surface,
              child: const TabBar(
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: [
                  Tab(text: 'Stock'),
                  Tab(text: 'Low Stock'),
                  Tab(text: 'Transfers'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildStockTab(),
                  _buildLowStockTab(),
                  _buildTransfersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: permissions.canManageStock
          ? _buildActionButtons(context, role)
          : null,
    );
  }

  Widget _buildActionButtons(BuildContext context, AppRole role) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Request Stock button (all roles with inventory access)
        FloatingActionButton.extended(
          heroTag: 'request_stock',
          onPressed: () => context.push('/inventory/request-stock'),
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Request Stock'),
          backgroundColor: AppColors.warning,
        ),
        const SizedBox(height: 12),
        // Receive Batch button (supervisor+)
        if (role.isAtLeast(AppRole.stockKeeper))
          FloatingActionButton.extended(
            heroTag: 'receive_batch',
            onPressed: () {
              // For now, show a snackbar. Will need product selection
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Select a product from Stock tab, then tap Receive'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.inventory),
            label: const Text('Receive Stock'),
            backgroundColor: AppColors.primary,
          ),
      ],
    );
  }

  Widget _buildStockTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warehouse_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          const Text('Stock Levels'),
          const SizedBox(height: 8),
          Text(
            'View and manage stock for all products',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 64,
            color: AppColors.warning,
          ),
          const SizedBox(height: 16),
          const Text('Low Stock Alerts'),
          const SizedBox(height: 8),
          Text(
            'Items that need restocking',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTransfersTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_horiz_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          const Text('Stock Transfers'),
          const SizedBox(height: 8),
          Text(
            'Transfer stock between branches',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
