import 'package:flutter/material.dart';
import '../../core/theme.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

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
            // Summary
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Items', style: TextStyle(fontSize: 13, color: JawakiTheme.textSecondary)),
                          const SizedBox(height: 4),
                          const Text('142', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: JawakiTheme.textPrimary)),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 40, color: const Color(0xFFE0E0E0)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('Low Stock', style: TextStyle(fontSize: 13, color: JawakiTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text('5', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: JawakiTheme.accentRed)),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 40, color: const Color(0xFFE0E0E0)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Categories', style: TextStyle(fontSize: 13, color: JawakiTheme.textSecondary)),
                          const SizedBox(height: 4),
                          const Text('12', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: JawakiTheme.primaryTeal)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Alerts section
            if (_lowStockItems.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.warning_amber, color: JawakiTheme.accentRed, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Low Stock Alerts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: JawakiTheme.accentRed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._lowStockItems.map((item) => _buildAlertCard(item)),
              const SizedBox(height: 24),
            ],

            // Search
            TextField(
              decoration: InputDecoration(
                hintText: 'Search inventory...',
                prefixIcon: const Icon(Icons.search, color: JawakiTheme.textSecondary),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'All Items',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: JawakiTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            // Inventory items
            ..._inventoryItems.map((item) => _buildInventoryItem(item)),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> item) {
    return Card(
      elevation: 0.5,
      color: JawakiTheme.accentRed.withValues(alpha: 0.05),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: JawakiTheme.accentRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.inventory, color: JawakiTheme.accentRed, size: 20),
        ),
        title: Text(
          item['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          'Only ${item['quantity']} ${item['unit']} left — reorder now',
          style: const TextStyle(fontSize: 12, color: JawakiTheme.accentRed),
        ),
        trailing: ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: JawakiTheme.accentRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Text('Order', style: TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildInventoryItem(Map<String, dynamic> item) {
    final qty = item['quantity'] as int;
    final reorderLevel = item['reorderLevel'] as int;
    final isLow = qty <= reorderLevel;

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isLow
                    ? JawakiTheme.accentRed.withValues(alpha: 0.1)
                    : JawakiTheme.primaryTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getCategoryIcon(item['category'] as String? ?? ''),
                color: isLow ? JawakiTheme.accentRed : JawakiTheme.primaryTeal,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: JawakiTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item['category'] as String} • ${item['sku'] as String}',
                    style: const TextStyle(fontSize: 11, color: JawakiTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${qty} ${item['unit'] as String}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isLow ? JawakiTheme.accentRed : JawakiTheme.textPrimary,
                  ),
                ),
                Text(
                  item['price'] as String,
                  style: const TextStyle(fontSize: 12, color: JawakiTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'dairy':
        return Icons.egg;
      case 'beverages':
        return Icons.local_drink;
      case 'grains':
        return Icons.grass;
      case 'cooking':
        return Icons.kitchen;
      case 'snacks':
        return Icons.cookie;
      case 'personal care':
        return Icons.face;
      case 'cleaning':
        return Icons.cleaning_services;
      case 'electronics':
        return Icons.electrical_services;
      default:
        return Icons.inventory_2;
    }
  }
}

final List<Map<String, dynamic>> _lowStockItems = [
  {'name': 'Fresh Milk', 'quantity': 12, 'unit': 'units', 'reorderLevel': 20},
  {'name': 'Cooking Oil 2L', 'quantity': 8, 'unit': 'units', 'reorderLevel': 15},
  {'name': 'Sugar 1kg', 'quantity': 20, 'unit': 'units', 'reorderLevel': 25},
  {'name': 'Bread Loaf', 'quantity': 5, 'unit': 'units', 'reorderLevel': 15},
  {'name': 'Rice 5kg', 'quantity': 10, 'unit': 'units', 'reorderLevel': 12},
];

final List<Map<String, dynamic>> _inventoryItems = [
  {'name': 'Fresh Milk', 'category': 'Dairy', 'sku': 'D-001', 'quantity': 12, 'unit': 'units', 'price': 'KES 65', 'reorderLevel': 20},
  {'name': 'Full Cream Milk', 'category': 'Dairy', 'sku': 'D-002', 'quantity': 30, 'unit': 'units', 'price': 'KES 75', 'reorderLevel': 15},
  {'name': 'Yogurt - Strawberry', 'category': 'Dairy', 'sku': 'D-003', 'quantity': 45, 'unit': 'cups', 'price': 'KES 50', 'reorderLevel': 20},
  {'name': 'Cooking Oil 2L', 'category': 'Cooking', 'sku': 'C-001', 'quantity': 8, 'unit': 'units', 'price': 'KES 380', 'reorderLevel': 15},
  {'name': 'Cooking Oil 1L', 'category': 'Cooking', 'sku': 'C-002', 'quantity': 25, 'unit': 'units', 'price': 'KES 200', 'reorderLevel': 20},
  {'name': 'Sugar 1kg', 'category': 'Grains', 'sku': 'G-001', 'quantity': 20, 'unit': 'units', 'price': 'KES 180', 'reorderLevel': 25},
  {'name': 'Rice 5kg', 'category': 'Grains', 'sku': 'G-002', 'quantity': 10, 'unit': 'units', 'price': 'KES 650', 'reorderLevel': 12},
  {'name': 'Rice 2kg', 'category': 'Grains', 'sku': 'G-003', 'quantity': 35, 'unit': 'units', 'price': 'KES 280', 'reorderLevel': 20},
  {'name': 'Bread Loaf', 'category': 'Snacks', 'sku': 'S-001', 'quantity': 5, 'unit': 'units', 'price': 'KES 55', 'reorderLevel': 15},
  {'name': 'Soda - Coca Cola', 'category': 'Beverages', 'sku': 'B-001', 'quantity': 48, 'unit': 'units', 'price': 'KES 25', 'reorderLevel': 30},
  {'name': 'Soda - Fanta', 'category': 'Beverages', 'sku': 'B-002', 'quantity': 36, 'unit': 'units', 'price': 'KES 25', 'reorderLevel': 24},
  {'name': 'Water 1L', 'category': 'Beverages', 'sku': 'B-003', 'quantity': 60, 'unit': 'units', 'price': 'KES 30', 'reorderLevel': 40},
  {'name': 'Wheat Flour 2kg', 'category': 'Grains', 'sku': 'G-004', 'quantity': 22, 'unit': 'units', 'price': 'KES 210', 'reorderLevel': 15},
  {'name': 'Soap - Bar', 'category': 'Cleaning', 'sku': 'CL-001', 'quantity': 50, 'unit': 'units', 'price': 'KES 45', 'reorderLevel': 30},
  {'name': 'Detergent 1kg', 'category': 'Cleaning', 'sku': 'CL-002', 'quantity': 28, 'unit': 'units', 'price': 'KES 180', 'reorderLevel': 20},
  {'name': 'Toothpaste', 'category': 'Personal Care', 'sku': 'PC-001', 'quantity': 40, 'unit': 'units', 'price': 'KES 85', 'reorderLevel': 25},
  {'name': 'Cooking Fat 500g', 'category': 'Cooking', 'sku': 'C-003', 'quantity': 18, 'unit': 'units', 'price': 'KES 120', 'reorderLevel': 12},
  {'name': 'Eggs (Tray)', 'category': 'Dairy', 'sku': 'D-004', 'quantity': 32, 'unit': 'trays', 'price': 'KES 500', 'reorderLevel': 15},
  {'name': 'Milk Powder 500g', 'category': 'Dairy', 'sku': 'D-005', 'quantity': 15, 'unit': 'units', 'price': 'KES 350', 'reorderLevel': 10},
  {'name': 'Cooking Spices', 'category': 'Cooking', 'sku': 'C-004', 'quantity': 45, 'unit': 'units', 'price': 'KES 30', 'reorderLevel': 20},
];
