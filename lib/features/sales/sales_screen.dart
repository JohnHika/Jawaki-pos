import 'package:flutter/material.dart';
import '../../core/theme.dart';

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

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
            // Summary cards
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Today',
                    'KES 12,450',
                    Icons.today,
                    JawakiTheme.accentGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'This Week',
                    'KES 78,320',
                    Icons.date_range,
                    JawakiTheme.primaryDeepBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'This Month',
                    'KES 342,150',
                    Icons.calendar_month,
                    JawakiTheme.accentOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Avg/Day',
                    'KES 11,405',
                    Icons.trending_up,
                    JawakiTheme.primaryTeal,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Filter row
            Row(
              children: [
                const Text(
                  'Recent Sales',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: JawakiTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_list, size: 16, color: JawakiTheme.textSecondary),
                      SizedBox(width: 4),
                      Text(
                        'Today',
                        style: TextStyle(fontSize: 13, color: JawakiTheme.textSecondary),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 16, color: JawakiTheme.textSecondary),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Sales list
            ..._salesData.map((sale) => _buildSaleCard(sale)),

            const SizedBox(height: 16),

            // View all button
            Center(
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.arrow_forward),
                label: const Text('View All Sales'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: JawakiTheme.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleCard(Map<String, dynamic> sale) {
    final status = sale['status'] as String;
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'completed':
        statusColor = JawakiTheme.accentGreen;
        statusIcon = Icons.check_circle;
        break;
      case 'pending':
        statusColor = JawakiTheme.accentOrange;
        statusIcon = Icons.schedule;
        break;
      case 'cancelled':
        statusColor = JawakiTheme.accentRed;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = JawakiTheme.textSecondary;
        statusIcon = Icons.help;
    }

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(
          sale['id'] as String,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sale['items'] as int} items • ${sale['customer'] as String}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              sale['time'] as String,
              style: const TextStyle(fontSize: 11, color: JawakiTheme.textSecondary),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              sale['amount'] as String,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: JawakiTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                status,
                style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final List<Map<String, dynamic>> _salesData = [
  {
    'id': '#POS-001',
    'amount': 'KES 2,450',
    'items': 4,
    'customer': 'Cash Customer',
    'time': 'Just now',
    'status': 'completed',
  },
  {
    'id': '#POS-002',
    'amount': 'KES 1,200',
    'items': 2,
    'customer': 'Mary W.',
    'time': '5 min ago',
    'status': 'completed',
  },
  {
    'id': '#POS-003',
    'amount': 'KES 3,800',
    'items': 6,
    'customer': 'John K.',
    'time': '12 min ago',
    'status': 'completed',
  },
  {
    'id': '#POS-004',
    'amount': 'KES 850',
    'items': 1,
    'customer': 'Cash Customer',
    'time': '20 min ago',
    'status': 'pending',
  },
  {
    'id': '#POS-005',
    'amount': 'KES 5,200',
    'items': 8,
    'customer': 'Jane A.',
    'time': '35 min ago',
    'status': 'completed',
  },
  {
    'id': '#POS-006',
    'amount': 'KES 1,650',
    'items': 3,
    'customer': 'Peter M.',
    'time': '48 min ago',
    'status': 'cancelled',
  },
  {
    'id': '#POS-007',
    'amount': 'KES 950',
    'items': 2,
    'customer': 'Grace N.',
    'time': '1 hour ago',
    'status': 'completed',
  },
  {
    'id': '#POS-008',
    'amount': 'KES 3,100',
    'items': 5,
    'customer': 'Cash Customer',
    'time': '1.5 hours ago',
    'status': 'completed',
  },
];
