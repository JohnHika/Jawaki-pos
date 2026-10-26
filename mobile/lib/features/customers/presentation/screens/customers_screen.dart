import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/widgets/motion_kit_extras.dart';
import '../../../finance/domain/finance_models.dart';
import '../widgets/add_customer_sheet.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _overdueInstallments = [];
  bool _isLoading = true;
  String? _loadError;
  bool _showDebtOnly = false;
  final _searchController = TextEditingController();
  Timer? _serverBalanceDebounce;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadOverdue() async {
    try {
      final db = getIt<AppDatabase>();
      final overdue = await db.getOverdueInstallments();
      if (mounted) setState(() => _overdueInstallments = overdue);
    } catch (_) {
      // The overdue reminder is secondary; keep the customer list usable.
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _serverBalanceDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Use server receivables for customers known to the server, then add only
  /// local credit sales that are still waiting to sync. This lets a payment
  /// from another device clear stale local balances without hiding offline
  /// sales. Best effort: offline, the local figure stands.
  Future<List<Map<String, dynamic>>> _withServerBalances(
    List<Map<String, dynamic>> customers,
    String? query,
  ) async {
    try {
      final authService = getIt<AuthService>();
      final tenantId = authService.tenantId;
      final branchId = authService.branchId;
      if (tenantId == null || branchId == null) return customers;
      final api = getIt<ApiClient>();
      final results = await Future.wait<dynamic>([
        api.getRetailReceivables(branchId),
        api.getCustomers(),
        getIt<AppDatabase>().getUnsyncedCustomerDebtSales(branchId: branchId),
      ]);
      final receivables = results[0] as List<RetailReceivable>;
      final remoteCustomers = (results[1] as List<dynamic>)
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
      final unsyncedSales = results[2] as List<Map<String, dynamic>>;
      final db = getIt<AppDatabase>();
      if (authService.tenantId != tenantId ||
          authService.branchId != branchId) {
        return customers;
      }
      await db.upsertCustomersById(
        remoteCustomers,
        expectedTenantId: tenantId,
      );
      if (authService.tenantId != tenantId ||
          authService.branchId != branchId) {
        return customers;
      }
      final currentTenantCustomers = query != null && query.isNotEmpty
          ? await db.searchCustomers(query)
          : await db.getAllCustomers();
      final knownCustomerIds = remoteCustomers
          .map((customer) => customer['id']?.toString())
          .whereType<String>()
          .toSet();
      final owed = <String, double>{};
      final cloudReceipts = <String, Set<String>>{};
      for (final r in receivables) {
        final id = r.customerId;
        if (id == null) continue;
        final receipt = r.receiptNumber?.trim();
        if (receipt != null && receipt.isNotEmpty) {
          cloudReceipts.putIfAbsent(id, () => <String>{}).add(receipt);
        }
        if (r.outstandingAmount > 0) {
          owed[id] = (owed[id] ?? 0) + r.outstandingAmount;
        }
      }
      final pendingDebt = <String, double>{};
      for (final sale in unsyncedSales) {
        final id = sale['customerId']?.toString();
        if (id == null || !knownCustomerIds.contains(id)) continue;
        final receipt = sale['receiptNumber']?.toString().trim() ?? '';
        if (receipt.isNotEmpty &&
            (cloudReceipts[id]?.contains(receipt) ?? false)) {
          continue;
        }
        pendingDebt[id] = (pendingDebt[id] ?? 0) +
            ((sale['amount'] as num?)?.toDouble() ?? 0);
      }
      return currentTenantCustomers.map((c) {
        final id = c['id']?.toString();
        if (id == null || !knownCustomerIds.contains(id)) return c;
        return <String, dynamic>{
          ...c,
          'balance': (owed[id] ?? 0) + (pendingDebt[id] ?? 0),
        };
      }).toList();
    } catch (_) {
      return customers;
    }
  }

  /// Debt-only filtering and ordering, shared by the instant local render and
  /// the later server-balance refresh.
  List<Map<String, dynamic>> _applyDebtFilter(
      List<Map<String, dynamic>> customers) {
    if (!_showDebtOnly) return customers;
    return customers.where((c) => ((c['balance'] as num?) ?? 0) > 0).toList()
      ..sort((a, b) =>
          ((b['balance'] as num?) ?? 0).compareTo((a['balance'] as num?) ?? 0));
  }

  Future<void> _loadCustomers({String? query}) async {
    final normalizedQuery = query?.trim();
    final generation = ++_loadGeneration;
    _serverBalanceDebounce?.cancel();
    setState(() {
      // Keep the current results visible while the next local search runs.
      _isLoading = _customers.isEmpty;
      _loadError = null;
    });
    try {
      final db = getIt<AppDatabase>();
      final local = (normalizedQuery != null && normalizedQuery.isNotEmpty)
          ? await db.searchCustomers(normalizedQuery)
          : await db.getAllCustomers();
      // Show the phone's own list straight away. The server balances are
      // layered on afterwards: waiting for them here left the page on a
      // spinner for the whole network timeout whenever the phone was offline.
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _customers = _applyDebtFilter(local);
        _isLoading = false;
        _loadError = null;
      });
      if (normalizedQuery == null || normalizedQuery.isEmpty) {
        unawaited(_loadOverdue());
      }
      // Search runs on the local database immediately. Wait until typing stops
      // before requesting the same full server balance snapshot again.
      _serverBalanceDebounce = Timer(const Duration(milliseconds: 320), () {
        if (!mounted || generation != _loadGeneration) return;
        unawaited(_refreshServerBalances(local, normalizedQuery, generation));
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _loadError =
              "Couldn't read the saved customer list. Please try again.";
        });
      }
    }
  }

  Future<void> _refreshServerBalances(
    List<Map<String, dynamic>> local,
    String? query,
    int generation,
  ) async {
    final merged = await _withServerBalances(local, query)
        .timeout(const Duration(seconds: 6), onTimeout: () => local);
    // Ignore a late answer if the user has searched again meanwhile, even if
    // they later type the same query a second time.
    if (!mounted || generation != _loadGeneration || identical(merged, local)) {
      return;
    }
    setState(() => _customers = _applyDebtFilter(merged));
  }

  Future<void> _showAddCustomerSheet() async {
    final customer = await showAddCustomerSheet(
      context,
      customerSingular: ref.read(businessLayoutProvider).customerSingular,
    );
    if (customer == null || !mounted) return;
    _loadCustomers();
    showGlassSnackBar(
      context,
      '${customer.name} added',
      icon: Icons.check_circle_rounded,
      color: DesignColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final businessLayout = ref.watch(businessLayoutProvider);
    final customerSingular = businessLayout.customerSingular.toLowerCase();
    final customersLabel = businessLayout.customersLabel.toLowerCase();

    return Scaffold(
      appBar: BrandedAppBar(
        title: businessLayout.actionLabel('/customers', 'Customers'),
        showBackButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, size: 20),
            tooltip: 'Add ${businessLayout.customerSingular}',
            onPressed: _showAddCustomerSheet,
          ),
        ],
      ),
      body: PageContainer(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Overdue payments — who to follow up with today
            if (_overdueInstallments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    onTap: () {
                      setState(() => _showDebtOnly = true);
                      _loadCustomers();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: DesignColors.error.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        border: Border.all(
                            color: DesignColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_rounded,
                              color: DesignColors.error, size: 17),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_overdueInstallments.length} overdue payment${_overdueInstallments.length == 1 ? '' : 's'} — follow up today',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: DesignColors.error,
                                  ),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: DesignColors.error, size: 17),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: titleColor),
                decoration: InputDecoration(
                  hintText: 'Search $customersLabel...',
                  hintStyle: TextStyle(color: tertiaryColor),
                  filled: true,
                  fillColor: surface,
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 19, color: tertiaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: DesignColors.brand, width: 1.5),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear search',
                          icon:
                              Icon(Icons.clear, size: 18, color: tertiaryColor),
                          onPressed: () {
                            _searchController.clear();
                            _loadCustomers();
                          })
                      : null,
                ),
                onChanged: (v) {
                  setState(() {});
                  _loadCustomers(query: v);
                },
              ),
            ),
            // Filter: everyone vs. customers who owe money
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('All $customersLabel'),
                    visualDensity: VisualDensity.compact,
                    labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface),
                    selected: !_showDebtOnly,
                    onSelected: (_) {
                      setState(() => _showDebtOnly = false);
                      _loadCustomers();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Owes money'),
                    avatar: const Icon(Icons.account_balance_wallet_outlined,
                        size: 16),
                    visualDensity: VisualDensity.compact,
                    labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface),
                    selected: _showDebtOnly,
                    selectedColor: DesignColors.error.withValues(alpha: 0.15),
                    onSelected: (_) {
                      setState(() => _showDebtOnly = true);
                      _loadCustomers();
                    },
                  ),
                ],
              ),
            ),
            // Customer list
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: DesignColors.brand))
                  : _loadError != null
                      ? EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Couldn\'t load $customersLabel',
                          subtitle: _loadError!,
                          iconColor: DesignColors.error,
                          actionLabel: 'Retry',
                          onAction: () => _loadCustomers(
                              query: _searchController.text.trim()),
                        )
                      : _customers.isEmpty
                          ? EmptyState(
                              icon: Icons.people_outlined,
                              title: _showDebtOnly
                                  ? 'No customers owe money'
                                  : 'No ${businessLayout.customersLabel} yet',
                              subtitle: _showDebtOnly
                                  ? 'Everyone is paid up'
                                  : 'Add your first $customerSingular to get started',
                              actionIcon: Icons.person_add_alt_1_rounded,
                              actionLabel: _showDebtOnly
                                  ? null
                                  : 'Add ${businessLayout.customerSingular}',
                              onAction:
                                  _showDebtOnly ? null : _showAddCustomerSheet,
                            )
                          : RefreshIndicator(
                              onRefresh: () => _loadCustomers(),
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                itemCount: _customers.length,
                                itemBuilder: (context, index) {
                                  final c = _customers[index];
                                  final balance =
                                      (c['balance'] as num?)?.toDouble() ?? 0;
                                  return UnfoldIn(
                                      delay: Duration(
                                          milliseconds:
                                              40 * (index < 8 ? index : 8)),
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Material(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                              DesignSpacing.radiusMd),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                                DesignSpacing.radiusMd),
                                            onTap: () => context
                                                .push('/customers/${c['id']}'),
                                            child: Container(
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                color: surface,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        DesignSpacing.radiusMd),
                                                border: Border.all(
                                                  color: balance > 0
                                                      ? DesignColors.error
                                                          .withValues(
                                                              alpha: 0.35)
                                                      : border,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    backgroundColor:
                                                        DesignColors.brand
                                                            .withValues(
                                                                alpha: 0.15),
                                                    child: Text(
                                                      (c['name'] as String? ??
                                                              '?')[0]
                                                          .toUpperCase(),
                                                      style: const TextStyle(
                                                          color: DesignColors
                                                              .brand,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(c['name'] ?? '',
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.copyWith(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color:
                                                                      titleColor,
                                                                )),
                                                        if ((c['phone'] ?? '')
                                                            .toString()
                                                            .isNotEmpty)
                                                          Text(c['phone'],
                                                              style: Theme.of(
                                                                      context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    color:
                                                                        secondaryColor,
                                                                  )),
                                                        if ((c['location'] ??
                                                                '')
                                                            .toString()
                                                            .isNotEmpty)
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                  Icons
                                                                      .location_on_outlined,
                                                                  size: 11,
                                                                  color:
                                                                      tertiaryColor),
                                                              const SizedBox(
                                                                  width: 2),
                                                              Text(
                                                                  c['location'],
                                                                  style: Theme.of(
                                                                          context)
                                                                      .textTheme
                                                                      .labelSmall
                                                                      ?.copyWith(
                                                                        color:
                                                                            tertiaryColor,
                                                                      )),
                                                            ],
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      if (balance > 0)
                                                        Text(
                                                            'Owes ${formatMoney(balance)}',
                                                            style: DesignType
                                                                .numeric(
                                                              color:
                                                                  DesignColors
                                                                      .error,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ))
                                                      else
                                                        Text(
                                                            'KES ${(c['totalSpent'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                                            style: DesignType
                                                                .numeric(
                                                              color:
                                                                  DesignColors
                                                                      .brand,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            )),
                                                      Text(
                                                          '${c['totalPurchases'] ?? 0} purchases',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .labelSmall
                                                                  ?.copyWith(
                                                                    color:
                                                                        tertiaryColor,
                                                                  )),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ));
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
