import 'package:flutter/material.dart';

import 'core/desktop_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = DesktopSession();
  await session.initialize();
  runApp(AxonDesktopApp(session: session));
}

class AxonDesktopApp extends StatelessWidget {
  const AxonDesktopApp({required this.session, super.key});

  final DesktopSession session;

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
      home: _AppGate(session: session),
    );
  }
}

class _AppGate extends StatelessWidget {
  const _AppGate({required this.session});

  final DesktopSession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (session.initializing) return const _StartupScreen();
        if (!session.authenticated) return _LoginScreen(session: session);
        return DesktopShell(session: session);
      },
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.session});

  final DesktopSession session;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _workspace = TextEditingController(text: 'levisa-ventures');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _server.text = widget.session.apiBaseUrl;
  }

  @override
  void dispose() {
    _workspace.dispose();
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.bolt_rounded,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AXON POS',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Text(
                                'Desktop workspace',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 34),
                      const Text(
                        'Sign in to your business',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Use the same account and business workspace as the mobile POS.',
                        style: TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _workspace,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Business workspace',
                          hintText: 'levisa-ventures',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                        validator: (value) =>
                            value == null || value.trim().length < 2
                            ? 'Enter your business workspace'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (value) =>
                            value == null || !value.contains('@')
                            ? 'Enter a valid email address'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        onFieldSubmitted: (_) => _signIn(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.length < 8
                            ? 'Enter your password'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _signIn,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Sign in'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _showGoogleStatus,
                        icon: const Icon(Icons.g_mobiledata_rounded),
                        label: const Text('Sign in with Google'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _busy ? null : _showServerSettings,
                        icon: const Icon(
                          Icons.settings_ethernet_outlined,
                          size: 18,
                        ),
                        label: const Text('Server connection settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.session.login(
        email: _email.text.trim(),
        password: _password.text,
        tenantSlug: _workspace.text.trim().toLowerCase(),
      );
    } on ApiFailure catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showGoogleStatus() {
    _showMessage(
      'Google sign-in will be enabled after the desktop OAuth client and redirect address are added to the Google Cloud configuration. Email and PIN-backed accounts can sign in now.',
    );
  }

  Future<void> _showServerSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('POS server connection'),
        content: TextField(
          controller: _server,
          decoration: const InputDecoration(
            labelText: 'API server URL',
            hintText: defaultApiBaseUrl,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await widget.session.setApiBaseUrl(_server.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    required this.sku,
    required this.color,
    required this.icon,
    this.imageUrl,
    this.minStock = 0,
    this.unit = 'piece',
  });

  final String id;
  final String name;
  final String category;
  final double price;
  final double stock;
  final String sku;
  final Color color;
  final IconData icon;
  final String? imageUrl;
  final double minStock;
  final String unit;

  bool get lowStock => stock <= minStock || (minStock == 0 && stock <= 0);

  factory Product.fromJson(Map<String, dynamic> json) {
    final categories = jsonMaps(json['categories']);
    final category = categories.isEmpty
        ? 'Uncategorised'
        : (categories.first['name']?.toString() ?? 'Uncategorised');
    final color = _productColor(category);
    return Product(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed product',
      category: category,
      price: _number(
        json['currentPrice'] ?? json['price'] ?? json['basePrice'],
      ),
      stock: _number(json['currentStock']),
      sku: json['sku']?.toString() ?? '—',
      color: color,
      icon: _productIcon(category),
      imageUrl: json['imageUrl']?.toString() ?? json['image']?.toString(),
      minStock: _number(json['minStock']),
      unit: json['unit']?.toString() ?? 'piece',
    );
  }
}

class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String address;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Unnamed customer',
    email: json['email']?.toString() ?? '',
    phone: json['phone']?.toString() ?? '',
    address: json['address']?.toString() ?? '',
  );
}

double _number(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

Color _productColor(String category) {
  const colors = [
    Color(0xFF8B5E3C),
    Color(0xFF3D91C8),
    Color(0xFFD2A24C),
    Color(0xFF6BAA63),
    Color(0xFFB45E85),
    Color(0xFFC87845),
  ];
  return colors[category.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
      colors.length];
}

IconData _productIcon(String category) {
  final text = category.toLowerCase();
  if (text.contains('bever')) return Icons.local_drink_rounded;
  if (text.contains('food') || text.contains('lunch') || text.contains('break'))
    return Icons.restaurant_rounded;
  if (text.contains('dessert') || text.contains('bak'))
    return Icons.cake_rounded;
  return Icons.inventory_2_outlined;
}

class DesktopShell extends StatefulWidget {
  const DesktopShell({required this.session, super.key});

  final DesktopSession session;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _page = 0;
  final Map<Product, int> _cart = {};
  List<Product> products = const [];
  List<Customer> customers = const [];
  List<Map<String, dynamic>> categories = const [];
  List<Map<String, dynamic>> stock = const [];
  Map<String, dynamic> dashboard = const {};
  List<Map<String, dynamic>> salesTrend = const [];
  List<Map<String, dynamic>> topProducts = const [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadWorkspace();
  }

  Future<void> _loadWorkspace() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final api = widget.session.api;
    final branchId = widget.session.branchId;
    try {
      final results = await Future.wait([
        api.getProducts(branchId: branchId),
        api.getCategories(),
        api.getCustomers(),
        if (branchId != null)
          api.getStock(branchId)
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);
      final loadedProducts = (results[0] as List<Map<String, dynamic>>)
          .where((item) => item['isActive'] != false)
          .map(Product.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        products = loadedProducts;
        categories = results[1] as List<Map<String, dynamic>>;
        customers = (results[2] as List<Map<String, dynamic>>)
            .map(Customer.fromJson)
            .toList();
        stock = results[3] as List<Map<String, dynamic>>;
      });
      await _loadInsights();
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadInsights() async {
    final branchId = widget.session.branchId;
    try {
      final results = await Future.wait([
        widget.session.api.getDashboard(branchId: branchId),
        widget.session.api.getSalesTrend(branchId: branchId),
        widget.session.api.getTopProducts(branchId: branchId),
      ]);
      if (mounted) {
        setState(() {
          dashboard = results[0] as Map<String, dynamic>;
          salesTrend = results[1] as List<Map<String, dynamic>>;
          topProducts = results[2] as List<Map<String, dynamic>>;
        });
      }
    } catch (_) {
      // Reporting permissions can vary by role; operational pages remain usable.
    }
  }

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
                      onRefresh: _loadWorkspace,
                      session: widget.session,
                    ),
                    Expanded(
                      child: _loading
                          ? _LoadingPage(
                              error: _loadError,
                              onRetry: _loadWorkspace,
                            )
                          : _pageBody(),
                    ),
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
        return _ProductsPage(
          products: products,
          categories: categories,
          api: widget.session.api,
          onChanged: _loadWorkspace,
        );
      case 3:
        return _CustomersPage(
          customers: customers,
          api: widget.session.api,
          onChanged: _loadWorkspace,
        );
      case 4:
        return _InventoryPage(products: products);
      case 5:
        return _ReportsPage(dashboard: dashboard, topProducts: topProducts);
      default:
        return _DashboardPage(
          dashboard: dashboard,
          trend: salesTrend,
          userName: widget.session.displayName,
        );
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
            onPressed: () => _submitSale(dialogContext),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Cash payment'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitSale(BuildContext dialogContext) async {
    final branchId = widget.session.branchId;
    if (branchId == null || branchId.isEmpty) {
      Navigator.pop(dialogContext);
      _showMessage(
        'No branch is selected for this account. Choose a branch in Settings.',
      );
      return;
    }
    try {
      await widget.session.api.createSale({
        'branchId': branchId,
        'deviceId': widget.session.deviceId,
        'paymentMethod': 'CASH',
        'paidAmount': _cart.entries.fold<double>(
          0,
          (sum, entry) => sum + entry.key.price * entry.value,
        ),
        'items': _cart.entries
            .map(
              (entry) => {
                'productId': entry.key.id,
                'quantity': entry.value,
                'unitPrice': entry.key.price,
              },
            )
            .toList(),
      });
      if (!mounted) return;
      Navigator.pop(dialogContext);
      setState(_cart.clear);
      _showMessage('Sale completed successfully.');
      await _loadWorkspace();
    } on ApiFailure catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: error == null
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading your live workspace…'),
                ],
              )
            : Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_outlined,
                        size: 38,
                        color: Colors.orangeAccent,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'We could not load your workspace',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    ),
  );
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
  const _TopBar({
    required this.page,
    required this.onNewSale,
    required this.onRefresh,
    required this.session,
  });
  final int page;
  final VoidCallback onNewSale;
  final VoidCallback onRefresh;
  final DesktopSession session;

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
            tooltip: 'Refresh live data',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              _initials(session.displayName),
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.displayName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                session.user?['role']?.toString() ?? 'Team member',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.take(2).map((part) => part[0]).join().toUpperCase();
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({
    required this.dashboard,
    required this.trend,
    required this.userName,
  });

  final Map<String, dynamic> dashboard;
  final List<Map<String, dynamic>> trend;
  final String userName;

  @override
  Widget build(BuildContext context) {
    final sales = jsonMap(dashboard['sales']);
    final inventory = jsonMap(dashboard['inventory']);
    final name = userName.split(RegExp(r'\s+')).first;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back, $name',
            style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Today’s live sales and inventory snapshot.',
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
          const SizedBox(height: 26),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MetricCard(
                title: "Today's sales",
                value: _money(
                  _number(sales['netRevenue'] ?? sales['totalRevenue']),
                ),
                change:
                    '${_number(sales['itemsSold']).toStringAsFixed(0)} items sold',
                icon: Icons.trending_up_rounded,
                color: Color(0xFF66D89A),
              ),
              _MetricCard(
                title: 'Transactions',
                value: _number(sales['totalSales']).toStringAsFixed(0),
                change:
                    '${_number(sales['uniqueCustomers']).toStringAsFixed(0)} customers',
                icon: Icons.receipt_long_outlined,
                color: Color(0xFF66B8F4),
              ),
              _MetricCard(
                title: 'Average order',
                value: _money(_number(sales['averageTicket'])),
                change: 'Live today',
                icon: Icons.shopping_bag_outlined,
                color: Color(0xFFFFB45E),
              ),
              _MetricCard(
                title: 'Low stock items',
                value: _number(inventory['lowStockItems']).toStringAsFixed(0),
                change: 'Needs attention',
                icon: Icons.warning_amber_rounded,
                color: Color(0xFFFF7B6B),
              ),
            ],
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth > 900
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _SalesChart(trend: trend)),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 2,
                        child: _LiveSnapshot(
                          sales: sales,
                          inventory: inventory,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _SalesChart(trend: trend),
                      const SizedBox(height: 18),
                      _LiveSnapshot(sales: sales, inventory: inventory),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String _money(double value) => 'KES ${value.toStringAsFixed(0)}';

class _LiveSnapshot extends StatelessWidget {
  const _LiveSnapshot({required this.sales, required this.inventory});

  final Map<String, dynamic> sales;
  final Map<String, dynamic> inventory;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live snapshot',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 20),
          _SnapshotLine(
            icon: Icons.inventory_2_outlined,
            label: 'Products tracked',
            value: _number(inventory['totalProducts']).toStringAsFixed(0),
          ),
          const SizedBox(height: 16),
          _SnapshotLine(
            icon: Icons.inventory_outlined,
            label: 'Stock value',
            value: _money(_number(inventory['totalStockValue'])),
          ),
          const SizedBox(height: 16),
          _SnapshotLine(
            icon: Icons.discount_outlined,
            label: 'Discounts today',
            value: _money(_number(sales['totalDiscount'])),
          ),
        ],
      ),
    ),
  );
}

class _SnapshotLine extends StatelessWidget {
  const _SnapshotLine({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label, style: const TextStyle(color: Colors.white60)),
      ),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
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
  const _SalesChart({required this.trend});

  final List<Map<String, dynamic>> trend;

  @override
  Widget build(BuildContext context) {
    final rawValues = trend
        .map(
          (item) =>
              _number(item['revenue'] ?? item['totalRevenue'] ?? item['sales']),
        )
        .toList();
    final max = rawValues.fold<double>(
      0,
      (value, next) => next > value ? next : value,
    );
    final values = rawValues
        .map((value) => max == 0 ? 0.06 : value / max)
        .toList();
    final days = trend
        .map(
          (item) =>
              item['label']?.toString() ??
              item['date']?.toString().split('T').first ??
              '—',
        )
        .toList();
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
                children: values.isEmpty
                    ? [
                        const Text(
                          'No sales recorded for this period',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ]
                    : [for (final value in values) _Bar(value: value)],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final day in days.take(7))
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
                child: product.imageUrl == null || product.imageUrl!.isEmpty
                    ? Icon(product.icon, size: 42, color: product.color)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            product.icon,
                            size: 42,
                            color: product.color,
                          ),
                        ),
                      ),
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
  const _ProductsPage({
    required this.products,
    required this.categories,
    required this.api,
    required this.onChanged,
  });
  final List<Product> products;
  final List<Map<String, dynamic>> categories;
  final DesktopApi api;
  final Future<void> Function() onChanged;

  @override
  State<_ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<_ProductsPage> {
  String query = '';
  bool grid = false;

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
              IconButton(
                tooltip: grid ? 'Show list' : 'Show grid',
                onPressed: () => setState(() => grid = !grid),
                icon: Icon(
                  grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Add product'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (grid)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 235,
                mainAxisExtent: 238,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: list.length,
              itemBuilder: (context, index) =>
                  _ProductTile(product: list[index], onTap: () {}),
            )
          else
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
                                tooltip: 'Edit product',
                                onPressed: () => _openEditor(product),
                                icon: const Icon(Icons.edit_outlined),
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

  Future<void> _openEditor([Product? product]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductEditorDialog(
        api: widget.api,
        categories: widget.categories,
        product: product,
      ),
    );
    if (saved == true && mounted) await widget.onChanged();
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
    child: product.imageUrl == null || product.imageUrl!.isEmpty
        ? Icon(product.icon, size: 18, color: product.color)
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              product.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(product.icon, size: 18, color: product.color),
            ),
          ),
  );
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    required this.api,
    required this.categories,
    this.product,
  });

  final DesktopApi api;
  final List<Map<String, dynamic>> categories;
  final Product? product;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _price;
  late final TextEditingController _image;
  late final TextEditingController _minimum;
  late final TextEditingController _unit;
  String? _categoryId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _sku = TextEditingController(
      text: product?.sku == '—' ? '' : product?.sku ?? '',
    );
    _price = TextEditingController(
      text: product == null ? '' : product.price.toStringAsFixed(2),
    );
    _image = TextEditingController(text: product?.imageUrl ?? '');
    _minimum = TextEditingController(
      text: product == null ? '0' : product.minStock.toStringAsFixed(0),
    );
    _unit = TextEditingController(text: product?.unit ?? 'piece');
    _categoryId = widget.categories
        .where((item) => item['name']?.toString() == product?.category)
        .firstOrNull?['id']
        ?.toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    _image.dispose();
    _minimum.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.product == null ? 'Add product' : 'Edit product'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Product name'),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter a product name'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Selling price (KES)',
                      ),
                      validator: (value) =>
                          _number(value) < 0 ? 'Enter a valid price' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sku,
                      decoration: const InputDecoration(
                        labelText: 'SKU (optional)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No category'),
                  ),
                  ...widget.categories.map(
                    (category) => DropdownMenuItem(
                      value: category['id']?.toString(),
                      child: Text(category['name']?.toString() ?? 'Category'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _image,
                decoration: const InputDecoration(
                  labelText: 'Product image URL (optional)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minimum,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Low-stock level',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save product'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'basePrice': _number(_price.text),
      'minStock': _number(_minimum.text),
      'unit': _unit.text.trim().isEmpty ? 'piece' : _unit.text.trim(),
      if (_sku.text.trim().isNotEmpty) 'sku': _sku.text.trim(),
      if (_image.text.trim().isNotEmpty) 'image': _image.text.trim(),
      if (_categoryId != null) 'categoryIds': [_categoryId],
    };
    try {
      if (widget.product == null) {
        await widget.api.createProduct(payload);
      } else {
        await widget.api.updateProduct(widget.product!.id, payload);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiFailure catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = error.message;
        });
    }
  }
}

class _CustomersPage extends StatelessWidget {
  const _CustomersPage({
    required this.customers,
    required this.api,
    required this.onChanged,
  });
  final List<Customer> customers;
  final DesktopApi api;
  final Future<void> Function() onChanged;

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
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add customer'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _SmallStat(
                label: 'Total customers',
                value: customers.length.toString(),
                icon: Icons.people_alt_outlined,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _SmallStat(
                label: 'With phone number',
                value: customers
                    .where((customer) => customer.phone.isNotEmpty)
                    .length
                    .toString(),
                icon: Icons.phone_outlined,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _SmallStat(
                label: 'Email contacts',
                value: customers
                    .where((customer) => customer.email.isNotEmpty)
                    .length
                    .toString(),
                icon: Icons.mail_outline,
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
                DataColumn(label: Text('ADDRESS')),
              ],
              rows: [
                for (final customer in customers)
                  DataRow(
                    onSelectChanged: (_) => _openEditor(context, customer),
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
                      DataCell(
                        Text(customer.address.isEmpty ? '—' : customer.address),
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

  Future<void> _openEditor(BuildContext context, [Customer? customer]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerEditorDialog(api: api, customer: customer),
    );
    if (saved == true) await onChanged();
  }
}

class _CustomerEditorDialog extends StatefulWidget {
  const _CustomerEditorDialog({required this.api, this.customer});

  final DesktopApi api;
  final Customer? customer;

  @override
  State<_CustomerEditorDialog> createState() => _CustomerEditorDialogState();
}

class _CustomerEditorDialogState extends State<_CustomerEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.customer?.name ?? '');
    _email = TextEditingController(text: widget.customer?.email ?? '');
    _phone = TextEditingController(text: widget.customer?.phone ?? '');
    _address = TextEditingController(text: widget.customer?.address ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.customer == null ? 'Add customer' : 'Edit customer'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Customer name'),
              validator: (value) => value == null || value.trim().length < 2
                  ? 'Enter a customer name'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address'),
              validator: (value) =>
                  value != null && value.isNotEmpty && !value.contains('@')
                  ? 'Enter a valid email address'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save customer'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'address': _address.text.trim(),
    };
    try {
      if (widget.customer == null) {
        await widget.api.createCustomer(payload);
      } else {
        await widget.api.updateCustomer(widget.customer!.id, payload);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiFailure catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = error.message;
        });
    }
  }
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
        Row(
          children: [
            Expanded(
              child: _SmallStat(
                label: 'Products tracked',
                value: products.length.toString(),
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _SmallStat(
                label: 'Low stock',
                value:
                    '${products.where((product) => product.lowStock).length} items',
                icon: Icons.warning_amber_rounded,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _SmallStat(
                label: 'Units in stock',
                value: products
                    .fold<double>(0, (sum, product) => sum + product.stock)
                    .toStringAsFixed(0),
                icon: Icons.inventory_outlined,
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
                              value:
                                  (product.stock /
                                          (product.minStock > 0
                                              ? product.minStock * 3
                                              : 100))
                                      .clamp(0.0, 1.0),
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
  const _ReportsPage({required this.dashboard, required this.topProducts});

  final Map<String, dynamic> dashboard;
  final List<Map<String, dynamic>> topProducts;

  @override
  Widget build(BuildContext context) {
    final sales = jsonMap(dashboard['sales']);
    final maximum = topProducts.fold<double>(
      0,
      (value, item) => _number(item['revenue'] ?? item['totalRevenue']) > value
          ? _number(item['revenue'] ?? item['totalRevenue'])
          : value,
    );
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Top products',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Today  •  ${_money(_number(sales['netRevenue'] ?? sales['totalRevenue']))}',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  if (topProducts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Text(
                        'No sales data is available for this period.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  else
                    for (final item in topProducts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 130,
                              child: Text(
                                item['name']?.toString() ??
                                    item['productName']?.toString() ??
                                    'Product',
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: LinearProgressIndicator(
                                  value: maximum == 0
                                      ? 0
                                      : _number(
                                              item['revenue'] ??
                                                  item['totalRevenue'],
                                            ) /
                                            maximum,
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
                                _money(
                                  _number(
                                    item['revenue'] ?? item['totalRevenue'],
                                  ),
                                ),
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
          Row(
            children: [
              Expanded(
                child: _InsightCard(
                  title: 'Best seller',
                  value: topProducts.isEmpty
                      ? 'No sales yet'
                      : (topProducts.first['name']?.toString() ??
                            topProducts.first['productName']?.toString() ??
                            'Product'),
                  detail: topProducts.isEmpty
                      ? 'Start selling in the POS'
                      : '${_number(topProducts.first['quantity'] ?? topProducts.first['quantitySold']).toStringAsFixed(0)} units sold',
                  icon: Icons.star_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _InsightCard(
                  title: 'Transactions',
                  value: _number(sales['totalSales']).toStringAsFixed(0),
                  detail: 'Recorded today',
                  icon: Icons.receipt_long_outlined,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _InsightCard(
                  title: 'Average order',
                  value: _money(_number(sales['averageTicket'])),
                  detail: 'Current period',
                  icon: Icons.shopping_bag_outlined,
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
