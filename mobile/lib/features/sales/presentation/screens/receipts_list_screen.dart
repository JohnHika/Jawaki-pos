import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/load_error.dart';
import '../../../../core/widgets/motion.dart';
import '../../domain/receipt_search.dart';
import '../../../../core/utils/format.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/sales_provider.dart';
import '../receipts_desktop/desktop_receipt_inspector.dart';
import '../receipts_desktop/desktop_receipts_view.dart';
import '../receipts_desktop/receipt_thermal_text.dart';
import 'receipt_screen.dart';

/// Receipts List Screen - Shows all sales/receipts from the local database
class ReceiptsListScreen extends ConsumerStatefulWidget {
  const ReceiptsListScreen({super.key});

  @override
  ConsumerState<ReceiptsListScreen> createState() => _ReceiptsListScreenState();
}

class _ReceiptsListScreenState extends ConsumerState<ReceiptsListScreen> {
  late final AppDatabase _db;
  List<PendingSale> _sales = [];
  Map<String, Map<String, dynamic>> _customersById = {};
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _isLoading = true;
  String? _error;
  int? _rangeDays = 30;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _db = getIt<AppDatabase>();
    _loadSales();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Sales matching the search box (receipt code, customer name or phone).
  List<PendingSale> get _visibleSales {
    final canViewCustomerDetails =
        ref.read(permissionsProvider).canSeeCustomers;
    if (_query.trim().isEmpty) return _sales;
    return _sales.where((sale) {
      final customer =
          canViewCustomerDetails ? _customersById[sale.customerId] : null;
      return receiptMatchesQuery(
        saleId: sale.id,
        receiptNumber: sale.receiptNumber,
        paymentMethod: sale.paymentMethod,
        customerName: customer?['name']?.toString(),
        customerPhone: customer?['phone']?.toString(),
        query: _query,
      );
    }).toList();
  }

  Future<void> _loadSales() async {
    final generation = ++_loadGeneration;
    try {
      final now = DateTime.now();
      final from = _rangeDays == null
          ? DateTime(2000)
          : _rangeDays == 0
              ? DateTime(now.year, now.month, now.day)
              : now.subtract(Duration(days: _rangeDays!));
      final sales = await _db.getSalesByDateRange(from, now);
      if (!mounted || generation != _loadGeneration) return;
      final canViewCustomerDetails =
          ref.read(permissionsProvider).canSeeCustomers;
      // Customer names only enrich the list; never fail receipts over them.
      var customers = <String, Map<String, dynamic>>{};
      if (canViewCustomerDetails) {
        try {
          final rows = await _db.getAllCustomers();
          if (!mounted ||
              generation != _loadGeneration ||
              !ref.read(permissionsProvider).canSeeCustomers) {
            return;
          }
          customers = {for (final c in rows) c['id'].toString(): c};
        } catch (_) {}
      }
      if (mounted && generation == _loadGeneration) {
        if (!ref.read(permissionsProvider).canSeeCustomers) customers = {};
        setState(() {
          _sales = sales;
          _customersById = canViewCustomerDetails ? customers : {};
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _error = loadErrorSubtitle(e);
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
    return formatMoney(amount);
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
      case 'MPESA_RECORDED':
      case 'BANK_RECORDED':
        return DesignColors.warning;
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
      case 'MPESA_RECORDED':
        return Icons.phone_android_rounded;
      case 'BANK_RECORDED':
        return Icons.account_balance_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canViewCustomerDetails =
        ref.watch(permissionsProvider).canSeeCustomers;
    ref.listen(permissionsProvider, (previous, next) {
      if (previous?.canSeeCustomers != next.canSeeCustomers) {
        final wasLoading = _isLoading;
        _loadGeneration++;
        setState(() {
          _customersById = {};
        });
        if (wasLoading || next.canSeeCustomers) _loadSales();
      }
    });
    final pageTitle =
        ref.watch(businessLayoutProvider).actionLabel('/receipts', 'Receipts');
    if (context.inDesktopShell) {
      return _buildDesktop(pageTitle, canViewCustomerDetails);
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: pageTitle,
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
                  subtitle: _error!,
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
                              subtitle: _query.trim().isEmpty
                                  ? '${_sales.length} receipt${_sales.length != 1 ? 's' : ''} ${_rangeLabel.toLowerCase()}'
                                  : '${_visibleSales.length} of ${_sales.length} match “${_query.trim()}”',
                              icon: Icons.receipt_long_rounded,
                            ),
                            const SizedBox(height: DesignSpacing.sm),
                            TextField(
                              key: const ValueKey('receipt-search'),
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              decoration: InputDecoration(
                                hintText: canViewCustomerDetails
                                    ? 'Search receipt, customer or phone'
                                    : 'Search receipt or payment',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _query = '');
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(height: DesignSpacing.md),
                            if (_visibleSales.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: DesignSpacing.xl),
                                child: Center(
                                  child: Text('No receipts match your search.',
                                      key: ValueKey('receipt-search-empty')),
                                ),
                              ),
                            // First-mount entrance stagger with stable
                            // per-sale keys - pull-to-refresh never replays
                            // the choreography.
                            ..._visibleSales.asMap().entries.map((entry) {
                              final index = entry.key;
                              final sale = entry.value;
                              return StaggeredItem(
                                key: ValueKey('receipt-${sale.id}'),
                                itemKey: 'receipt-${sale.id}',
                                index: index,
                                child: _buildReceiptCard(
                                  sale,
                                  isDark,
                                  canViewCustomerDetails,
                                ),
                              );
                            }),
                            const SizedBox(height: DesignSpacing.xxl),
                          ],
                        ),
                      ),
                    ),
    );
  }

  void _reload() {
    setState(() => _isLoading = true);
    _loadSales();
  }

  Widget _buildDesktop(String pageTitle, bool canViewCustomerDetails) {
    final names = <String, String>{};
    final phones = <String, String>{};
    if (canViewCustomerDetails) {
      _customersById.forEach((id, c) {
        final name = c['name']?.toString() ?? '';
        if (name.isNotEmpty) names[id] = name;
        final phone = c['phone']?.toString() ?? '';
        if (phone.isNotEmpty) phones[id] = phone;
      });
    }
    // A sale stores who rang it up by id only. This computer knows the name of
    // the person signed in, so that is the one it can show.
    final cashiers = <String, String>{};
    try {
      final auth = getIt<AuthService>();
      final id = auth.userId;
      final name = auth.currentUser?['name']?.toString() ?? '';
      if (id != null && name.isNotEmpty) cashiers[id] = name;
    } catch (_) {}

    return Scaffold(
      body: DesktopReceiptsView(
        title: pageTitle,
        sales: _sales,
        canViewCustomerDetails: canViewCustomerDetails,
        loading: _isLoading,
        errorMessage: _error,
        onRetry: _reload,
        onRefresh: _reload,
        rangeDays: _rangeDays,
        onRangeChanged: (days) {
          setState(() {
            _rangeDays = days;
            _isLoading = true;
          });
          _loadSales();
        },
        customerNames: names,
        customerPhones: phones,
        cashierNames: cashiers,
        onOpen: (sale) => context.go('/receipt/${sale.id}'),
        onPrint: _printSale,
        inspectorBuilder: (context, sale, close) => _ReceiptInspectorHost(
          sale: sale,
          onClose: close,
          onChanged: _loadSales,
        ),
      ),
    );
  }

  /// Ctrl+P on the picked row: the same print flow the receipt page uses.
  Future<void> _printSale(PendingSale sale) async {
    try {
      final receipt = receiptForCustomerVisibility(
        await ref.read(receiptProvider(sale.id).future),
        canViewCustomerDetails: ref.read(permissionsProvider).canSeeCustomers,
      );
      if (!mounted) return;
      await ReceiptScreen(saleId: sale.id).printReceipt(context, ref, receipt);
    } catch (_) {
      // The inspector already says why a receipt could not load.
    }
  }

  String get _rangeLabel {
    if (_rangeDays == null) return 'All time';
    if (_rangeDays == 0) return 'Today';
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
        final tertiaryColor =
            isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
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

  Widget _buildReceiptCard(
    PendingSale sale,
    bool isDark,
    bool canViewCustomerDetails,
  ) {
    final customer =
        canViewCustomerDetails ? _customersById[sale.customerId] : null;
    // Show the same number the receipt, dashboard and reports use.
    final receiptNumber = sale.receiptNumber.trim().isNotEmpty
        ? sale.receiptNumber
        : (sale.id.length >= 8
            ? sale.id.substring(0, 8).toUpperCase()
            : sale.id.toUpperCase());
    final methodColor = _paymentMethodColor(sale.paymentMethod);
    final methodIcon = _paymentMethodIcon(sale.paymentMethod);
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.md - 2),
      child: GlassCard(
        onTap: () => context.go('/receipt/${sale.id}'),
        padding: const EdgeInsets.all(DesignSpacing.md + 2),
        borderRadius: DesignSpacing.radiusMd + 2,
        blur: 10,
        tint: Colors.transparent,
        borderColor: border,
        child: Row(
          children: [
            // Leading icon
            Container(
              padding: const EdgeInsets.all(DesignSpacing.md - 2),
              decoration: BoxDecoration(
                color: methodColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              ),
              child: Icon(methodIcon, color: methodColor, size: 22),
            ),
            const SizedBox(width: DesignSpacing.md),

            // Middle content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#$receiptNumber',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: DesignType.chatBody,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignSpacing.sm),
                      PaymentChip(
                          method: paymentMethodLabel(sale.paymentMethod),
                          compact: true),
                    ],
                  ),
                  if (customer?['name'] != null &&
                      customer!['name'].toString().isNotEmpty) ...[
                    const SizedBox(height: DesignSpacing.xs - 2),
                    Text(
                      customer['name'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesignType.chatSecondary,
                        color: titleColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: DesignSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: tertiaryColor,
                      ),
                      const SizedBox(width: DesignSpacing.xs),
                      Expanded(
                        child: Text(
                          _formatDateTime(sale.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: DesignType.chatSecondary,
                            color: tertiaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Trailing: total amount
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 124),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatCurrency(sale.total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: DesignType.numeric(
                      fontSize: DesignType.chatBody + 1,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.xs - 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: tertiaryColor,
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The receipt inspector wired to the real receipt: it watches the provider the
/// receipt page uses and reuses that page's print, share and void handlers.
class _ReceiptInspectorHost extends ConsumerWidget {
  const _ReceiptInspectorHost({
    required this.sale,
    required this.onClose,
    required this.onChanged,
  });

  final PendingSale sale;
  final VoidCallback onClose;

  /// A receipt changed (voided): reload the table.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receiptProvider(sale.id));
    final rawReceipt = async.valueOrNull;
    final canViewCustomerDetails =
        ref.watch(permissionsProvider).canSeeCustomers;
    final receipt = rawReceipt == null
        ? null
        : receiptForCustomerVisibility(
            rawReceipt,
            canViewCustomerDetails: canViewCustomerDetails,
          );
    final error = receipt == null ? async.error : null;
    final handlers = ReceiptScreen(saleId: sale.id);
    var local = false;
    try {
      local = getIt<AuthService>().isLocalWorkspace;
    } catch (_) {}
    return DesktopReceiptInspector(
      receipt: receipt,
      loading: async.isLoading,
      errorMessage: error == null
          ? null
          : error is StateError
              ? error.message.toString()
              : loadErrorSubtitle(error),
      onRetry: error == null || error is StateError
          ? null
          : () => ref.invalidate(receiptProvider(sale.id)),
      fallbackNumber: sale.id.length >= 8
          ? sale.id.substring(0, 8).toUpperCase()
          : sale.id.toUpperCase(),
      showTax: receiptShowsTax(),
      waitingToSync: !local && !sale.isSynced,
      canVoid: ref.watch(permissionsProvider).canVoidSales,
      onClose: onClose,
      onOpen: () => context.go('/receipt/${sale.id}'),
      onPrint: () => handlers.printReceipt(context, ref, receipt),
      onShare: () => handlers.shareReceipt(context, ref, receipt),
      onVoid: receipt == null
          ? null
          : () async {
              await handlers.voidSale(context, ref, receipt);
              onChanged();
            },
    );
  }
}
