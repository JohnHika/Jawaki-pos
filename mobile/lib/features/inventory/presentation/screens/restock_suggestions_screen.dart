import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../finance/presentation/screens/finance_screen.dart' show RestockPrefill;

final _restockSuggestionsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final branchId = getIt<AuthService>().branchId;
  if (branchId == null) return {};
  return getIt<ApiClient>().getRestockSuggestions(branchId);
});

final _currencyFmt =
    NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);

class RestockSuggestionsScreen extends ConsumerWidget {
  const RestockSuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionsProvider);
    final suggestionsAsync = ref.watch(_restockSuggestionsProvider);

    if (!permissions.canRecordRestock) {
      return const Scaffold(
        appBar: BrandedAppBar(title: 'Restock Suggestions'),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Restricted',
          subtitle: 'Only stock keepers and above can view restock suggestions.',
        ),
      );
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Restock Suggestions',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_restockSuggestionsProvider),
          ),
        ],
      ),
      body: suggestionsAsync.when(
        data: (data) {
          if (data.isEmpty) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'No branch selected',
              subtitle: 'Select a branch to view restock suggestions.',
            );
          }

          final items = (data['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          final availableCash = (data['availableCash'] as num).toDouble();
          final trimmedCount = data['trimmedCount'] as int;
          final aiRationale = data['aiRationale'] as String?;

          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                MetricCard(
                  title: 'Available cash',
                  value: _currencyFmt.format(availableCash),
                  icon: Icons.account_balance_wallet_rounded,
                  color: DesignColors.warning,
                ),
                const SizedBox(height: 20),
                EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: trimmedCount > 0
                      ? 'Not enough cash to restock yet'
                      : 'Stock levels look healthy',
                  subtitle: trimmedCount > 0
                      ? '$trimmedCount low-stock item(s) are waiting for more cash to become available.'
                      : 'No products are currently below their reorder level.',
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              MetricCard(
                title: 'Available cash',
                value: _currencyFmt.format(availableCash),
                icon: Icons.account_balance_wallet_rounded,
                color: DesignColors.success,
              ),
              if (aiRationale != null && aiRationale.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DesignColors.brand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: DesignColors.brand.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: DesignColors.brand, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(aiRationale,
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SectionHeader(
                title: 'Suggested purchases',
                subtitle:
                    '${items.length} item${items.length == 1 ? '' : 's'}, prioritized by urgency',
                icon: Icons.local_shipping_outlined,
                trailing: trimmedCount > 0
                    ? StatusBadge(
                        label: '$trimmedCount waiting on cash',
                        color: DesignColors.warning,
                        isActive: true,
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              ...items.map((item) => _RestockSuggestionCard(item: item)),
            ],
          );
        },
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: List.generate(
              4,
              (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: ShimmerWidget(
                        width: double.infinity, height: 100, borderRadius: 14),
                  )),
        ),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load restock suggestions',
          subtitle: 'Check your connection and try again.',
          iconColor: DesignColors.error,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(_restockSuggestionsProvider),
        ),
      ),
    );
  }
}

class _RestockSuggestionCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _RestockSuggestionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    final productName = item['productName'] as String;
    final suggestedQty = (item['suggestedQty'] as num).toDouble();
    final unitCost = (item['unitCost'] as num).toDouble();
    final estimatedCost = (item['estimatedCost'] as num).toDouble();
    final daysOfStockRemaining = item['daysOfStockRemaining'] as int;
    final currentStock = (item['currentStock'] as num).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: surface, border: Border.all(color: border), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(productName,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: titleColor)),
                      const SizedBox(height: 2),
                      Text(
                          'In stock: ${currentStock.toStringAsFixed(0)} — ${daysOfStockRemaining < 999 ? "$daysOfStockRemaining day(s) left" : "no recent sales data"}',
                          style: TextStyle(fontSize: 12, color: secondaryColor)),
                    ],
                  ),
                ),
                if (daysOfStockRemaining <= 3)
                  const StatusBadge(
                      label: 'Urgent', color: DesignColors.error, isActive: true),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                      'Buy ${suggestedQty.toStringAsFixed(0)} @ ${_currencyFmt.format(unitCost)}',
                      style: TextStyle(fontSize: 13, color: secondaryColor)),
                ),
                Text(_currencyFmt.format(estimatedCost),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push(
                  '/finance',
                  extra: RestockPrefill(
                    productName: productName,
                    quantity: suggestedQty,
                    unitCost: unitCost,
                  ),
                ),
                icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                label: const Text('Buy'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
