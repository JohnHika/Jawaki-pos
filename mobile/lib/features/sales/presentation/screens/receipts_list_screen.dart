import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';

/// Receipts List Screen - Shows all sales/receipts from the local database
class ReceiptsListScreen extends ConsumerStatefulWidget {
  const ReceiptsListScreen({super.key});

  @override
  ConsumerState<ReceiptsListScreen> createState() => _ReceiptsListScreenState();
}

class _ReceiptsListScreenState extends ConsumerState<ReceiptsListScreen> {
  late final AppDatabase _db;
  List<PendingSale> _sales = [];
  bool _isLoading = true;
  String? _error;
  int? _rangeDays = 30;

  @override
  void initState() {
    super.initState();
    _db = getIt<AppDatabase>();
    _loadSales();
  }

  Future<void> _loadSales() async {
    try {
      final now = DateTime.now();
      final from = _rangeDays == null
          ? DateTime(2000)
          : now.subtract(Duration(days: _rangeDays!));
      final sales = await _db.getSalesByDateRange(from, now);
      if (mounted) {
        setState(() {
          _sales = sales;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _formatCurrency(double amount) {
    return 'KES ${amount.toStringAsFixed(0)}';
  }

  Color _paymentMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'CASH':
        return DesignColors.cash;
      case 'MPESA':
        return DesignColors.mpesa;
      case 'CARD':
      case 'CREDIT':
        return DesignColors.credit;
      case 'PESAPAL':
        return DesignColors.pesapal;
      case 'TOURISTTAP':
      case 'TOURIST TAP':
        return DesignColors.touristtap;
      default:
        return DesignColors.brand;
    }
  }

  IconData _paymentMethodIcon(String method) {
    switch (method.toUpperCase()) {
      case 'CASH':
        return Icons.money_rounded;
      case 'MPESA':
        return Icons.phone_android_rounded;
      case 'CARD':
      case 'CREDIT':
        return Icons.credit_card_rounded;
      case 'PESAPAL':
        return Icons.payments_rounded;
      case 'TOURISTTAP':
      case 'TOURIST TAP':
        return Icons.nfc_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Receipts',
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () => _showFilterSheet(context),
            tooltip: 'Filter receipts',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: DesignColors.accent))
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Couldn\'t load receipts',
                  subtitle: 'Check your connection and try again.',
                  actionLabel: 'Retry',
                  iconColor: DesignColors.error,
                  onAction: () {
                    setState(() {
                      _isLoading = true;
                    });
                    _loadSales();
                  },
                )
              : _sales.isEmpty
                  ? EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'No Receipts Yet',
                      subtitle: 'Completed sales will appear here',
                      actionLabel: 'Refresh',
                      onAction: () {
                        setState(() {
                          _isLoading = true;
                        });
                        _loadSales();
                      },
                    )
                  : RefreshIndicator(
                      color: DesignColors.accent,
                      onRefresh: _loadSales,
                      child: PageContainer(
                        withScroll: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionHeader(
                              title: 'Recent Receipts',
                              subtitle:
                                  '${_sales.length} receipt${_sales.length != 1 ? 's' : ''} ${_rangeLabel.toLowerCase()}',
                              icon: Icons.receipt_long_rounded,
                            ),
                            const SizedBox(height: 8),
                            ..._sales
                                .map((sale) => _buildReceiptCard(sale, isDark)),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
    );
  }

  String get _rangeLabel {
    if (_rangeDays == null) return 'All time';
    if (_rangeDays == 7) return 'Last 7 days';
    if (_rangeDays == 30) return 'Last 30 days';
    if (_rangeDays == 90) return 'Last 90 days';
    return 'Last $_rangeDays days';
  }

  void _showFilterSheet(BuildContext context) {
    final options = <String, int?>{
      'Last 7 days': 7,
      'Last 30 days': 30,
      'Last 90 days': 90,
      'All time': null,
    };

    GlassBottomSheet.show(
      context,
      title: 'Filter receipts',
      initialSize: 0.35,
      maxSize: 0.6,
      scrollable: true,
      child: Builder(builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final tertiaryColor = isDark
            ? DesignColors.darkTextTertiary
            : DesignColors.textTertiary;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.entries.map((entry) {
              final selected = entry.value == _rangeDays;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? DesignColors.accent : tertiaryColor,
                ),
                title: Text(entry.key),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _rangeDays = entry.value;
                    _isLoading = true;
                  });
                  _loadSales();
                },
              );
            }).toList(),
          ),
        );
      }),
    );
  }

  Widget _buildReceiptCard(PendingSale sale, bool isDark) {
    final receiptNumber = sale.id.length >= 8
        ? sale.id.substring(0, 8).toUpperCase()
        : sale.id.toUpperCase();
    final methodColor = _paymentMethodColor(sale.paymentMethod);
    final methodIcon = _paymentMethodIcon(sale.paymentMethod);
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => context.go('/receipt/${sale.id}'),
        padding: const EdgeInsets.all(14),
        borderRadius: 14,
        blur: 10,
        tint: Colors.transparent,
        borderColor: border,
        child: Row(
          children: [
            // Leading icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: methodColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(methodIcon, color: methodColor, size: 22),
            ),
            const SizedBox(width: 12),

            // Middle content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#$receiptNumber',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PaymentChip(method: _capitalize(sale.paymentMethod)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: tertiaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDateTime(sale.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: tertiaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Trailing: total amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatCurrency(sale.total),
                  style: DesignType.numeric(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  color: tertiaryColor,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1).toLowerCase();
  }
}
