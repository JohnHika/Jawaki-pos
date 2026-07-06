import 'package:flutter/material.dart';
import '../../core/theme.dart';

class DashboardScreen extends StatelessWidget {
  final String storeName;
  final String aiStatus;

  const DashboardScreen({
    super.key,
    required this.storeName,
    this.aiStatus = 'not activated',
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => await Future.delayed(const Duration(seconds: 1)),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI Status mini card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: JawakiTheme.primaryTeal),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Jawaki AI is $aiStatus',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Navigate to AI tab — handled by parent
                      },
                      child: const Text('Open'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stats grid
            Row(
              children: [
                Expanded(child: _buildStatCard('Today\'s Sales', 'KES 12,450', Icons.trending_up, JawakiTheme.accentGreen)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('Orders Today', '34', Icons.receipt, JawakiTheme.primaryDeepBlue)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('Active Customers', '18', Icons.people, JawakiTheme.accentOrange)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('Low Stock Items', '5', Icons.warning_amber, JawakiTheme.accentRed)),
              ],
            ),

            const SizedBox(height: 24),

            // Recent transactions header
            const Text(
              'Recent Transactions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: JawakiTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _buildRecentTransaction('POS-001', 'KES 2,450', 'Just now'),
            _buildRecentTransaction('POS-002', 'KES 1,200', '5 min ago'),
            _buildRecentTransaction('POS-003', 'KES 3,800', '12 min ago'),
            _buildRecentTransaction('POS-004', 'KES 850', '20 min ago'),
            _buildRecentTransaction('POS-005', 'KES 5,200', '35 min ago'),

            const SizedBox(height: 24),

            // Quick links
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: JawakiTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildQuickActionCard(Icons.add_shopping_cart, 'New Sale', JawakiTheme.primaryTeal)),
                const SizedBox(width: 12),
                Expanded(child: _buildQuickActionCard(Icons.inventory_2, 'Add Stock', JawakiTheme.primaryDeepBlue)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildQuickActionCard(Icons.assessment, 'Reports', JawakiTheme.accentOrange)),
                const SizedBox(width: 12),
                Expanded(child: _buildQuickActionCard(Icons.sync, 'Sync', Colors.purple)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 13, color: JawakiTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTransaction(String id, String amount, String time) {
    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: JawakiTheme.accentGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.receipt, color: JawakiTheme.accentGreen, size: 20),
        ),
        title: Text(id, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(time, style: const TextStyle(fontSize: 12)),
        trailing: Text(
          amount,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: JawakiTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionCard(IconData icon, String label, Color color) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
