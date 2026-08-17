import 'package:flutter/material.dart';

void main() => runApp(const AxonDesktopApp());

class AxonDesktopApp extends StatelessWidget {
  const AxonDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF7548),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Axon POS Desktop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xFF0C0D11),
        cardColor: const Color(0xFF15171D),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF15171D),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
      ),
      home: const DesktopShell(),
    );
  }
}

class Product {
  Product({
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    required this.sku,
    required this.color,
    required this.icon,
  });

  final String name;
  final String category;
  final double price;
  int stock;
  final String sku;
  final Color color;
  final IconData icon;
}

class Customer {
  Customer({
    required this.name,
    required this.email,
    required this.phone,
    required this.orders,
    required this.spent,
    required this.status,
  });

  final String name;
  final String email;
  final String phone;
  final int orders;
  final double spent;
  final String status;
}

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _page = 0;
  final Map<Product, int> _cart = {};

  final products = <Product>[
    Product(
      name: 'Arabica Coffee',
      category: 'Beverages',
      price: 520,
      stock: 42,
      sku: 'BEV-001',
      color: const Color(0xFF8B5E3C),
      icon: Icons.coffee_rounded,
    ),
    Product(
      name: 'Sparkling Water',
      category: 'Beverages',
      price: 180,
      stock: 86,
      sku: 'BEV-002',
      color: const Color(0xFF3D91C8),
      icon: Icons.water_drop_rounded,
    ),
    Product(
      name: 'Granola Bowl',
      category: 'Breakfast',
      price: 650,
      stock: 18,
      sku: 'BRK-004',
      color: const Color(0xFFD2A24C),
      icon: Icons.breakfast_dining_rounded,
    ),
    Product(
      name: 'Avocado Toast',
      category: 'Breakfast',
      price: 780,
      stock: 11,
      sku: 'BRK-008',
      color: const Color(0xFF6BAA63),
      icon: Icons.lunch_dining_rounded,
    ),
    Product(
      name: 'Chicken Wrap',
      category: 'Lunch',
      price: 920,
      stock: 7,
      sku: 'LUN-012',
      color: const Color(0xFFC87845),
      icon: Icons.kebab_dining_rounded,
    ),
    Product(
      name: 'Garden Salad',
      category: 'Lunch',
      price: 760,
      stock: 25,
      sku: 'LUN-018',
      color: const Color(0xFF579A6B),
      icon: Icons.eco_rounded,
    ),
    Product(
      name: 'Chocolate Cake',
      category: 'Desserts',
      price: 480,
      stock: 4,
      sku: 'DES-002',
      color: const Color(0xFF7B4A6B),
      icon: Icons.cake_rounded,
    ),
    Product(
      name: 'Berry Cheesecake',
      category: 'Desserts',
      price: 560,
      stock: 13,
      sku: 'DES-006',
      color: const Color(0xFFB45E85),
      icon: Icons.bakery_dining_rounded,
    ),
  ];

  final customers = <Customer>[
    Customer(
      name: 'Amina Wanjiku',
      email: 'amina@example.com',
      phone: '+254 712 220 441',
      orders: 24,
      spent: 184200,
      status: 'VIP',
    ),
    Customer(
      name: 'Brian Otieno',
      email: 'brian@example.com',
      phone: '+254 722 019 380',
      orders: 12,
      spent: 93600,
      status: 'Active',
    ),
    Customer(
      name: 'Clara Mwende',
      email: 'clara@example.com',
      phone: '+254 701 338 102',
      orders: 8,
      spent: 52700,
      status: 'Active',
    ),
    Customer(
      name: 'David Kimani',
      email: 'david@example.com',
      phone: '+254 734 771 220',
      orders: 3,
      spent: 18800,
      status: 'Overdue',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extended = constraints.maxWidth >= 1180;
        return Scaffold(
          body: Row(
            children: [
              _NavigationRail(
                selected: _page,
                extended: extended,
                onSelected: (value) => setState(() => _page = value),
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      page: _page,
                      onNewSale: () => setState(() => _page = 1),
                    ),
                    Expanded(child: _pageBody()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pageBody() {
    switch (_page) {
      case 1:
        return _PosPage(
          cart: _cart,
          products: products,
          onAdd: _add,
          onRemove: _remove,
          onCheckout: _checkout,
        );
      case 2:
        return _ProductsPage(products: products);
      case 3:
        return _CustomersPage(customers: customers);
      case 4:
        return _InventoryPage(products: products);
      case 5:
        return const _ReportsPage();
      default:
        return const _DashboardPage();
    }
  }

  void _add(Product product) {
    setState(
      () =>
          _cart.update(product, (quantity) => quantity + 1, ifAbsent: () => 1),
    );
  }

  void _remove(Product product) {
    setState(() {
      final quantity = _cart[product] ?? 0;
      if (quantity <= 1) {
        _cart.remove(product);
      } else {
        _cart[product] = quantity - 1;
      }
    });
  }

  void _checkout() {
    if (_cart.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete sale'),
        content: const Text('Choose a payment method for this checkout.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(_cart.clear);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sale completed successfully')),
              );
            },
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Cash payment'),
          ),
        ],
      ),
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.selected,
    required this.extended,
    required this.onSelected,
  });

  final int selected;
  final bool extended;
  final ValueChanged<int> onSelected;
  static const items = <(IconData, String)>[
    (Icons.grid_view_rounded, 'Overview'),
    (Icons.point_of_sale_rounded, 'Point of sale'),
    (Icons.inventory_2_outlined, 'Products'),
    (Icons.people_alt_outlined, 'Customers'),
    (Icons.warehouse_outlined, 'Inventory'),
    (Icons.insights_outlined, 'Reports'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: extended ? 236 : 86,
      color: const Color(0xFF111217),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 16, 28),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Colors.black),
                ),
                if (extended) ...[
                  const SizedBox(width: 12),
                  const Text(
                    'AXON',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final active = selected == index;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Tooltip(
                    message: item.$2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelected(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? primary.withOpacity(.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.$1,
                              size: 21,
                              color: active ? primary : Colors.white54,
                            ),
                            if (extended) ...[
                              const SizedBox(width: 13),
                              Text(
                                item.$2,
                                style: TextStyle(
                                  color: active ? Colors.white : Colors.white60,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.settings_outlined, color: Colors.white54),
                    if (extended) ...[
                      const SizedBox(width: 13),
                      const Text(
                        'Settings',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.page, required this.onNewSale});
  final int page;
  final VoidCallback onNewSale;

  @override
  Widget build(BuildContext context) {
    const titles = [
      'Overview',
      'Point of sale',
      'Products',
      'Customers',
      'Inventory',
      'Reports',
    ];
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF24262D))),
      ),
      child: Row(
        children: [
          Text(
            titles[page],
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (page == 0)
            FilledButton.icon(
              onPressed: onNewSale,
              icon: const Icon(Icons.add, size: 19),
              label: const Text('New sale'),
            ),
          const SizedBox(width: 18),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Text(
              'JK',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('John Hika', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(
                'Administrator',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Good morning, John',
            style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Here is what is happening across Levisa Ventures today.',
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
          const SizedBox(height: 26),
          const Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MetricCard(
                title: "Today's sales",
                value: 'KES 84,620',
                change: '+18.4%',
                icon: Icons.trending_up_rounded,
                color: Color(0xFF66D89A),
              ),
              _MetricCard(
                title: 'Transactions',
                value: '126',
                change: '+9.2%',
                icon: Icons.receipt_long_outlined,
                color: Color(0xFF66B8F4),
              ),
              _MetricCard(
                title: 'Average order',
                value: 'KES 671',
                change: '+4.1%',
                icon: Icons.shopping_bag_outlined,
                color: Color(0xFFFFB45E),
              ),
              _MetricCard(
                title: 'Low stock items',
                value: '7',
                change: 'Needs attention',
                icon: Icons.warning_amber_rounded,
                color: Color(0xFFFF7B6B),
              ),
            ],
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth > 900
                ? const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _SalesChart()),
                      SizedBox(width: 18),
                      Expanded(flex: 2, child: _ActivityCard()),
                    ],
                  )
                : const Column(
                    children: [
                      _SalesChart(),
                      SizedBox(height: 18),
                      _ActivityCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.change,
    required this.icon,
    required this.color,
  });
  final String title;
  final String value;
  final String change;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, color: color),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              value,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              change,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SalesChart extends StatelessWidget {
  const _SalesChart();

  @override
  Widget build(BuildContext context) {
    const values = [0.38, 0.57, 0.46, 0.73, 0.66, 0.88, 0.79];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales performance',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Last 7 days',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
                Icon(Icons.more_horiz, color: Colors.white54),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 190,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [for (final value in values) _Bar(value: value)],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final day in days)
                  Text(
                    day,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 150 * value,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
    ),
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context) {
    const activity = [
      ('Sale #1042', 'KES 3,850', '2 min ago'),
      ('Stock received', 'Coffee beans', '24 min ago'),
      ('New customer', 'Amina Wanjiku', '1 hr ago'),
      ('Sale #1041', 'KES 1,240', '2 hrs ago'),
    ];
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent activity',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 18),
            for (final item in activity)
              Padding(
                padding: const EdgeInsets.only(bottom: 17),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: primary.withOpacity(.15),
                      child: Icon(
                        item.$1.startsWith('Sale')
                            ? Icons.receipt_long
                            : Icons.circle,
                        size: 16,
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$1,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.$2,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item.$3,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
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

class _PosPage extends StatefulWidget {
  const _PosPage({
    required this.cart,
    required this.products,
    required this.onAdd,
    required this.onRemove,
    required this.onCheckout,
  });
  final Map<Product, int> cart;
  final List<Product> products;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onRemove;
  final VoidCallback onCheckout;

  @override
  State<_PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<_PosPage> {
  String query = '';
  String category = 'All products';

  @override
  Widget build(BuildContext context) {
    final visible = widget.products.where((product) {
      final matchesQuery = product.name.toLowerCase().contains(
        query.toLowerCase(),
      );
      final matchesCategory =
          category == 'All products' || product.category == category;
      return matchesQuery && matchesCategory;
    }).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final catalog = _catalog(visible);
          if (constraints.maxWidth > 950) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: catalog),
                const SizedBox(width: 18),
                SizedBox(width: 360, child: _cartPanel()),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: [catalog, const SizedBox(height: 18), _cartPanel()],
            ),
          );
        },
      ),
    );
  }

  Widget _catalog(List<Product> visible) {
    const categories = [
      'All products',
      'Beverages',
      'Breakfast',
      'Lunch',
      'Desserts',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search products or scan SKU',
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final item in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item),
                    selected: category == item,
                    onSelected: (_) => setState(() => category = item),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 210,
            mainAxisExtent: 214,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) => _ProductTile(
            product: visible[index],
            onTap: () => widget.onAdd(visible[index]),
          ),
        ),
      ],
    );
  }

  Widget _cartPanel() {
    final total = widget.cart.entries.fold<double>(
      0,
      (sum, entry) => sum + entry.key.price * entry.value,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Current sale',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${widget.cart.length} items',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.cart.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 70),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 42,
                        color: Colors.white24,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Cart is empty',
                        style: TextStyle(color: Colors.white54),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Select a product to begin',
                        style: TextStyle(color: Colors.white30, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              for (final entry in widget.cart.entries)
                _CartRow(
                  product: entry.key,
                  count: entry.value,
                  onAdd: () => widget.onAdd(entry.key),
                  onRemove: () => widget.onRemove(entry.key),
                ),
              const Divider(height: 28),
              _SummaryRow(
                label: 'Subtotal',
                value: 'KES ${total.toStringAsFixed(0)}',
              ),
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Tax (included)',
                value: 'KES ${(total * .16).toStringAsFixed(0)}',
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Total',
                value: 'KES ${total.toStringAsFixed(0)}',
                strong: true,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.onCheckout,
                  icon: const Icon(Icons.lock_outline),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Text('Continue to payment'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: product.color.withOpacity(.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(product.icon, size: 42, color: product.color),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'KES ${product.price.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${product.stock} left',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.product,
    required this.count,
    required this.onAdd,
    required this.onRemove,
  });
  final Product product;
  final int count;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: product.color.withOpacity(.17),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(product.icon, size: 18, color: product.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                'KES ${(product.price * count).toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(
            Icons.remove_circle_outline,
            size: 18,
            color: Colors.white38,
          ),
        ),
        Text('$count', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(
          onPressed: onAdd,
          icon: Icon(
            Icons.add_circle_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          color: strong ? Colors.white : Colors.white54,
          fontWeight: strong ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: strong ? 19 : 13,
          fontWeight: FontWeight.w800,
          color: strong ? Theme.of(context).colorScheme.primary : Colors.white,
        ),
      ),
    ],
  );
}

class _ProductsPage extends StatefulWidget {
  const _ProductsPage({required this.products});
  final List<Product> products;

  @override
  State<_ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<_ProductsPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.products
        .where(
          (product) => '${product.name} ${product.sku}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 26, 32, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Product catalog',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Manage prices, stock visibility, categories and product images from one workspace.',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by product name or SKU',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Add product'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Card(
            child: SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('PRODUCT')),
                    DataColumn(label: Text('CATEGORY')),
                    DataColumn(label: Text('PRICE')),
                    DataColumn(label: Text('STOCK')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final product in list)
                      DataRow(
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                _ProductIcon(product: product),
                                const SizedBox(width: 10),
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              product.category,
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ),
                          DataCell(
                            Text('KES ${product.price.toStringAsFixed(0)}'),
                          ),
                          DataCell(Text('${product.stock} units')),
                          DataCell(
                            _StatusPill(
                              label: product.stock < 10
                                  ? 'Low stock'
                                  : 'In stock',
                              good: product.stock >= 10,
                            ),
                          ),
                          DataCell(
                            IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.more_horiz),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductIcon extends StatelessWidget {
  const _ProductIcon({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: product.color.withOpacity(.17),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(product.icon, size: 18, color: product.color),
  );
}

class _CustomersPage extends StatelessWidget {
  const _CustomersPage({required this.customers});
  final List<Customer> customers;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(32, 26, 32, 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customers',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Keep customer history and relationships close to every sale.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add customer'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(
              child: _SmallStat(
                label: 'Total customers',
                value: '1,284',
                icon: Icons.people_alt_outlined,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: _SmallStat(
                label: 'New this month',
                value: '86',
                icon: Icons.person_add_outlined,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: _SmallStat(
                label: 'Outstanding credit',
                value: 'KES 42,800',
                icon: Icons.credit_card_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('CUSTOMER')),
                DataColumn(label: Text('CONTACT')),
                DataColumn(label: Text('ORDERS')),
                DataColumn(label: Text('LIFETIME VALUE')),
                DataColumn(label: Text('STATUS')),
              ],
              rows: [
                for (final customer in customers)
                  DataRow(
                    cells: [
                      DataCell(
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: Colors.orangeAccent.withOpacity(
                                .18,
                              ),
                              child: Text(
                                customer.name.substring(0, 1),
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              customer.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customer.email),
                            Text(
                              customer.phone,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(Text('${customer.orders}')),
                      DataCell(
                        Text('KES ${customer.spent.toStringAsFixed(0)}'),
                      ),
                      DataCell(
                        _StatusPill(
                          label: customer.status,
                          good: customer.status != 'Overdue',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
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

class _InventoryPage extends StatelessWidget {
  const _InventoryPage({required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(32, 26, 32, 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Inventory control',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'See what is moving, what is low, and what needs a reorder.',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(
              child: _SmallStat(
                label: 'Total stock value',
                value: 'KES 1.82M',
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: _SmallStat(
                label: 'Low stock',
                value: '7 items',
                icon: Icons.warning_amber_rounded,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: _SmallStat(
                label: 'Pending requests',
                value: '12',
                icon: Icons.move_to_inbox_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stock levels',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 18),
                for (final product in products)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(
                            product.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: product.stock / 100,
                              minHeight: 8,
                              backgroundColor: Colors.white10,
                              color: product.stock < 10
                                  ? const Color(0xFFFF7B6B)
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 65,
                          child: Text(
                            '${product.stock} units',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: product.stock < 10
                                  ? const Color(0xFFFF7B6B)
                                  : Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReportsPage extends StatelessWidget {
  const _ReportsPage();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('Beverages', .82, 'KES 912K'),
      ('Lunch', .64, 'KES 704K'),
      ('Breakfast', .49, 'KES 536K'),
      ('Desserts', .31, 'KES 328K'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 26, 32, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reports & insights',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Make better operating decisions from one clear view of the business.',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Revenue by category',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'This month  •  KES 2.48M',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                        children: [
                          SizedBox(width: 100, child: Text(row.$1)),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: LinearProgressIndicator(
                                value: row.$2,
                                minHeight: 10,
                                backgroundColor: Colors.white10,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          SizedBox(
                            width: 90,
                            child: Text(
                              row.$3,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Expanded(
                child: _InsightCard(
                  title: 'Best seller',
                  value: 'Arabica Coffee',
                  detail: '142 units sold',
                  icon: Icons.star_rounded,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _InsightCard(
                  title: 'Peak hour',
                  value: '12:00 — 13:00',
                  detail: 'KES 184K revenue',
                  icon: Icons.schedule_rounded,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _InsightCard(
                  title: 'Repeat rate',
                  value: '38.6%',
                  detail: '+5.4% this month',
                  icon: Icons.repeat_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
  });
  final String title;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.good});
  final String label;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? const Color(0xFF66D89A) : const Color(0xFFFF7B6B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
