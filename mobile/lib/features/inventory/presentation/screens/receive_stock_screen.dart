import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../../catalog/domain/stock_status.dart';
import '../../../catalog/presentation/screens/barcode_scan_screen.dart';
import '../../../catalog/presentation/widgets/stock_kit.dart';
import '../../../sales/presentation/providers/catalog_provider.dart'
    as catalog_cache;

/// One product in a delivery.
class _Line {
  _Line({required this.product, required this.tiers, double quantity = 1})
      : unit = product.unit,
        quantity = TextEditingController(text: kitNumber(quantity)),
        cost = TextEditingController(
          text: (product.costPrice ?? 0) > 0 ? kitNumber(product.costPrice!) : '',
        );

  final Product product;
  final List<ProductPricingTier> tiers;
  final TextEditingController quantity;
  final TextEditingController cost;
  String unit;

  /// How many of the product's own unit one of [unit] holds.
  double get factor {
    if (unit == product.unit) return 1;
    for (final tier in tiers) {
      if (tier.unit == unit) return tier.quantityPerUnit;
    }
    return 1;
  }

  double get entered => double.tryParse(quantity.text.trim()) ?? 0;
  double get base => entered * factor;
  double? get costEach {
    final value = double.tryParse(cost.text.trim());
    return value == null || value <= 0 ? null : value;
  }

  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

/// Receive a delivery of one or many products in one go. Counts go up, every
/// line lands in that product's history, and a buying price is remembered for
/// next time. A buying price is optional.
class ReceiveStockScreen extends ConsumerStatefulWidget {
  const ReceiveStockScreen({super.key, this.productId});

  /// A product to start the delivery with, when opened from its page.
  final String? productId;

  @override
  ConsumerState<ReceiveStockScreen> createState() => _ReceiveStockScreenState();
}

class _ReceiveStockScreenState extends ConsumerState<ReceiveStockScreen> {
  final List<_Line> _lines = [];
  final TextEditingController _supplier = TextEditingController();
  final TextEditingController _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final id = widget.productId;
    if (id != null && id.isNotEmpty) _addById(id);
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _supplier.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addById(String productId) async {
    final db = getIt<AppDatabase>();
    final product = await db.getProduct(productId);
    if (product == null || !mounted) return;
    await _add(product);
  }

  Future<void> _add(Product product) async {
    if (_lines.any((l) => l.product.id == product.id)) {
      final existing = _lines.firstWhere((l) => l.product.id == product.id);
      final next = existing.entered + 1;
      setState(() => existing.quantity.text = kitNumber(next));
      return;
    }
    final tiers = await getIt<AppDatabase>().getPricingTiersForProduct(product.id);
    if (!mounted) return;
    setState(() => _lines.add(_Line(product: product, tiers: tiers)));
  }

  Future<void> _pick() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SignInPalette.of(context).card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => const _ProductPickerSheet(),
    );
    if (product != null) await _add(product);
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
          builder: (_) => const BarcodeScanScreen(title: 'Scan an item')),
    );
    if (code == null || !mounted) return;
    final all = await getIt<AppDatabase>()
        .watchCatalogProducts(isActive: true)
        .first;
    final wanted = code.toUpperCase();
    final match = all.where((p) => p.sku.toUpperCase() == wanted).toList();
    if (!mounted) return;
    if (match.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No product has the code $code. Add it under Products first.')),
      );
      return;
    }
    await _add(match.first);
  }

  double get _totalBase => _lines.fold(0, (sum, l) => sum + l.base);

  double? get _totalPaid {
    if (_lines.isEmpty || _lines.any((l) => l.costEach == null)) return null;
    return _lines.fold<double>(0, (sum, l) => sum + l.costEach! * l.base);
  }

  Future<void> _save() async {
    final valid = _lines.where((l) => l.entered > 0).toList();
    if (valid.isEmpty) {
      setState(() => _error = 'Add at least one item with a count above zero.');
      return;
    }
    for (final line in valid) {
      if (!line.product.allowFractions && line.entered % 1 != 0) {
        setState(() =>
            _error = '${line.product.name} is sold in whole units. Use a whole number.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = getIt<AppDatabase>();
      final branchId = getIt<StorageService>().getBranchId();
      if (branchId == null || branchId.isEmpty) {
        throw StateError('The shop branch is missing. Reopen setup.');
      }
      final delivery = const Uuid().v4();
      final supplier = _supplier.text.trim();
      final note = _note.text.trim();
      final now = DateTime.now();
      for (var i = 0; i < valid.length; i++) {
        final line = valid[i];
        await db.recordLocalStockReceipt(
          receiptId: '$delivery-$i',
          productId: line.product.id,
          branchId: branchId,
          batches: [
            {
              'quantity': line.entered,
              'unit': line.unit,
              'unitsPerQuantity': line.factor,
              if (line.costEach != null) 'costPrice': line.costEach,
              if (supplier.isNotEmpty) 'supplierRef': supplier,
              if (note.isNotEmpty) 'notes': note,
            },
          ],
          receivedAt: now,
        );
        if (line.costEach != null) {
          await db.setProductCostPrice(line.product.id, line.costEach);
        }
      }
      ref.invalidate(catalog_cache.filteredProductsProvider);
      ref.invalidate(catalog_cache.favoriteProductsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Saved. ${stockNumber(_totalBase)} received across ${valid.length} ${valid.length == 1 ? 'product' : 'products'}.'),
        ),
      );
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/products');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final paid = _totalPaid;
    final products = _lines.where((l) => l.entered > 0).length;
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/products'),
        ),
        title: Text('Receive stock',
            style: DesignType.display.copyWith(
                color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              // Room above the first field so its floating label clears the
              // header line.
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                TextField(
                  controller: _supplier,
                  style: TextStyle(color: palette.ink),
                  textCapitalization: TextCapitalization.words,
                  decoration: kitFieldDecoration(context,
                      label: 'From (optional)', hint: 'For example, Mama Njeri Wholesalers'),
                ),
                const SizedBox(height: 20),
                Text('DELIVERED',
                    style: DesignType.numeric(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: palette.soft,
                        letterSpacing: 1.1)),
                const SizedBox(height: 10),
                if (_lines.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                      border: Border.all(color: palette.line),
                    ),
                    child: Text(
                      'Scan or add each item that arrived. You can do ten in about a minute.',
                      style: TextStyle(color: palette.soft, height: 1.4),
                    ),
                  )
                else
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                      border: Border.all(color: palette.line),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _lines.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: palette.line),
                          _lineTile(palette, _lines[i]),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _scan,
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                        label: const Text('Scan item'),
                        style: _outline(palette),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pick,
                        icon: const Icon(Icons.add_rounded, size: 19),
                        label: const Text('Add item'),
                        style: _outline(palette),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DesignColors.peach,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Text(
                    'Buying prices are optional. When you add them, each product shows its profit.',
                    style: TextStyle(color: Color(0xFF5A2A0E), fontSize: 13, height: 1.4),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _note,
                  style: TextStyle(color: palette.ink),
                  decoration: kitFieldDecoration(context, label: 'Note (optional)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  SignInError(message: _error!),
                ],
              ],
            ),
          ),
          PinnedActionBar(
            summary: _lines.isEmpty
                ? null
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${stockNumber(_totalBase)} ${_totalBase == 1 ? 'item' : 'items'} in $products ${products == 1 ? 'product' : 'products'}',
                          style: TextStyle(color: palette.soft, fontSize: 13),
                        ),
                      ),
                      if (paid != null)
                        Text('${formatMoney(paid)} paid',
                            style: DesignType.numeric(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: palette.ink)),
                    ],
                  ),
            child: SignInButton(
              label: _busy ? 'Saving…' : 'Save delivery',
              onPressed: _busy || _lines.isEmpty ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _outline(SignInPalette palette) => OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      );

  Widget _lineTile(SignInPalette palette, _Line line) {
    Widget step(IconData icon, String label, double by) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: () {
              final next = (line.entered + by).clamp(0, 1e9).toDouble();
              setState(() => line.quantity.text = kitNumber(next));
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.field,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.line),
              ),
              child: Icon(icon, size: 19, color: palette.ink),
            ),
          ),
        );
    final units = [
      line.product.unit,
      for (final t in line.tiers) t.unit,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(line.product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: palette.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              step(Icons.remove_rounded, 'One less', -1),
              SizedBox(
                width: 56,
                child: TextField(
                  controller: line.quantity,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: DesignType.numeric(
                      fontSize: 15, fontWeight: FontWeight.w700, color: palette.ink),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              step(Icons.add_rounded, 'One more', 1),
              IconButton(
                tooltip: 'Remove from this delivery',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: Icon(Icons.close_rounded, size: 18, color: palette.soft),
                onPressed: () => setState(() {
                  _lines.remove(line);
                  line.dispose();
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (units.length > 1) ...[
                SizedBox(
                  width: 112,
                  child: DropdownButtonFormField<String>(
                    initialValue: line.unit,
                    isExpanded: true,
                    decoration: kitFieldDecoration(context, label: 'Counted in'),
                    items: [
                      for (final u in units) DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (v) => setState(() => line.unit = v ?? line.unit),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: TextField(
                  controller: line.cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: palette.ink, fontWeight: FontWeight.w600),
                  decoration: kitFieldDecoration(
                    context,
                    label: 'Price paid for each ${line.product.unit} (optional)',
                    prefixText: 'KES ',
                    hint: '0',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A searchable list of the products that are counted, to add to a delivery.
class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final TextEditingController _query = TextEditingController();
  late final Future<List<Product>> _products = getIt<AppDatabase>()
      .watchCatalogProducts(isActive: true)
      .first
      .then((all) =>
          all.where((p) => p.trackInventory).toList()
            ..sort((a, b) => a.name.compareTo(b.name)));

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: palette.line, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _query,
                    autofocus: true,
                    style: TextStyle(color: palette.ink),
                    decoration: kitFieldDecoration(context,
                        label: 'Find an item', hint: 'Name or code'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Product>>(
                future: _products,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final q = _query.text.trim().toLowerCase();
                  final shown = snapshot.data!
                      .where((p) =>
                          q.isEmpty ||
                          p.name.toLowerCase().contains(q) ||
                          p.sku.toLowerCase().contains(q))
                      .toList();
                  if (shown.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          q.isEmpty
                              ? 'No counted products yet. Add one under Products.'
                              : 'Nothing matches "${_query.text.trim()}".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.soft),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: palette.line),
                    itemBuilder: (context, index) {
                      final p = shown[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: ProductAvatar(name: p.name, imageUrl: p.imageUrl),
                        title: Text(p.name,
                            style: TextStyle(
                                color: palette.ink, fontWeight: FontWeight.w600)),
                        subtitle: Text('per ${p.unit}',
                            style: TextStyle(color: palette.soft, fontSize: 12)),
                        onTap: () => Navigator.of(context).pop(p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
