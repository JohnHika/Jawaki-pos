import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/features/clients/data/providers/clients_provider.dart';
import 'package:axon_pos/features/clients/data/models/pos_client.dart';
import 'package:axon_pos/features/clients/data/models/branch.dart';

/// Client Detail Screen - Shows detailed client info and branch list
class ClientDetailScreen extends ConsumerStatefulWidget {
  final String clientId;
  const ClientDetailScreen({super.key, required this.clientId});

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    final client = clients.firstWhere((c) => c.id == widget.clientId);
    final branches = ref.watch(clientBranchesProvider);

    // Initialize branches with sample data
    ref.listen(clientBranchesProvider, (prev, next) {
      if (next.isEmpty) {
        _initializeSampleBranches(ref, client.id);
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Calculate stats
    final totalDevices = branches.fold<int>(0, (sum, b) => sum + b.deviceCount);
    final activeDevices = branches.fold<int>(0, (sum, b) => sum + b.activeDevices);
    final aiSubscriptions = branches.where((b) => b.hasAi).length;

    // Show add branch dialog
    void _showAddBranchDialog() {
      final nameCtrl = TextEditingController();
      final descriptionCtrl = TextEditingController();
      final addressCtrl = TextEditingController();
      final phoneCtrl = TextEditingController();
      final emailCtrl = TextEditingController();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
          title: const Text(
            'Add Branch',
            style: TextStyle(color: DesignColors.textPrimary, fontSize: 18),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320),
            child: ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Branch Name *',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;

                final branch = Branch(
                  id: 'branch-${DateTime.now().millisecondsSinceEpoch}',
                  clientId: client.id,
                  name: name,
                  description: descriptionCtrl.text.trim(),
                  address: addressCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                ref.read(clientDetailProvider.notifier).addBranch(branch);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Branch "$name" added successfully'),
                    backgroundColor: DesignColors.success,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: DesignColors.brand),
              child: const Text('Add Branch'),
            ),
          ],
        ),
      );
    }

    // Toggle branch active status
    void _toggleBranchActive(Branch branch) {
      ref.read(clientDetailProvider.notifier).updateBranch(
        branch.copyWith(
          isActive: !branch.isActive,
          updatedAt: DateTime.now(),
        ),
      );
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: client.name,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            onPressed: () {
              // Show QR code for this client
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Refresh data
        },
        child: PageContainer(
          withScroll: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Client Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 20,
                  child: Row(
                    children: [
                      // Client Logo
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: DesignColors.brandSubtle,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: client.logoUrl != null && client.logoUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  client.logoUrl!,
                                  fit: BoxFit.cover,
                                  width: 80,
                                  height: 80,
                                  errorBuilder: (context, error, stackTrace) => Icon(
                                    Icons.business_rounded,
                                    color: DesignColors.brand,
                                    size: 40,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.business_rounded,
                                color: DesignColors.brand,
                                size: 40,
                              ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  client.name,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: DesignColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(client.subscriptionStatus ?? 'active'),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    client.subscriptionStatus ?? 'N/A',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _getStatusTextColor(client.subscriptionStatus ?? 'active'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              client.slug,
                              style: TextStyle(
                                fontSize: 14,
                                color: DesignColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (client.hasIssues)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: DesignColors.error.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.warning_rounded, size: 14, color: DesignColors.error),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Issues',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: DesignColors.error,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (client.pendingPayments != null && client.pendingPayments! > 0) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: DesignColors.accentSubtle,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.attach_money_rounded, size: 14, color: DesignColors.accent),
                                        const SizedBox(width: 4),
                                        Text(
                                          'KES ${client.pendingPayments!.toStringAsFixed(0)} Due',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: DesignColors.accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Stats Row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Branches',
                        value: '${client.branchCount}',
                        icon: Icons.location_on_outlined,
                        color: DesignColors.brand,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Devices',
                        value: '$totalDevices',
                        icon: Icons.devices_other_outlined,
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Active',
                        value: '$activeDevices',
                        icon: Icons.toggle_on_outlined,
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
                      child: _StatCard(
                        label: 'AI Subscriptions',
                        value: '$aiSubscriptions',
                        icon: Icons.auto_awesome_rounded,
                        color: DesignColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Active Branches',
                        value: '${client.activeBranches}',
                        icon: Icons.check_circle_outlined,
                        color: DesignColors.success,
                      ),
                    ),
                    if (client.subscriptionExpiry != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: 'Expires',
                          value: client.subscriptionExpiry != null
                              ? client.subscriptionExpiry!.toLocal().toString().split(' ')[0]
                              : '-',
                          icon: Icons.calendar_today_outlined,
                          color: client.subscriptionExpiry != null && DateTime.now().isAfter(client.subscriptionExpiry!)
                              ? DesignColors.error
                              : DesignColors.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Quick Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showAddBranchDialog,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Branch'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Navigate to transactions
                        },
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('View Transactions'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DesignColors.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Branches List
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Text(
                      'Branches (${branches.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: DesignColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        // View all branches
                      },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('View All'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: branches.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: DesignColors.textTertiary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Icon(
                                Icons.business_outlined,
                                size: 64,
                                color: DesignColors.textTertiary.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No branches yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: DesignColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add a branch to start managing locations',
                              style: TextStyle(
                                fontSize: 14,
                                color: DesignColors.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _showAddBranchDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: DesignColors.brand,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Add First Branch'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: branches.length,
                        itemBuilder: (context, index) {
                          final branch = branches[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GlassCard(
                              padding: const EdgeInsets.all(16),
                              borderRadius: 16,
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      // Branch icon
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: DesignColors.brandSubtle,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.location_on_outlined,
                                          color: DesignColors.brand,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              branch.name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: DesignColors.textPrimary,
                                              ),
                                            ),
                                            if (branch.address != null && branch.address!.isNotEmpty)
                                              Text(
                                                branch.address!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: DesignColors.textSecondary,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      // Status toggle
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: branch.isActive ? DesignColors.successSubtle : DesignColors.textTertiary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              branch.isActive ? Icons.toggle_on : Icons.toggle_off,
                                              size: 16,
                                              color: branch.isActive ? DesignColors.success : DesignColors.textTertiary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              branch.isActive ? 'Active' : 'Inactive',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: branch.isActive ? DesignColors.success : DesignColors.textTertiary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // AI indicator
                                      if (branch.hasAi)
                                        Container(
                                          margin: const EdgeInsets.only(left: 12),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: DesignColors.accentSubtle,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.auto_awesome_rounded, size: 12, color: DesignColors.accent),
                                              const SizedBox(width: 4),
                                              Text(
                                                'AI',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: DesignColors.accent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      _BranchStatItem(
                                        label: 'Devices',
                                        value: '${branch.deviceCount}',
                                        icon: Icons.devices_other_outlined,
                                        active: branch.activeDevices > 0,
                                      ),
                                      if (branch.lastSync != null)
                                        _BranchStatItem(
                                          label: 'Last Sync',
                                          value: branch.lastSync!.substring(0, 16),
                                          icon: Icons.sync_rounded,
                                          active: true,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return DesignColors.successSubtle;
      case 'trial':
        return DesignColors.accentSubtle;
      case 'expired':
      case 'paused':
        return DesignColors.errorSubtle;
      default:
        return DesignColors.surfaceSubtle;
    }
  }

  Color _getStatusTextColor(String status) {
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

  void _initializeSampleBranches(WidgetRef ref, String clientId) {
    final now = DateTime.now();
    final sampleBranches = [
      Branch(
        id: 'branch-levisa-main',
        clientId: clientId,
        name: 'Main Branch',
        description: 'Headquarters and main operations',
        address: '123 Kilimani Road, Nairobi',
        phone: '+254 700 123 456',
        email: 'info@levisa.co.ke',
        isActive: true,
        deviceCount: 8,
        activeDevices: 6,
        lastSync: now.toIso8601String(),
        hasAi: true,
        createdAt: now.subtract(const Duration(days: 365)),
        updatedAt: now,
      ),
      Branch(
        id: 'branch-levisa-west',
        clientId: clientId,
        name: 'Westlands Branch',
        description: 'Retail location',
        address: '45 Westlands Road, Nairobi',
        phone: '+254 700 123 457',
        email: 'westlands@levisa.co.ke',
        isActive: true,
        deviceCount: 4,
        activeDevices: 4,
        lastSync: now.toIso8601String(),
        hasAi: true,
        createdAt: now.subtract(const Duration(days: 200)),
        updatedAt: now,
      ),
      Branch(
        id: 'branch-levisa-mombasa',
        clientId: clientId,
        name: 'Mombasa Branch',
        description: 'Coastal operations',
        address: '78 Moi Avenue, Mombasa',
        phone: '+254 700 123 458',
        email: 'mombasa@levisa.co.ke',
        isActive: true,
        deviceCount: 6,
        activeDevices: 5,
        lastSync: now.toIso8601String(),
        hasAi: false,
        createdAt: now.subtract(const Duration(days: 100)),
        updatedAt: now,
      ),
    ];

    ref.read(clientDetailProvider.notifier).setBranches(sampleBranches);
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchStatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool active;

  const _BranchStatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? DesignColors.successSubtle : DesignColors.textTertiary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: active ? DesignColors.success : DesignColors.textTertiary),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? DesignColors.success : DesignColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
