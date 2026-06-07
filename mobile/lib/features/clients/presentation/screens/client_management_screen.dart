import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:levisa_adventures_pos/core/theme/design_system.dart';
import 'package:levisa_adventures_pos/features/clients/data/providers/clients_provider.dart';
import 'package:levisa_adventures_pos/features/clients/data/models/pos_client.dart';

/// Client Management Screen - List and manage all Axon POS clients
class ClientManagementScreen extends ConsumerWidget {
  const ClientManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);
    final clientsWithIssues = ref.watch(clientsWithIssuesCounterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Initialize with sample data if empty
    ref.listen(clientsProvider, (prev, next) {
      if (prev != null && prev.isEmpty && next.isEmpty) {
        _initializeSampleData(ref);
      }
    });

    // Show add client dialog
    void _showAddClientDialog() {
      final nameCtrl = TextEditingController();
      final slugCtrl = TextEditingController();
      final logoUrlCtrl = TextEditingController();

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
          title: const Text(
            'Add New Client',
            style: TextStyle(color: DesignColors.textPrimary, fontSize: 18),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Client Name *',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: slugCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Slug *',
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                  onChanged: (value) {
                    // Auto-generate slug from name
                    if (slugCtrl.text.isEmpty) {
                      slugCtrl.text = value
                          .toLowerCase()
                          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
                          .replaceAll(RegExp(r'^-+|-+$'), '');
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: logoUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Logo URL (optional)',
                    prefixIcon: Icon(Icons.image_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final slug = slugCtrl.text.trim();
                if (name.isEmpty || slug.isEmpty) return;

                final client = PosClient(
                  id: 'client-${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  slug: slug,
                  logoUrl: logoUrlCtrl.text.trim().isEmpty ? null : logoUrlCtrl.text.trim(),
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                ref.read(clientsProvider.notifier).addClient(client);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text('Client "$name" added successfully'),
                    backgroundColor: DesignColors.success,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: DesignColors.brand),
              child: const Text('Add Client'),
            ),
          ],
        ),
      );
    }

    // Show edit client dialog
    void _showEditClientDialog(PosClient client) {
      final nameCtrl = TextEditingController(text: client.name);
      final slugCtrl = TextEditingController(text: client.slug);
      final logoUrlCtrl = TextEditingController(text: client.logoUrl ?? '');

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
          title: const Text(
            'Edit Client',
            style: TextStyle(color: DesignColors.textPrimary, fontSize: 18),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Client Name *',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: slugCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Slug *',
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: logoUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Logo URL (optional)',
                    prefixIcon: Icon(Icons.image_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final slug = slugCtrl.text.trim();
                if (name.isEmpty || slug.isEmpty) return;

                ref.read(clientsProvider.notifier).updateClient(
                  client.copyWith(
                    name: name,
                    slug: slug,
                    logoUrl: logoUrlCtrl.text.trim().isEmpty ? null : logoUrlCtrl.text.trim(),
                    updatedAt: DateTime.now(),
                  ),
                );
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text('Client "$name" updated successfully'),
                    backgroundColor: DesignColors.success,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: DesignColors.brand),
              child: const Text('Update Client'),
            ),
          ],
        ),
      );
    }

    // Toggle active status
    void _toggleActive(String clientId) {
      ref.read(clientsProvider.notifier).toggleClientActive(clientId);
    }

    // Delete client
    void _deleteClient(PosClient client) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
          title: const Text('Delete Client'),
          content: Text('Are you sure you want to delete "${client.name}"? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(clientsProvider.notifier).deleteClient(client.id);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text('Client "${client.name}" deleted'),
                    backgroundColor: DesignColors.error,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: DesignColors.error),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }

    // Show client details
    void _showClientDetails(PosClient client) {
      ref.read(selectedClientProvider.notifier).state = client;
      context.push('/clients/${client.id}');
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Client Management',
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: clientsWithIssues > 0,
              label: Text('$clientsWithIssues'),
              backgroundColor: DesignColors.error,
              child: const Icon(Icons.warning_outlined),
            ),
            onPressed: () {
              if (clientsWithIssues > 0) {
                _showIssuesSheet(ref, clients, context);
              }
            },
          ),
        ],
      ),
      body: PageContainer(
        child: Column(
          children: [
            // Stats Row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: GlassCard(
                      padding: const EdgeInsets.all(12),
                      borderRadius: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${clients.length}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: DesignColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Total Clients',
                            style: TextStyle(
                              fontSize: 12,
                              color: DesignColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassCard(
                      padding: const EdgeInsets.all(12),
                      borderRadius: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${clients.where((c) => c.isActive).length}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: DesignColors.success,
                            ),
                          ),
                          Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 12,
                              color: DesignColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Search and Filter
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                borderRadius: 12,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search clients...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.filter_list, size: 20),
                      onPressed: () {
                        _showFilterSheet(context);
                      },
                    ),
                  ),
                  onChanged: (value) {
                    // Filter would be implemented here
                  },
                ),
              ),
            ),
            // Client List
            Expanded(
              child: _buildClientList(ref, clients, _showClientDetails, _toggleActive, _deleteClient, _showEditClientDialog, isDark),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddClientDialog,
        backgroundColor: DesignColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Client'),
      ),
    );
  }

  Widget _buildClientList(
    WidgetRef ref,
    List<PosClient> clients,
    Function(PosClient) onClientTap,
    Function(String) onToggleActive,
    Function(PosClient) onDelete,
    Function(PosClient) onEdit,
    bool isDark,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: clients.length,
      itemBuilder: (context, index) {
        final client = clients[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 16,
            onTap: () => onClientTap(client),
            child: Column(
              children: [
                Row(
                  children: [
                    // Logo placeholder
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
                                errorBuilder: (ctx, error, stackTrace) => Icon(
                                  Icons.business_rounded,
                                  color: DesignColors.brand,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.business_rounded,
                              color: DesignColors.brand,
                              size: 24,
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.warning_rounded, size: 10, color: DesignColors.error),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Issue',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: DesignColors.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ' Slug: ${client.slug}',
                            style: TextStyle(
                              fontSize: 12,
                              color: DesignColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (client.branchCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: DesignColors.brandSubtle,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_on_outlined, size: 12, color: DesignColors.brand),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${client.branchCount} Branch${client.branchCount > 1 ? 'es' : ''}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: DesignColors.brand,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (client.subscriptionStatus != null)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(client.subscriptionStatus!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    client.subscriptionStatus!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _getStatusTextColor(client.subscriptionStatus!),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Status toggle
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: client.isActive ? DesignColors.successSubtle : DesignColors.textTertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            client.isActive ? Icons.toggle_on : Icons.toggle_off,
                            size: 16,
                            color: client.isActive ? DesignColors.success : DesignColors.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            client.isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: client.isActive ? DesignColors.success : DesignColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Menu
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          onEdit(client);
                        } else if (value == 'delete') {
                          onDelete(client);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Edit Client'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18, color: DesignColors.error),
                              SizedBox(width: 8),
                              Text('Delete Client', style: TextStyle(color: DesignColors.error)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (client.hasIssues) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      color: DesignColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DesignColors.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_rounded, size: 16, color: DesignColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            client.subscriptionStatus == 'trial' && client.subscriptionExpiry != null
                                ? 'Trial expired on ${client.subscriptionExpiry!.toLocal().toString().split(' ')[0]}'
                                : 'Has pending payments: \$${client.pendingPayments?.toStringAsFixed(2) ?? '0.00'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: DesignColors.error,
                            ),
                          ),
                        ),
                        if (client.pendingPayments != null && client.pendingPayments! > 0)
                          ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Process payment for ${client.name}'),
                                  backgroundColor: DesignColors.brand,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: DesignColors.brand,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: const Text('Pay Now'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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

  void _showFilterSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (dialogContext) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(dialogContext).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: isDark ? DesignColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 28,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter Clients',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              _FilterChip(
                label: 'All Clients',
                isSelected: true,
                onSelected: (selected) {},
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _FilterChip(
                label: 'Active Only',
                isSelected: false,
                onSelected: (selected) {},
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _FilterChip(
                label: 'With Issues',
                isSelected: false,
                onSelected: (selected) {},
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _FilterChip(
                label: 'Expired Trial',
                isSelected: false,
                onSelected: (selected) {},
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showIssuesSheet(WidgetRef ref, List<PosClient> clients, BuildContext context) {
    final issuesClients = clients.where((c) => c.hasIssues).toList();
    if (issuesClients.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (dialogContext) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(dialogContext).padding.bottom + 16),
        decoration: BoxDecoration(
          color: Theme.of(dialogContext).brightness == Brightness.dark
              ? DesignColors.darkSurface
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clients with Issues (${issuesClients.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DesignColors.error,
                ),
              ),
              const SizedBox(height: 16),
              ...issuesClients.map((client) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  padding: const EdgeInsets.all(12),
                  borderRadius: 12,
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: DesignColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.warning_rounded,
                          color: DesignColors.error,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              client.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: DesignColors.textPrimary,
                              ),
                            ),
                            Text(
                              client.subscriptionStatus == 'trial' && client.subscriptionExpiry != null
                                  ? 'Trial expired on ${client.subscriptionExpiry!.toLocal().toString().split(' ')[0]}'
                                  : 'Pending payment: \$${client.pendingPayments?.toStringAsFixed(2) ?? '0.00'}',
                              style: TextStyle(
                                fontSize: 11,
                                color: DesignColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          // Navigate to payment or resolve
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DesignColors.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('Resolve'),
                      ),
                    ],
                  ),
                ),
              )),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  // Show all issues in a list view
                },
                child: Text(
                  'View All Issues',
                  style: TextStyle(color: DesignColors.brand),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _initializeSampleData(WidgetRef ref) {
    final now = DateTime.now();
    final sampleClients = [
      PosClient(
        id: 'client-levisa',
        name: 'Arche Axon Intelligence',
        slug: 'axon',
        isActive: true,
        branchCount: 3,
        activeBranches: 3,
        subscriptionStatus: 'active',
        createdAt: now.subtract(const Duration(days: 365)),
        updatedAt: now,
      ),
      PosClient(
        id: 'client-tsl',
        name: 'TSL Limited',
        slug: 'tsl',
        isActive: true,
        branchCount: 2,
        activeBranches: 2,
        subscriptionStatus: 'active',
        createdAt: now.subtract(const Duration(days: 180)),
        updatedAt: now,
      ),
      PosClient(
        id: 'client-kate',
        name: 'Kate Boutique',
        slug: 'kate',
        isActive: false,
        branchCount: 1,
        activeBranches: 0,
        subscriptionStatus: 'expired',
        subscriptionExpiry: now.subtract(const Duration(days: 30)),
        pendingPayments: 5000.0,
        createdAt: now.subtract(const Duration(days: 90)),
        updatedAt: now,
      ),
      PosClient(
        id: 'client-moringa',
        name: 'Moringa Retail',
        slug: 'moringa',
        isActive: true,
        branchCount: 5,
        activeBranches: 4,
        subscriptionStatus: 'trial',
        subscriptionExpiry: now.add(const Duration(days: 15)),
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now,
      ),
      PosClient(
        id: 'client-bamburi',
        name: 'Bamburi Sports',
        slug: 'bamburi',
        isActive: true,
        branchCount: 2,
        activeBranches: 2,
        subscriptionStatus: 'trial',
        subscriptionExpiry: now.add(const Duration(days: 5)),
        createdAt: now.subtract(const Duration(days: 14)),
        updatedAt: now,
      ),
    ];

    ref.read(clientsProvider.notifier).state = sampleClients;
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Function(bool) onSelected;
  final bool isDark;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        onSelected(selected);
      },
      backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
      selectedColor: DesignColors.brand.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? DesignColors.brand : (isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? DesignColors.brand : (isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder),
        ),
      ),
    );
  }
}
