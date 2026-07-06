import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/clients/data/providers/clients_provider.dart';
import 'package:axon_pos/features/clients/data/models/pos_client.dart';

/// Multi-Client Dashboard Screen - Admin overview of all clients
class MultiClientDashboardScreen extends ConsumerStatefulWidget {
  const MultiClientDashboardScreen({super.key});

  @override
  ConsumerState<MultiClientDashboardScreen> createState() => _MultiClientDashboardScreenState();
}

class _MultiClientDashboardScreenState extends ConsumerState<MultiClientDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'all'; // all, active, trial, expired

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(dashboardSummaryProvider);
    final clients = ref.watch(clientsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter clients based on selection
    List<PosClient> getFilteredClients() {
      switch (_selectedFilter) {
        case 'active':
          return clients.where((c) => c.isActive && c.subscriptionStatus != 'expired').toList();
        case 'trial':
          return clients.where((c) => c.subscriptionStatus == 'trial').toList();
        case 'expired':
          return clients.where((c) => c.subscriptionStatus == 'expired').toList();
        default:
          return clients;
      }
    }

    final filteredClients = getFilteredClients();

    // Calculate revenue stats
    double calculateTotalRevenue() {
      double total = 0;
      for (final c in clients) {
        // Simplified: use branch count as revenue proxy
        total += c.branchCount * 100000;
      }
      return total;
    }

    final totalRevenue = calculateTotalRevenue();

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Multi-Client Dashboard',
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(Icons.filter_list_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('All Clients'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'active',
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: DesignColors.success),
                    SizedBox(width: 8),
                    Text('Active Only'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'trial',
                child: Row(
                  children: [
                    Icon(Icons.update_rounded, size: 18, color: DesignColors.accent),
                    SizedBox(width: 8),
                    Text('Trial Period'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'expired',
                child: Row(
                  children: [
                    Icon(Icons.error_rounded, size: 18, color: DesignColors.error),
                    SizedBox(width: 8),
                    Text('Expired'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab Bar
          Container(
            decoration: BoxDecoration(
              color: isDark ? DesignColors.darkSurface : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: DesignColors.brand,
              unselectedLabelColor: isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary,
              indicatorColor: DesignColors.brand,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Details'),
                Tab(text: 'Analysis'),
              ],
            ),
          ),
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Overview Tab
                _buildOverviewTab(summary, filteredClients, isDark),
                // Details Tab
                _buildDetailsTab(filteredClients, isDark),
                // Analysis Tab
                _buildAnalysisTab(clients, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(
    Map<String, dynamic> summary,
    List<PosClient> filteredClients,
    bool isDark,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          // Summary Cards
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: 'Total Clients',
                    value: '${summary['totalClients'] ?? 0}',
                    icon: Icons.business_outlined,
                    color: DesignColors.brand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    label: 'Active Subscriptions',
                    value: '${summary['activeSubscriptions'] ?? 0}',
                    icon: Icons.check_circle_rounded,
                    color: DesignColors.success,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: 'Trial Period',
                    value: '${summary['trialClients'] ?? 0}',
                    icon: Icons.update_rounded,
                    color: DesignColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    label: 'Expired',
                    value: '${summary['expiredClients'] ?? 0}',
                    icon: Icons.error_rounded,
                    color: DesignColors.error,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _SummaryCard(
              label: 'Total Revenue (Est)',
              value: 'KES ${summary['totalPendingPayments']?.toStringAsFixed(0) ?? '0'}',
              icon: Icons.attach_money_rounded,
              color: Colors.teal,
              largeValue: true,
            ),
          ),
          // Filter Results
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Text(
                  'Showing ${filteredClients.length} client(s)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Client List
          if (filteredClients.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: isDark ? DesignColors.darkSurfaceElevated : DesignColors.textTertiary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      size: 64,
                      color: isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No clients found',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            ...filteredClients.map((client) => _ClientComparisonRow(
              client: client,
              isDark: isDark,
              onTap: () {
                context.push('/clients/${client.id}');
              },
            )),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(List<PosClient> clients, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Client Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DetailRow(
                    label: 'Total Clients',
                    value: '${clients.length}',
                    isDark: isDark,
                  ),
                  _DetailRow(
                    label: 'Active Clients',
                    value: '${clients.where((c) => c.isActive).length}',
                    color: DesignColors.success,
                    isDark: isDark,
                  ),
                  _DetailRow(
                    label: 'Trial Clients',
                    value: '${clients.where((c) => c.subscriptionStatus == 'trial').length}',
                    color: DesignColors.accent,
                    isDark: isDark,
                  ),
                  _DetailRow(
                    label: 'Expired Clients',
                    value: '${clients.where((c) => c.subscriptionStatus == 'expired').length}',
                    color: DesignColors.error,
                    isDark: isDark,
                  ),
                  _DetailRow(
                    label: 'Total Branches',
                    value: '${clients.fold<int>(0, (sum, c) => sum + c.branchCount)}',
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Top Performing Clients',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
              ),
            ),
          ),
          ...clients.asMap().entries.map((entry) {
            final client = entry.value;
            return _ClientPerformanceRow(
              client: client,
              rank: entry.key + 1,
              isDark: isDark,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAnalysisTab(List<PosClient> clients, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          // Revenue Bar Chart
          _buildRevenueBarChart(clients),
          Padding(
            padding: const EdgeInsets.all(16),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subscription Status Distribution',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...[
                    {'label': 'Active', 'count': clients.where((c) => c.subscriptionStatus == 'active').length, 'color': DesignColors.success},
                    {'label': 'Trial', 'count': clients.where((c) => c.subscriptionStatus == 'trial').length, 'color': DesignColors.accent},
                    {'label': 'Expired', 'count': clients.where((c) => c.subscriptionStatus == 'expired').length, 'color': DesignColors.error},
                    {'label': 'Paused', 'count': clients.where((c) => c.subscriptionStatus == 'paused').length, 'color': DesignColors.textTertiary},
                  ].asMap().entries.map((entry) {
                    final item = entry.value;
                    final count = item['count'] as int;
                    final percentage = clients.isNotEmpty ? (count / clients.length) * 100 : 0;
                    return Padding(
                      padding: EdgeInsets.only(top: entry.key == 0 ? 0 : 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: item['color'] as Color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                item['label'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '$count (${percentage.toStringAsFixed(1)}%)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Container(
                              width: (percentage / 100) * 200,
                              decoration: BoxDecoration(
                                color: item['color'] as Color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Simple bar chart widget for revenue comparison
  Widget _buildRevenueBarChart(List<PosClient> clients) {
    if (clients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No clients to display',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).brightness == Brightness.dark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary,
            ),
          ),
        ),
      );
    }

    final maxRevenue = clients.fold<double>(0, (sum, c) => sum + c.branchCount * 100000);
    final displayClients = clients.take(6).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 160,
            child: Row(
              children: [
                ...displayClients.asMap().entries.map((entry) {
                  final client = entry.value;
                  final revenue = client.branchCount * 100000;
                  final percentage = maxRevenue > 0 ? (revenue / maxRevenue) * 100 : 0;

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: entry.key == 0 ? 0 : 8,
                        right: entry.key == displayClients.length - 1 ? 0 : 8,
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: (percentage / 100) * 120,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  DesignColors.brand.withValues(alpha: 0.8),
                                  DesignColors.brand.withValues(alpha: 0.4),
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(8),
                                bottom: Radius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(percentage / 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? DesignColors.darkTextTertiary
                                  : DesignColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Client Revenue Comparison',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).brightness == Brightness.dark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '(Based on branch count as proxy)',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).brightness == Brightness.dark
                  ? DesignColors.darkTextTertiary
                  : DesignColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool largeValue;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.largeValue = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: largeValue ? 24 : 20,
              fontWeight: FontWeight.w800,
              color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool isDark;

  const _DetailRow({
    required this.label,
    required this.value,
    this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color ?? (isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientComparisonRow extends StatelessWidget {
  final PosClient client;
  final bool isDark;
  final VoidCallback onTap;

  const _ClientComparisonRow({
    required this.client,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 16,
        child: Row(
          children: [
            // Client logo
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: DesignColors.brandSubtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: client.logoUrl != null && client.logoUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        client.logoUrl!,
                        fit: BoxFit.cover,
                        width: 48,
                        height: 48,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.business_rounded,
                          color: DesignColors.brand,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.business_rounded,
                      color: DesignColors.brand,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        client.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: DesignColors.textPrimary,
                        ),
                      ),
                      if (client.hasIssues)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: DesignColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.warning_rounded, size: 10, color: DesignColors.error),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (client.branchCount > 0)
                        Text(
                          '${client.branchCount} Branches',
                          style: TextStyle(
                            fontSize: 12,
                            color: DesignColors.textSecondary,
                          ),
                        ),
                      if (client.subscriptionStatus != null) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor(client.subscriptionStatus!).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            client.subscriptionStatus!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _getStatusColor(client.subscriptionStatus!),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (client.hasIssues)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DesignColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.warning_rounded, size: 18, color: DesignColors.error),
              ),
            IconButton(
              icon: Icon(Icons.chevron_right_rounded, color: DesignColors.textTertiary),
              onPressed: onTap,
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return DesignColors.success;
      case 'trial':
        return DesignColors.accent;
      case 'expired':
      case 'paused':
        return DesignColors.error;
      default:
        return DesignColors.textTertiary;
    }
  }
}

class _ClientPerformanceRow extends StatelessWidget {
  final PosClient client;
  final int rank;
  final bool isDark;

  const _ClientPerformanceRow({
    required this.client,
    required this.rank,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final estimatedRevenue = client.branchCount * 100000;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: rank <= 3
              ? DesignColors.brandSubtle.withValues(alpha: 0.3)
              : (isDark ? DesignColors.darkSurface : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: rank <= 3
                ? DesignColors.brand.withValues(alpha: 0.3)
                : (isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder),
          ),
        ),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: rank == 1
                    ? DesignColors.accentSubtle
                    : (rank == 2 ? DesignColors.textSecondary : DesignColors.textTertiary.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: rank == 1
                        ? DesignColors.accent
                        : (rank == 2 ? DesignColors.textPrimary : DesignColors.textTertiary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Client name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: DesignColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${client.branchCount} branches, ${client.activeBranches} active',
                    style: TextStyle(
                      fontSize: 12,
                      color: DesignColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Revenue
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'KES ${estimatedRevenue.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
                  ),
                ),
                Text(
                  'Est. Monthly',
                  style: TextStyle(
                    fontSize: 10,
                    color: DesignColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
