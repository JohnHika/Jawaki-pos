import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers({String? query}) async {
    setState(() => _isLoading = true);
    try {
      final db = getIt<AppDatabase>();
      final customers = (query != null && query.isNotEmpty)
          ? await db.searchCustomers(query)
          : await db.getAllCustomers();
      if (mounted) setState(() { _customers = customers; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Show add customer bottom sheet
  void _showAddCustomerSheet() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final sheetChild = Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add Customer',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: DesignColors.textPrimary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Customer Name *', prefixIcon: Icon(Icons.person_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined)),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailCtrl,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesCtrl,
            decoration: const InputDecoration(labelText: 'Notes', prefixIcon: Icon(Icons.notes_rounded)),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: 'Save Customer',
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final db = getIt<AppDatabase>();
              await db.insertOrGetCustomer(
                DateTime.now().millisecondsSinceEpoch.toString(),
                nameCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
              _loadCustomers();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );

    GlassBottomSheet.show(context, child: sheetChild);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        centerTitle: false,
        backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        elevation: 0,
      ),
      body: PageContainer(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                borderRadius: 12,
                tint: Colors.transparent,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search customers...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: InputBorder.none,
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); _loadCustomers(); })
                        : null,
                  ),
                  onChanged: (v) {
                    setState(() {});
                    _loadCustomers(query: v);
                  },
                ),
              ),
            ),
            // Customer list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: DesignColors.brand))
                  : _customers.isEmpty
                      ? EmptyState(
                          icon: Icons.people_outlined,
                          title: 'No Customers Yet',
                          subtitle: 'Add your first customer to get started',
                          iconColor: DesignColors.textTertiary,
                          actionLabel: 'Add Customer',
                          onAction: _showAddCustomerSheet,
                        )
                      : RefreshIndicator(
                          onRefresh: () => _loadCustomers(),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: _customers.length,
                            itemBuilder: (context, index) {
                              final c = _customers[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassCard(
                                  padding: const EdgeInsets.all(12),
                                  borderRadius: 14,
                                  onTap: () => context.push('/customers/${c['id']}'),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: DesignColors.brand.withValues(alpha: 0.15),
                                        child: Text(
                                          (c['name'] as String? ?? '?')[0].toUpperCase(),
                                          style: const TextStyle(color: DesignColors.brand, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                            if ((c['phone'] ?? '').isNotEmpty)
                                              Text(c['phone'], style: const TextStyle(fontSize: 12, color: DesignColors.textSecondary)),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('KES ${(c['totalSpent'] as num?)?.toStringAsFixed(0) ?? '0'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: DesignColors.brand)),
                                          Text('${c['totalPurchases'] ?? 0} purchases', style: const TextStyle(fontSize: 11, color: DesignColors.textTertiary)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCustomerSheet,
        backgroundColor: DesignColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Customer'),
      ),
    );
  }
}