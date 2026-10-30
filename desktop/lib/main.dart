import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'features/ai/desktop_ai_screen.dart';
import 'core/desktop_link_client.dart';
import 'core/desktop_qr_sign_in.dart';
import 'core/desktop_workspace.dart';
import 'core/desktop_archive_import.dart';
import 'features/settings/desktop_archive_history_dialog.dart';
import 'theme/counterbase_theme.dart';

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
    return MaterialApp(
      title: 'Counterbase Desktop',
      debugShowCheckedModeBanner: false,
      theme: buildCounterbaseTheme(),
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
        if (session.initializationError != null) {
          return _WorkspaceFailure(message: session.initializationError!);
        }
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

class _WorkspaceFailure extends StatelessWidget {
  const _WorkspaceFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_rounded, size: 38),
                const SizedBox(height: 16),
                const Text(
                  'Your local workspace could not be opened',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.session});

  final DesktopSession session;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _business = TextEditingController();
  final _owner = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  // Phone sign-in is the fast path once a phone server is reachable; the
  // PIN form stays available as fallback. Fresh workspaces still need the
  // form (business/owner naming) before any phone pairing can adopt one.
  bool _usePhoneSignIn = false;

  /// Phones announce themselves on the LAN; this desktop has no way to
  /// enumerate them, so the address is entered once (or pinned via env for
  /// kiosk setups) and remembered in the OS credential store.
  static const _phoneServerKey = 'counterbase_desktop_phone_server';
  String? _phoneServer;

  @override
  void initState() {
    super.initState();
    _loadPhoneServer();
  }

  Future<void> _loadPhoneServer() async {
    final stored = await widget.session.storageRead(_phoneServerKey);
    final env = const String.fromEnvironment('COUNTERBASE_PHONE_SERVER');
    final url = (stored?.isNotEmpty == true ? stored : env) ?? '';
    if (!mounted || url.isEmpty) return;
    if (!DesktopLinkClient.isPrivateNetworkBaseUrl(url)) {
      setState(() {
        _phoneServer = null;
        _error =
            'Saved phone address is not a private-network address. Enter the LAN address shown in the phone’s Backend Server settings.';
      });
      return;
    }
    setState(() {
      _phoneServer = url;
      // Only jump straight to the phone flow for an existing workspace.
      _usePhoneSignIn = widget.session.hasWorkspace;
    });
  }

  /// One-time phone address entry: the user reads it from the phone's
  /// Settings → Backend Server screen (e.g. http://192.168.1.20:3000).
  Future<void> _pickPhoneServer() async {
    final controller = TextEditingController(text: _phoneServer ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect to your phone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'In Counterbase on your phone, open Settings → Backend Server '
              'and turn on server mode. Type the address it shows here.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Phone address',
                hintText: 'http://192.168.1.20:3000',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final normalized = url.endsWith('/')
        ? url.substring(0, url.length - 1)
        : url;
    if (!DesktopLinkClient.isPrivateNetworkBaseUrl(normalized)) {
      setState(() {
        _error =
            'Enter the phone’s private-network address, such as http://192.168.1.20:3000.';
      });
      return;
    }
    await _savePhoneServer(normalized);
    if (!mounted) return;
    setState(() {
      _phoneServer = normalized;
      _usePhoneSignIn = true;
      _error = null;
    });
  }

  /// The phone approved: adopt the session and open the workspace.
  Future<void> _finishPhoneSignIn(DesktopLinkSession linked) async {
    try {
      await widget.session.loginWithPhoneApproval(
        displayName: linked.userName.isEmpty ? 'Owner' : linked.userName,
        businessName: widget.session.businessName,
      );
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _savePhoneServer(String url) =>
      widget.session.storageWrite(_phoneServerKey, url);

  @override
  void dispose() {
    _business.dispose();
    _owner.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSetup = !widget.session.hasWorkspace;
    final phoneAvailable = !isSetup;
    return Scaffold(
      body: Row(
        children: [
          Expanded(flex: 5, child: _LoginAside(isSetup: isSetup)),
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            CbLogoMark(size: 40),
                            SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Counterbase',
                                  style: TextStyle(
                                    fontFamily: 'CbDisplay',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                    color: CbInk.text,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text('DESKTOP WORKSPACE', style: CbText.tag),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        if (!phoneAvailable) ...[
                          CbTag('SET UP THIS DEVICE'),
                          const SizedBox(height: 12),
                          Text(
                            'Open your local workspace.',
                            style: CbText.display.copyWith(fontSize: 26),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Sales, products, customers and stock stay on this computer. No Counterbase online account, no POS server.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _business,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Business name',
                              hintText: 'Your shop or company',
                            ),
                            validator: (value) =>
                                value == null || value.trim().length < 2
                                ? 'Enter your business name'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _owner,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Your name',
                            ),
                            validator: (value) =>
                                value == null || value.trim().length < 2
                                ? 'Enter your name'
                                : null,
                          ),
                          const SizedBox(height: 14),
                        ] else if (_usePhoneSignIn) ...[
                          DesktopQrSignIn(
                            session: widget.session,
                            phoneBaseUrl: _phoneServer ?? '',
                            onBack: () =>
                                setState(() => _usePhoneSignIn = false),
                            onLinked: _finishPhoneSignIn,
                          ),
                        ] else ...[
                          CbTag('WELCOME BACK'),
                          const SizedBox(height: 12),
                          Text(
                            'Unlock ${widget.session.businessName}.',
                            style: CbText.display.copyWith(fontSize: 26),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Enter your owner PIN, or approve on your phone.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _pin,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            obscureText: _obscure,
                            style: CbText.data.copyWith(
                              fontSize: 20,
                              letterSpacing: 8,
                            ),
                            onFieldSubmitted: (_) => _continue(),
                            decoration: InputDecoration(
                              labelText: 'Owner PIN',
                              counterText: '',
                              suffixIcon: IconButton(
                                tooltip: _obscure ? 'Show PIN' : 'Hide PIN',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                value == null ||
                                    !RegExp(r'^\d{6}$').hasMatch(value)
                                ? 'Enter all six digits'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: const TextStyle(color: CbInk.error),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _busy ? null : _continue,
                              child: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Unlock workspace'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _pickPhoneServer,
                            icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                            label: const Text('Sign in with your phone'),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Works without a Counterbase online account or POS server.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!widget.session.hasWorkspace) {
        await widget.session.createWorkspace(
          businessName: _business.text,
          ownerName: _owner.text,
          pin: _pin.text,
        );
      } else {
        await widget.session.login(_pin.text);
      }
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Navy instrument panel on the sign-in screen: blueprint grid, live facts.
class _LoginAside extends StatelessWidget {
  const _LoginAside({required this.isSetup});

  final bool isSetup;

  @override
  Widget build(BuildContext context) {
    final business = context
        .findAncestorStateOfType<_LoginScreenState>()
        ?.widget
        .session
        .businessName;
    return Container(
      color: CbInk.bg,
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                CbLogoMark(size: 34),
                SizedBox(width: 12),
                Text(
                  'Counterbase',
                  style: TextStyle(
                    fontFamily: 'CbDisplay',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: CbInk.text,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const CbTag('LOCAL-FIRST POINT OF SALE'),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Text(
                'The till that keeps working when the internet does not.',
                style: CbText.display.copyWith(fontSize: 38, height: 1.15),
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                'Checkout, stock and records run entirely on this computer. '
                'The database is encrypted with SQLCipher; the key never '
                'leaves the operating system credential store.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 34),
            // Workspace identity card — mirrors the mobile PIN screen's
            // GlassCard: tinted fill, radius 20, quiet border.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: CbInk.text.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CbInk.text.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: CbInk.success,
                      ),
                      SizedBox(width: 8),
                      Text('WORKSPACE STATUS', style: CbText.tag),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _AsideRow(
                    label: 'Mode',
                    value: isSetup ? 'Awaiting setup' : 'Locked',
                  ),
                  const SizedBox(height: 10),
                  _AsideRow(
                    label: 'Business',
                    value: isSetup ? 'Not yet created' : (business ?? '—'),
                  ),
                  const SizedBox(height: 10),
                  const _AsideRow(label: 'Storage', value: 'This computer'),
                  const SizedBox(height: 10),
                  const _AsideRow(label: 'Network', value: 'Not required'),
                ],
              ),
            ),
            const Spacer(),
            Text(
              'Arche Axon Intelligence',
              style: CbText.tag.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _AsideRow extends StatelessWidget {
  const _AsideRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 92, child: Text(label, style: CbText.tag)),
      Expanded(
        child: Text(
          value,
          style: CbText.data.copyWith(fontSize: 12.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
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

Color _productColor(String category) => productCategoryColor(category);

IconData _productIcon(String category) {
  final text = category.toLowerCase();
  if (text.contains('bever')) return Icons.local_drink_rounded;
  if (text.contains('food') ||
      text.contains('lunch') ||
      text.contains('break')) {
    return Icons.restaurant_rounded;
  }
  if (text.contains('dessert') || text.contains('bak')) {
    return Icons.cake_rounded;
  }
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
    final api = widget.session.workspace;
    final branchId = widget.session.branchId;
    try {
      final results = await Future.wait([
        api.getProducts(branchId: branchId),
        api.getCategories(),
        api.getCustomers(),
        api.getStock(branchId),
      ]);
      final loadedProducts = (results[0])
          .where((item) => item['isActive'] != false)
          .map(Product.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        products = loadedProducts;
        categories = results[1];
        customers = (results[2]).map(Customer.fromJson).toList();
        stock = results[3];
      });
      await _loadInsights();
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _loadError = 'Local records could not be loaded. $error',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadInsights() async {
    final branchId = widget.session.branchId;
    try {
      final results = await Future.wait([
        widget.session.workspace.getDashboard(branchId: branchId),
        widget.session.workspace.getSalesTrend(branchId: branchId),
        widget.session.workspace.getTopProducts(branchId: branchId),
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
                onSettings: _openLocalSettings,
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
          categories:
              categories
                  .map((item) => item['name']?.toString().trim() ?? '')
                  .where((name) => name.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
          onAdd: _add,
          onRemove: _remove,
          onCheckout: _checkout,
        );
      case 2:
        return _ProductsPage(
          products: products,
          categories: categories,
          api: widget.session.workspace,
          onChanged: _loadWorkspace,
        );
      case 3:
        return _CustomersPage(
          customers: customers,
          api: widget.session.workspace,
          onChanged: _loadWorkspace,
        );
      case 4:
        return _InventoryPage(
          products: products,
          workspace: widget.session.workspace,
          onChanged: _loadWorkspace,
        );
      case 5:
        return _ReportsPage(dashboard: dashboard, topProducts: topProducts);
      case 6:
        return DesktopAiScreen(
          session: widget.session,
          onOpenGatewaySettings: _openAxonGatewaySettings,
        );
      default:
        return _DashboardPage(
          dashboard: dashboard,
          trend: salesTrend,
          userName: widget.session.displayName,
        );
    }
  }

  Future<void> _openLocalSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Workspace settings'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.session.businessName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.offline_bolt_outlined),
                title: Text('Local workspace'),
                subtitle: Text(
                  'Sales, products, customers, and stock are stored on this device.',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  unawaited(_openAxonGatewaySettings());
                },
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Axon AI gateway settings'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _createPortableBackup(dialogContext),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Create portable encrypted backup'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _createCrossPlatformArchive(dialogContext),
                icon: const Icon(Icons.devices_rounded),
                label: const Text('Create cross-platform transfer'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  unawaited(_restorePortableBackup());
                },
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Restore portable backup'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  unawaited(_restoreLocalArchive());
                },
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Import shop transfer or archive'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  unawaited(
                    showDesktopArchiveHistoryDialog(
                      context,
                      widget.session.workspace,
                    ),
                  );
                },
                icon: const Icon(Icons.history_rounded),
                label: const Text('Browse imported archive history'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Database location',
                style: TextStyle(color: CbInk.ink2),
              ),
              const SizedBox(height: 6),
              SelectableText(
                widget.session.workspace.databasePath ?? 'Unavailable',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text(
                'This workspace does not sync. Portable backups preserve this desktop database. Cross-platform .cbarchive transfers carry products, customers, completed sales, and current stock. Split-payment detail stays in the imported archive for read-only review; it is not mapped into live desktop Finance, and customer debt balances and collections are not transferred. Supplier finance, photos, held carts, and device settings are also excluded. Restoring a portable backup replaces this computer’s current shop records and keeps an encrypted rollback copy.',
                style: TextStyle(color: CbInk.ink2, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              widget.session.signOut();
            },
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('Lock workspace'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAxonGatewaySettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AxonGatewaySettingsDialog(session: widget.session),
    );
  }

  Future<void> _createPortableBackup(BuildContext dialogContext) async {
    Navigator.pop(dialogContext);
    final passphrase = await _requestNewPortableBackupPassphrase();
    if (passphrase == null || !mounted) return;
    try {
      final path = await widget.session.workspace.createPortableBackup(
        passphrase: passphrase,
      );
      if (mounted) {
        _showMessage(
          'Encrypted shop backup saved to $path. Keep its password safe.',
        );
      }
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage('The encrypted backup could not be created. Try again.');
      }
    }
  }

  Future<void> _createCrossPlatformArchive(BuildContext dialogContext) async {
    Navigator.pop(dialogContext);
    final passphrase = await _requestNewPortableBackupPassphrase();
    if (passphrase == null || !mounted) return;
    try {
      final path = await widget.session.workspace.createCrossPlatformArchive(
        passphrase: passphrase,
      );
      if (mounted) {
        _showMessage(
          'Verified encrypted transfer saved to $path. It contains products, customers, completed sales, and current stock. Keep the password separately.',
        );
      }
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage('The cross-platform transfer could not be created.');
      }
    }
  }

  Future<void> _restorePortableBackup() async {
    final selected = await FilePicker.pickFile(
      dialogTitle: 'Choose an encrypted Counterbase backup',
      type: FileType.custom,
      allowedExtensions: const ['cbportable'],
    );
    final path = selected?.path;
    if (path == null || path.isEmpty || !mounted) return;
    final passphrase = await _requestPortableRestorePassphrase();
    if (passphrase == null || !mounted) return;

    late DesktopPortableBackupPreview preview;
    try {
      preview = await widget.session.workspace.inspectPortableBackup(
        path: path,
        passphrase: passphrase,
      );
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) _showMessage(error.message);
      return;
    } catch (_) {
      if (mounted) _showMessage('Counterbase could not inspect that backup.');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restore ${preview.businessName}?'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prepared for ${preview.ownerName}. It contains ${preview.products} products, ${preview.customers} customers and ${preview.sales} completed sales.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'Restoring replaces the shop records currently on this computer. Your Counterbase login PIN stays on this computer. An encrypted rollback copy of the current database is retained here in case recovery is needed.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'Only continue if you trust the backup and recognize this shop.',
                  style: TextStyle(color: CbInk.ink2),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Replace shop records'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 14),
            Text('Restoring encrypted shop records…'),
          ],
        ),
      ),
    );
    try {
      await widget.session.workspace.restorePortableBackup(
        path: path,
        passphrase: passphrase,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await widget.session.refreshWorkspaceProfile();
      await _loadWorkspace();
      _showMessage(
        'Restored ${preview.businessName}: ${preview.products} products, ${preview.customers} customers and ${preview.sales} sales.',
      );
    } on LocalWorkspaceFailure catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showMessage(
        'The backup could not be restored. The previous shop records were recovered.',
      );
    }
  }

  Future<String?> _requestNewPortableBackupPassphrase() {
    final controller = TextEditingController();
    final confirmation = TextEditingController();
    var errorText = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void submit() {
            if (controller.text.length < 12 ||
                controller.text.contains('\u0000')) {
              setDialogState(
                () => errorText =
                    'Use at least 12 characters without a null character.',
              );
              return;
            }
            if (controller.text != confirmation.text) {
              setDialogState(() => errorText = 'The passwords do not match.');
              return;
            }
            Navigator.pop(dialogContext, controller.text);
          }

          return AlertDialog(
            title: const Text('Protect portable backup'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose a password with at least 12 characters. You will need it to restore this backup on another computer. Counterbase cannot recover a forgotten password.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Backup password',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmation,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    errorText: errorText.isEmpty ? null : errorText,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('Create backup'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      controller.dispose();
      confirmation.dispose();
    });
  }

  Future<String?> _requestPortableRestorePassphrase() {
    final controller = TextEditingController();
    var errorText = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Unlock portable backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the password used when this backup was created.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Backup password',
                  errorText: errorText.isEmpty ? null : errorText,
                ),
                onSubmitted: (_) {
                  if (controller.text.length < 12) {
                    setDialogState(
                      () => errorText = 'Use at least 12 characters.',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, controller.text);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.length < 12) {
                  setDialogState(
                    () => errorText = 'Use at least 12 characters.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, controller.text);
              },
              child: const Text('Unlock backup'),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _restoreLocalArchive() async {
    final service = DesktopArchiveImportService();
    DesktopArchivePreview? preview;
    try {
      preview = await service.pickArchive(
        requestPassphrase: _requestArchivePassphrase,
      );
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) _showMessage(error.message);
      return;
    } catch (_) {
      if (mounted) _showMessage('The archive could not be opened.');
      return;
    }
    if (preview == null || !mounted) return;
    final selected = preview;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restore ${selected.tenantName}?'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The archive has ${selected.branches} branches, ${selected.products} products, ${selected.customers} customers and ${selected.sales} sales.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'A fresh workspace can adopt this shop. An existing shop can only merge an archive with the same shop identity. Matching records are kept, and the import commits as one transaction.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'The transfer file is password-encrypted. Supported products, stock, customers and completed sales enter the live local workspace. The full original archive is also retained inside this computer’s encrypted database for read-only browsing; it does not change live stock or financial totals. Keep the original file as an external backup.',
                  style: TextStyle(color: CbInk.ink2),
                ),
                const SizedBox(height: 14),
                Text(
                  'Prepared ${MaterialLocalizations.of(dialogContext).formatMediumDate(selected.createdAt.toLocal())}.',
                  style: const TextStyle(color: CbInk.ink2, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Restore shop records'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 14),
            Text('Restoring local records…'),
          ],
        ),
      ),
    );
    try {
      final result = await widget.session.workspace.importLegacyArchive(
        payload: selected.payload,
        archiveId: selected.archiveId,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await widget.session.refreshWorkspaceProfile();
      await _loadWorkspace();
      _showMessage(
        result.alreadyImported
            ? 'This archive was already imported. No duplicate records were added; its preserved history is available in Workspace settings.'
            : 'Archive restored for ${selected.tenantName}. Supported records are available offline, and the original encrypted snapshot is available in Workspace settings.',
      );
    } on LocalWorkspaceFailure catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showMessage(
        'The archive could not be restored. No partial import was kept.',
      );
    }
  }

  Future<String?> _requestArchivePassphrase() {
    final controller = TextEditingController();
    var errorText = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Unlock shop archive'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the password used when this archive was prepared.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Archive password',
                  errorText: errorText.isEmpty ? null : errorText,
                ),
                onSubmitted: (_) {
                  if (controller.text.length < 12) {
                    setDialogState(
                      () => errorText = 'Use at least 12 characters.',
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(controller.text);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.length < 12) {
                  setDialogState(
                    () => errorText = 'Use at least 12 characters.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: const Text('Unlock archive'),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  void _add(Product product) {
    final inCart = _cart[product] ?? 0;
    final available = product.stock.floor();
    if (inCart >= available) {
      _showMessage(
        available == 0
            ? '${product.name} is out of stock.'
            : 'Only $available units of ${product.name} are available.',
      );
      return;
    }
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
    var submitting = false;
    String? errorMessage;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => PopScope(
          canPop: !submitting,
          child: AlertDialog(
            title: const Text('Complete sale'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Record this cash sale on this device.'),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(errorMessage!, style: const TextStyle(color: CbInk.bad)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: submitting
                    ? null
                    : () async {
                        setDialogState(() {
                          submitting = true;
                          errorMessage = null;
                        });
                        try {
                          await widget.session.workspace.createSale({
                            'branchId': widget.session.branchId,
                            'deviceId': widget.session.deviceId,
                            'paymentMethod': 'CASH',
                            'paidAmount': _cart.entries.fold<double>(
                              0,
                              (sum, entry) =>
                                  sum + entry.key.price * entry.value,
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
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (!mounted) return;
                          setState(_cart.clear);
                          _showMessage('Sale completed successfully.');
                          await _loadWorkspace();
                        } on LocalWorkspaceFailure catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              submitting = false;
                              errorMessage = error.message;
                            });
                          }
                        } catch (_) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              submitting = false;
                              errorMessage =
                                  'The sale could not be confirmed. Check Sales before trying again.';
                            });
                          }
                        }
                      },
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.payments_outlined),
                label: Text(
                  submitting ? 'Recording sale…' : 'Record cash sale',
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                  Text('Loading your local workspace…'),
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
                        color: CbInk.warn,
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
                        style: const TextStyle(color: CbInk.ink2),
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

class _AxonGatewaySettingsDialog extends StatefulWidget {
  const _AxonGatewaySettingsDialog({required this.session});

  final DesktopSession session;

  @override
  State<_AxonGatewaySettingsDialog> createState() =>
      _AxonGatewaySettingsDialogState();
}

class _AxonGatewaySettingsDialogState
    extends State<_AxonGatewaySettingsDialog> {
  final _keyController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _hasKey = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final hasKey = await widget.session.hasAxonGatewayKey();
      if (mounted) setState(() => _hasKey = hasKey);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'The secure credential store is unavailable.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_keyController.text.trim().isEmpty) {
      setState(() => _message = 'Enter the Axon Gateway key first.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.session.saveAxonGatewayKey(_keyController.text);
      _keyController.clear();
      if (mounted) {
        setState(() {
          _hasKey = true;
          _message = 'Key saved in this computer’s secure credential store.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not save the key securely. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.session.removeAxonGatewayKey();
      if (mounted) {
        setState(() {
          _hasKey = false;
          _message = 'Saved Axon Gateway key removed from this computer.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not remove the saved key. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.auto_awesome_rounded),
        SizedBox(width: 10),
        Text('Axon AI Gateway'),
      ],
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The app connects only to gateway.archeaxon.com. Add the key issued for this installation; it is stored in the operating system credential store.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _keyController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            decoration: const InputDecoration(
              labelText: 'Axon Gateway key',
              hintText: 'Paste the key issued for this computer',
              prefixIcon: Icon(Icons.key_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _hasKey ? Icons.verified_user_rounded : Icons.lock_outline,
                size: 18,
                color: _hasKey ? CbInk.ok : CbInk.ink2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _loading
                      ? 'Checking secure storage…'
                      : _hasKey
                      ? 'A key is saved securely on this computer.'
                      : 'No key is saved on this computer.',
                  style: const TextStyle(color: CbInk.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Axon AI uses this key only for requests to gateway.archeaxon.com. Local lookups are read-only; customer personal data and business changes are unavailable to the assistant.',
            style: TextStyle(color: CbInk.ink2, fontSize: 12),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(color: CbInk.ink2)),
          ],
        ],
      ),
    ),
    actions: [
      if (_hasKey)
        TextButton(
          onPressed: _saving ? null : _remove,
          child: const Text('Remove key'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_rounded),
        label: const Text('Save key'),
      ),
    ],
  );
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.selected,
    required this.extended,
    required this.onSelected,
    required this.onSettings,
  });

  final int selected;
  final bool extended;
  final ValueChanged<int> onSelected;
  final VoidCallback onSettings;
  static const items = <(IconData, String)>[
    (Icons.grid_view_outlined, 'Overview'),
    (Icons.point_of_sale_outlined, 'Point of sale'),
    (Icons.inventory_2_outlined, 'Products'),
    (Icons.people_alt_outlined, 'Customers'),
    (Icons.warehouse_outlined, 'Inventory'),
    (Icons.insights_outlined, 'Reports'),
    (Icons.auto_awesome_outlined, 'Axon AI'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: extended ? 232 : 68,
      decoration: const BoxDecoration(
        color: CbInk.ground,
        border: Border(right: BorderSide(color: CbInk.hairline)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 14, 24),
            child: Row(
              children: [
                const CbLogoMark(size: 30),
                if (extended) ...[
                  const SizedBox(width: 11),
                  const Text(
                    'Counterbase',
                    style: TextStyle(
                      fontFamily: 'CbDisplay',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: CbInk.text,
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
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Tooltip(
                    message: item.$2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => onSelected(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.symmetric(
                          horizontal: extended ? 12 : 0,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? CbInk.action.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border(
                            left: BorderSide(
                              width: 2,
                              color: active ? CbInk.action : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.$1,
                              size: 19,
                              color: active ? CbInk.action : CbInk.muted,
                            ),
                            if (extended) ...[
                              const SizedBox(width: 12),
                              Text(
                                item.$2,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: active ? CbInk.ink : CbInk.ink2,
                                  fontWeight: active
                                      ? FontWeight.w600
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
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onSettings,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: extended ? 12 : 0,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.settings_outlined,
                      size: 19,
                      color: CbInk.muted,
                    ),
                    if (extended) ...[
                      const SizedBox(width: 12),
                      const Text(
                        'Settings',
                        style: TextStyle(fontSize: 13.5, color: CbInk.ink2),
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
      'Axon AI',
    ];
    final index = page < 0 || page >= titles.length ? 0 : page;
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: CbInk.ground,
        border: Border(bottom: BorderSide(color: CbInk.hairline)),
      ),
      child: Row(
        children: [
          Text(
            '${'0${index + 1}'} · ${titles[index].toUpperCase()}',
            style: CbText.tag.copyWith(fontSize: 12, color: CbInk.ink2),
          ),
          const SizedBox(width: 18),
          Container(width: 1, height: 22, color: CbInk.hairline),
          const SizedBox(width: 18),
          Text(titles[index], style: CbText.display.copyWith(fontSize: 22)),
          const Spacer(),
          if (index == 0)
            FilledButton.icon(
              onPressed: onNewSale,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New sale'),
            ),
          const SizedBox(width: 14),
          IconButton(
            tooltip: 'Refresh local data',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          const SizedBox(width: 10),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CbInk.navy,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: CbInk.hairline),
            ),
            child: Text(
              _initials(session.displayName),
              style: CbText.data.copyWith(
                fontSize: 12,
                color: CbInk.action,
                fontWeight: FontWeight.w600,
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
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: CbInk.ink,
                ),
              ),
              Text('Workspace owner', style: CbText.tag.copyWith(fontSize: 10)),
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
          const CbTag('LOCAL WORKSPACE · TODAY'),
          const SizedBox(height: 12),
          Text(
            'Good to see you, $name.',
            style: CbText.display.copyWith(fontSize: 32),
          ),
          const SizedBox(height: 8),
          Text(
            'Today’s sales and stock on this device.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
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
                color: CbInk.success,
              ),
              _MetricCard(
                title: 'Transactions',
                value: _number(sales['totalSales']).toStringAsFixed(0),
                change:
                    '${_number(sales['uniqueCustomers']).toStringAsFixed(0)} customers',
                icon: Icons.receipt_long_rounded,
                color: CbInk.accent,
              ),
              _MetricCard(
                title: 'Average order',
                value: _money(_number(sales['averageTicket'])),
                change: 'Recorded today',
                icon: Icons.shopping_cart_rounded,
                color: CbInk.info,
              ),
              _MetricCard(
                title: 'Low stock items',
                value: _number(inventory['lowStockItems']).toStringAsFixed(0),
                change: 'Needs attention',
                icon: Icons.inventory_2_rounded,
                color: CbInk.error,
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
          const CbTag('LOCAL SNAPSHOT'),
          const SizedBox(height: 18),
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
      Icon(icon, size: 17, color: CbInk.action),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 13.5, color: CbInk.ink2),
        ),
      ),
      Text(
        value,
        style: CbText.data.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      ),
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
    width: 232,
    // Mobile MetricCard pattern: ClipRRect + left accent bar, value in
    // tabular mono, uppercase tracked title.
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
            decoration: BoxDecoration(
              color: CbInk.surface,
              border: Border.all(color: CbInk.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: CbText.data.copyWith(
                    fontSize: 22,
                    color: CbInk.text,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CbText.tag.copyWith(fontSize: 10.5),
                ),
                const SizedBox(height: 3),
                Text(
                  change,
                  style: CbText.tag.copyWith(fontSize: 10, color: color),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: color),
          ),
        ],
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CbTag('SALES PERFORMANCE'),
                    SizedBox(height: 8),
                    Text('Last 7 days', style: CbText.tag),
                  ],
                ),
                Text('FIG. 01', style: CbText.tag.copyWith(fontSize: 10)),
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
                        Text(
                          'No sales recorded for this period',
                          style: Theme.of(context).textTheme.bodyMedium,
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
                  Text(day, style: CbText.tag.copyWith(fontSize: 10)),
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
    width: 26,
    height: 150 * value,
    decoration: const BoxDecoration(
      color: CbInk.action,
      borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
    ),
  );
}

class _PosPage extends StatefulWidget {
  const _PosPage({
    required this.cart,
    required this.products,
    required this.categories,
    required this.onAdd,
    required this.onRemove,
    required this.onCheckout,
  });
  final Map<Product, int> cart;
  final List<Product> products;
  final List<String> categories;
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
    final categoryOptions = ['All products', ...widget.categories];
    final selectedCategory = categoryOptions.contains(category)
        ? category
        : 'All products';
    final normalizedQuery = query.trim().toLowerCase();
    final visible = widget.products.where((product) {
      final matchesQuery =
          normalizedQuery.isEmpty ||
          product.name.toLowerCase().contains(normalizedQuery) ||
          product.sku.toLowerCase().contains(normalizedQuery);
      final matchesCategory =
          selectedCategory == 'All products' ||
          product.category == selectedCategory;
      return matchesQuery && matchesCategory;
    }).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 950) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _catalog(
                    visible,
                    categoryOptions,
                    selectedCategory,
                    scrollableGrid: true,
                  ),
                ),
                const SizedBox(width: 18),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(child: _cartPanel()),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: [
                _catalog(
                  visible,
                  categoryOptions,
                  selectedCategory,
                  scrollableGrid: false,
                ),
                const SizedBox(height: 18),
                _cartPanel(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _catalog(
    List<Product> visible,
    List<String> categoryOptions,
    String selectedCategory, {
    required bool scrollableGrid,
  }) {
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
                  hintText: 'Search name or SKU, or scan a barcode',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final item in categoryOptions)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item),
                    selected: selectedCategory == item,
                    onSelected: (_) => setState(() => category = item),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (visible.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.products.isEmpty
                          ? Icons.inventory_2_outlined
                          : Icons.search_off_rounded,
                      size: 34,
                      color: CbInk.ink2,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.products.isEmpty
                          ? 'No products yet'
                          : 'No matching products',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.products.isEmpty
                          ? 'Add products in the catalog to start a sale.'
                          : 'Try another name, SKU, or category.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: CbInk.ink2),
                    ),
                    if (query.isNotEmpty || selectedCategory != 'All products')
                      TextButton(
                        onPressed: () => setState(() {
                          query = '';
                          category = 'All products';
                        }),
                        child: const Text('Clear search and filters'),
                      ),
                  ],
                ),
              ),
            ),
          )
        else if (scrollableGrid)
          Expanded(child: _productGrid(visible, scrollable: true))
        else
          _productGrid(visible, scrollable: false),
      ],
    );
  }

  Widget _productGrid(List<Product> visible, {required bool scrollable}) =>
      GridView.builder(
        shrinkWrap: !scrollable,
        physics: scrollable ? null : const NeverScrollableScrollPhysics(),
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
      );

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
                const CbTag('CURRENT SALE'),
                Text(
                  '${widget.cart.values.fold<int>(0, (sum, quantity) => sum + quantity)} items',
                  style: CbText.tag.copyWith(fontSize: 10.5),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.cart.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 70),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.point_of_sale_outlined,
                        size: 38,
                        color: CbInk.navy3,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Cart is empty',
                        style: TextStyle(
                          color: CbInk.ink2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Select a product to begin',
                        style: CbText.tag.copyWith(fontSize: 10.5),
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
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Total',
                value: 'KES ${total.toStringAsFixed(0)}',
                strong: true,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: widget.onCheckout,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Continue to payment'),
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
      borderRadius: BorderRadius.circular(10),
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
                  color: product.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: product.color.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(product.icon, size: 36, color: product.color),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: CbInk.ink,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'KES ${product.price.toStringAsFixed(0)}',
                  style: CbText.data.copyWith(
                    fontSize: 13,
                    color: CbInk.action,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${product.stock} left',
                  style: CbText.tag.copyWith(fontSize: 10),
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
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: product.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: product.color.withValues(alpha: 0.25)),
          ),
          child: Icon(product.icon, size: 17, color: product.color),
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
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: CbInk.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'KES ${(product.price * count).toStringAsFixed(0)}',
                style: CbText.data.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onRemove,
          icon: const Icon(
            Icons.remove_circle_outline,
            size: 18,
            color: CbInk.muted,
          ),
        ),
        Text(
          '$count',
          style: CbText.data.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onAdd,
          icon: const Icon(
            Icons.add_circle_outline,
            size: 18,
            color: CbInk.action,
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
        strong ? label.toUpperCase() : label,
        style: strong
            ? CbText.tag.copyWith(color: CbInk.ink)
            : const TextStyle(fontSize: 13.5, color: CbInk.ink2),
      ),
      Text(
        value,
        style: strong
            ? CbText.data.copyWith(
                fontSize: 22,
                color: CbInk.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              )
            : CbText.data.copyWith(fontSize: 13),
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
  final DesktopWorkspaceStore api;
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
          const CbTag('CATALOG'),
          const SizedBox(height: 10),
          Text('Product catalog', style: CbText.display.copyWith(fontSize: 30)),
          const SizedBox(height: 6),
          const Text(
            'Manage prices, stock, categories and product codes from one workspace.',
            style: TextStyle(color: CbInk.ink2),
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
                                style: const TextStyle(color: CbInk.ink2),
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
      color: product.color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: product.color.withValues(alpha: 0.25)),
    ),
    child: Icon(product.icon, size: 17, color: product.color),
  );
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    required this.api,
    required this.categories,
    this.product,
  });

  final DesktopWorkspaceStore api;
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
  late final TextEditingController _minimum;
  late final TextEditingController _unit;
  late final TextEditingController _openingStock;
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
    _minimum = TextEditingController(
      text: product == null ? '0' : product.minStock.toStringAsFixed(0),
    );
    _unit = TextEditingController(text: product?.unit ?? 'piece');
    _openingStock = TextEditingController(text: '0');
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
    _minimum.dispose();
    _unit.dispose();
    _openingStock.dispose();
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
              if (widget.product == null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _openingStock,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Opening stock',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (value) => _number(value) < 0
                      ? 'Opening stock cannot be negative'
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
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
                    style: const TextStyle(color: CbInk.bad),
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
      if (widget.product == null) 'initialStock': _number(_openingStock.text),
      'unit': _unit.text.trim().isEmpty ? 'piece' : _unit.text.trim(),
      if (_sku.text.trim().isNotEmpty) 'sku': _sku.text.trim(),
      if (_categoryId != null) 'categoryIds': [_categoryId],
    };
    try {
      if (widget.product == null) {
        await widget.api.createProduct(payload);
      } else {
        await widget.api.updateProduct(widget.product!.id, payload);
      }
      if (mounted) Navigator.pop(context, true);
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
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
  final DesktopWorkspaceStore api;
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
                  CbTag('CUSTOMERS'),
                  SizedBox(height: 10),
                  Text(
                    'Customers',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.2,
                      color: CbInk.ink,
                      fontFamily: 'CbDisplay',
                      height: 1.12,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Keep customer history and relationships close to every sale.',
                    style: TextStyle(color: CbInk.ink2),
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
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: CbInk.navy,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: CbInk.hairline),
                              ),
                              child: Text(
                                customer.name.substring(0, 1).toUpperCase(),
                                style: CbText.data.copyWith(
                                  fontSize: 13,
                                  color: CbInk.action,
                                  fontWeight: FontWeight.w600,
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
                                color: CbInk.muted,
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

  final DesktopWorkspaceStore api;
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
                child: Text(_error!, style: const TextStyle(color: CbInk.bad)),
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
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
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
            Icon(icon, size: 20, color: CbInk.action),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: CbText.tag),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: CbText.data.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: CbInk.ink,
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
  const _InventoryPage({
    required this.products,
    required this.workspace,
    required this.onChanged,
  });

  final List<Product> products;
  final DesktopWorkspaceStore workspace;
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
                  CbTag('INVENTORY'),
                  SizedBox(height: 10),
                  Text(
                    'Inventory control',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.2,
                      color: CbInk.ink,
                      fontFamily: 'CbDisplay',
                      height: 1.12,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'See what is moving, what is low, and what needs a reorder.',
                    style: TextStyle(color: CbInk.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: products.isEmpty ? null : () => _adjustStock(context),
              icon: const Icon(Icons.inventory_rounded),
              label: const Text('Adjust stock'),
            ),
          ],
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
                              backgroundColor: CbInk.navy,
                              color: product.stock < 10
                                  ? CbInk.bad
                                  : CbInk.action,
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
                                  ? CbInk.bad
                                  : CbInk.ink2,
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

  Future<void> _adjustStock(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _StockAdjustmentDialog(products: products, workspace: workspace),
    );
    if (saved == true) await onChanged();
  }
}

class _StockAdjustmentDialog extends StatefulWidget {
  const _StockAdjustmentDialog({
    required this.products,
    required this.workspace,
  });

  final List<Product> products;
  final DesktopWorkspaceStore workspace;

  @override
  State<_StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  late String? _productId = widget.products.firstOrNull?.id;
  final _quantity = TextEditingController(text: '1');
  bool _adding = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Adjust stock'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _productId,
            decoration: const InputDecoration(labelText: 'Product'),
            items: [
              for (final product in widget.products)
                DropdownMenuItem(value: product.id, child: Text(product.name)),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _productId = value),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Add stock'),
                icon: Icon(Icons.add_rounded),
              ),
              ButtonSegment(
                value: false,
                label: Text('Remove'),
                icon: Icon(Icons.remove_rounded),
              ),
            ],
            selected: {_adding},
            onSelectionChanged: _saving
                ? null
                : (selection) => setState(() => _adding = selection.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: CbInk.bad)),
          ],
        ],
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
            : const Text('Save adjustment'),
      ),
    ],
  );

  Future<void> _save() async {
    final amount = double.tryParse(_quantity.text.trim());
    if (_productId == null || amount == null || amount <= 0) {
      setState(
        () => _error = 'Choose a product and enter a quantity above zero.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.workspace.adjustStock({
        'productId': _productId,
        'quantity': amount,
        'direction': _adding ? 'ADD' : 'REMOVE',
      });
      if (mounted) Navigator.pop(context, true);
    } on LocalWorkspaceFailure catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    }
  }
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
          const CbTag('REPORTS'),
          const SizedBox(height: 10),
          Text(
            'Reports & insights',
            style: CbText.display.copyWith(fontSize: 30),
          ),
          const SizedBox(height: 6),
          const Text(
            'Make better operating decisions from one clear view of the business.',
            style: TextStyle(color: CbInk.ink2),
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
                        style: TextStyle(color: CbInk.ink2, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  if (topProducts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Text(
                        'No sales data is available for this period.',
                        style: TextStyle(color: CbInk.ink2),
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
                                  backgroundColor: CbInk.navy,
                                  color: CbInk.action,
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
          Icon(icon, size: 20, color: CbInk.action),
          const SizedBox(height: 18),
          Text(title.toUpperCase(), style: CbText.tag),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CbText.data.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: CbInk.ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(detail, style: CbText.tag.copyWith(fontSize: 10.5)),
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
    final color = good ? CbInk.ok : CbInk.bad;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label.toUpperCase(),
        style: CbText.tag.copyWith(fontSize: 10, color: color),
      ),
    );
  }
}
