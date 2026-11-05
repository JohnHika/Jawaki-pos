import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../../sales/presentation/providers/catalog_provider.dart'
    as catalog_cache;
import '../../domain/stock_status.dart';
import '../widgets/add_edit_product_sheet.dart';
import '../widgets/stock_kit.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  Product? _product;
  List<ProductPricingTier> _pricingTiers = [];
  LocalStockData? _stock;
  List<StockMovement> _history = const [];
  StreamSubscription<LocalStockData?>? _stockSubscription;
  String _categoryName = 'Uncategorized';
  bool _isLoading = true;

  static final _day = DateFormat('EEE d MMM');
  static final _time = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _stockSubscription = getIt<AppDatabase>()
        .watchStockForProduct(widget.productId)
        .listen((stock) {
      if (!mounted) return;
      setState(() => _stock = stock);
      _loadHistory();
    });
    _loadProduct();
  }

  @override
  void dispose() {
    _stockSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    try {
      final db = getIt<AppDatabase>();
      final product = await db.getProduct(widget.productId);
      if (product == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final categories = await db.getAllCategories();
      final categoryMap = {for (final c in categories) c.id: c.name};
      final tiers = await db.getPricingTiersForProduct(widget.productId);
      if (!mounted) return;
      setState(() {
        _product = product;
        _pricingTiers = tiers;
        _categoryName = categoryMap[product.categoryId] ?? 'Uncategorized';
        _isLoading = false;
      });
      _loadHistory();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadHistory() async {
    if (!getIt<AuthService>().isLocalWorkspace) return;
    try {
      final rows = await getIt<AppDatabase>()
          .getLocalProductStockHistory(widget.productId, limit: 40);
      if (!mounted) return;
      setState(() {
        _history = [
          for (final row in rows)
            StockMovement(
              kind: switch (row['kind']) {
                'sale' => StockMovementKind.sale,
                'delivery' => StockMovementKind.delivery,
                _ => StockMovementKind.correction,
              },
              at: row['at'] as DateTime,
              quantity: (row['quantity'] as num).toDouble(),
              note: row['note'] as String?,
              unitCost: (row['unitCost'] as num?)?.toDouble(),
            ),
        ];
      });
    } catch (_) {
      // History is a convenience. The product page still works without it.
    }
  }

  Future<void> _edit() async {
    final product = _product;
    if (product == null) return;
    await openProductForm(
      context,
      product: product,
      entityLabel: ref.read(businessLayoutProvider).productSingular,
    );
    if (mounted) _loadProduct();
  }

  Future<void> _receive() async {
    await context.push('/inventory/receive?productId=${widget.productId}');
    if (mounted) {
      _loadProduct();
    }
  }

  Future<void> _remove() async {
    final product = _product;
    if (product == null) return;
    final palette = SignInPalette.of(context);
    final isLocal = getIt<AuthService>().isLocalWorkspace;
    final bringBack = isLocal && !product.isActive;
    final go = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: palette.line, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                bringBack ? 'Bring back ${product.name}?' : 'Remove ${product.name}?',
                style: DesignType.display.copyWith(
                    color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                bringBack
                    ? 'It shows on Sell and in the list again.'
                    : isLocal
                        ? 'It stops showing on Sell and in the list. Past sales and receipts keep its name. You can bring it back from Products, the filter button, Show removed products.'
                        : 'This removes it from the catalog.',
                style: TextStyle(color: palette.soft, fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(sheet, true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  backgroundColor:
                      bringBack ? DesignColors.accent : const Color(0xFFC0392B),
                  foregroundColor:
                      bringBack ? DesignColors.textPrimary : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(bringBack ? 'Bring it back' : 'Remove product',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(sheet, false),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 46), foregroundColor: palette.soft),
                child: Text(bringBack ? 'Cancel' : 'Keep it',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    try {
      if (isLocal) {
        await getIt<AppDatabase>()
            .setLocalProductActive(product.id, isActive: bringBack);
      } else {
        await getIt<ApiClient>().deleteProduct(product.id);
        await catalog_cache.deleteProductFromCache(product.id);
      }
      ref.invalidate(catalog_cache.filteredProductsProvider);
      ref.invalidate(catalog_cache.favoriteProductsProvider);
      ref.invalidate(catalog_cache.categoriesProvider);
      if (!mounted) return;
      if (bringBack) {
        _loadProduct();
      } else if (context.canPop()) {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update the product. ${apiErrorMessage(e)}'),
          backgroundColor: DesignColors.error,
        ),
      );
    }
  }

  Future<void> _correctCount() async {
    final product = _product;
    if (product == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SignInPalette.of(context).card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheet) => _CorrectCountSheet(
        product: product,
        current: _stock?.quantity.toDouble() ?? 0,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Count corrected. It is in the history.')),
      );
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final perms = ref.watch(permissionsProvider);
    final product = _product;
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/products'),
        ),
        title: Text(
          product?.name ?? 'Product',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesignType.display.copyWith(
              color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (product != null && perms.canEditProducts)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == 'edit') _edit();
                if (value == 'remove') _remove();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    getIt<AuthService>().isLocalWorkspace && !product.isActive
                        ? 'Bring it back'
                        : 'Remove product',
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : product == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text('This product is no longer here.',
                          style: TextStyle(color: palette.soft)),
                    ),
                  )
                : _content(context, palette, product, perms.canManageStock,
                    perms.canEditProducts),
      ),
    );
  }

  Widget _content(BuildContext context, SignInPalette palette, Product product,
      bool canReceive, bool canEdit) {
    final qty = _stock?.quantity.toDouble();
    final level = stockLevelFor(
      trackInventory: product.trackInventory,
      quantity: qty,
      minStock: product.minStock,
    );
    final cost = product.costPrice;
    final margin = (cost != null && cost > 0) ? product.price - cost : null;
    final extras = _industryValues(product);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        if (!product.isActive) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              border: Border.all(color: palette.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Removed. It does not show on Sell.',
                      style: TextStyle(color: palette.ink, fontWeight: FontWeight.w600)),
                ),
                if (canEdit)
                  TextButton(
                    onPressed: _remove,
                    child: const Text('Bring it back'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PRICE',
                      style: DesignType.numeric(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.soft,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 2),
                  Text(
                    '${formatMoney(product.price)}  ',
                    style: DesignType.display.copyWith(
                        color: palette.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w800),
                  ),
                  Text('per ${product.unit}',
                      style: TextStyle(color: palette.soft, fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: palette.field,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(_categoryName,
                  style: TextStyle(
                      color: palette.soft,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        for (final tier in _pricingTiers) ...[
          const SizedBox(height: 6),
          Text(
            '${tier.unit[0].toUpperCase()}${tier.unit.substring(1)} of ${kitNumber(tier.quantityPerUnit)} · ${formatMoney(tier.price)}',
            style: TextStyle(color: palette.soft, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        if (product.trackInventory)
          _stockCard(product, qty, level)
        else
          _plainNote(
            palette,
            'Stock is not counted for this',
            canEdit
                ? 'It sells without a count. Edit it to count how many are left.'
                : 'It sells without a count.',
          ),
        if (product.trackInventory && product.isActive) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (canReceive)
                Expanded(
                  flex: 13,
                  child: FilledButton(
                    onPressed: _receive,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: DesignColors.accent,
                      foregroundColor: DesignColors.textPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                    child: const Text('Receive stock',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              if (canReceive && canEdit) const SizedBox(width: 10),
              if (canEdit)
                Expanded(
                  flex: 10,
                  child: OutlinedButton(
                    onPressed: _correctCount,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: palette.ink,
                      side: BorderSide(color: palette.line),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                    child: const Text('Correct count',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ],
        if (margin != null) ...[
          const SizedBox(height: 12),
          _plainNote(
            palette,
            'You paid ${formatMoney(cost)} each',
            margin >= 0
                ? 'You make ${formatMoney(margin)} on each, about ${(margin / product.price * 100).round()} percent of the price.'
                : 'You lose ${formatMoney(-margin)} on each. Check the price.',
          ),
        ],
        const SizedBox(height: 22),
        Text('HISTORY',
            style: DesignType.numeric(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.soft,
                letterSpacing: 1.1)),
        const SizedBox(height: 10),
        _historyList(palette, product),
        if ((product.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 22),
          _plainNote(palette, 'Description', product.description!.trim()),
        ],
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              border: Border.all(color: palette.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Details',
                    style: DesignType.display.copyWith(
                        color: palette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                for (final entry in extras.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(entry.key,
                              style: TextStyle(color: palette.soft, fontSize: 13)),
                        ),
                        Expanded(
                          flex: 5,
                          child: Text(entry.value,
                              style: TextStyle(
                                  color: palette.ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (product.sku.isNotEmpty) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: product.sku));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Code copied')));
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text('Code ${product.sku}'),
              style: TextButton.styleFrom(foregroundColor: palette.soft),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stockCard(Product product, double? qty, StockLevel level) {
    const soft = Color(0xFFB3A89A);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unit = qty == null ? product.unit : pluralUnit(product.unit, qty);
    // About how long it will last, from what actually sold in the last 14 days.
    final since = DateTime.now().subtract(const Duration(days: 14));
    final soldRecently = _history
        .where((m) => m.kind == StockMovementKind.sale && m.at.isAfter(since))
        .fold<double>(0, (sum, m) => sum + m.quantity.abs());
    String? pace;
    if (qty != null && qty > 0 && soldRecently > 0) {
      final days = (qty / (soldRecently / 14)).round();
      pace = days <= 1 ? 'about a day at this pace' : 'about $days days at this pace';
    }
    final meta = [
      if (product.minStock > 0) 'Warns below ${product.minStock}',
      if (pace != null) pace,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211C16) : const Color(0xFF1A1610),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ON THE SHELF',
                  style: DesignType.numeric(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: soft,
                      letterSpacing: 1.1)),
              const Spacer(),
              StockChip(level: level, quantity: qty),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(qty == null ? '—' : stockNumber(qty),
                  style: DesignType.display.copyWith(
                      color: const Color(0xFFF6EFE6),
                      fontSize: 40,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text(unit,
                  style: const TextStyle(
                      color: soft, fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          if (qty != null) ...[
            const SizedBox(height: 10),
            StockGauge(quantity: qty, warnAt: product.minStock, level: level),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(meta, style: const TextStyle(color: soft, fontSize: 12.5)),
          ],
        ],
      ),
    );
  }

  Widget _plainNote(SignInPalette palette, String title, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: DesignType.display.copyWith(
                  color: palette.ink, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: palette.soft, fontSize: 13.5, height: 1.4)),
        ],
      ),
    );
  }

  Widget _historyList(SignInPalette palette, Product product) {
    if (!getIt<AuthService>().isLocalWorkspace) {
      return _plainNote(palette, 'History is on this device',
          'Stock history shows for shops that keep their records on this phone.');
    }
    if (_history.isEmpty) {
      return _plainNote(palette, 'No movement yet',
          'Sales, deliveries and count corrections show here, with who and when.');
    }
    final rows = <Widget>[];
    for (var i = 0; i < _history.length; i++) {
      final m = _history[i];
      final (IconData icon, Color tint) = switch (m.kind) {
        StockMovementKind.sale => (Icons.point_of_sale_rounded, palette.soft),
        StockMovementKind.delivery => (Icons.add_rounded, MoneyColors.cash),
        StockMovementKind.correction => (Icons.rule_rounded, MoneyColors.recorded),
      };
      final sub = [
        '${_day.format(m.at)} ${_time.format(m.at)}',
        if (m.unitCost != null) 'KES ${kitNumber(m.unitCost!)} each',
        if ((m.note ?? '').isNotEmpty) m.note!,
      ].join(' · ');
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title,
                      style: TextStyle(
                          color: palette.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                  Text(sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.soft, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(m.signed,
                style: DesignType.numeric(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: m.quantity >= 0 ? MoneyColors.cash : palette.ink)),
          ],
        ),
      ));
      if (i != _history.length - 1) {
        rows.add(Divider(height: 1, color: palette.line));
      }
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Column(children: rows),
    );
  }

  String pluralUnit(String unit, double qty) =>
      qty == 1 || unit.endsWith('s') ? unit : '${unit}s';

  /// The shop-type details saved with the product, labelled in words.
  Map<String, String> _industryValues(Product product) {
    final layout = ref.read(businessLayoutProvider);
    try {
      final decoded = jsonDecode(product.metadata);
      final fields = decoded is Map ? decoded['industryFields'] : null;
      if (fields is! Map) return const {};
      return {
        for (final field in layout.effectiveProductFields)
          if ((fields[field.key]?.toString().trim() ?? '').isNotEmpty)
            field.label: fields[field.key].toString().trim(),
      };
    } catch (_) {
      return const {};
    }
  }
}

/// Sets the count to what is really on the shelf, and keeps a record of why.
class _CorrectCountSheet extends StatefulWidget {
  const _CorrectCountSheet({required this.product, required this.current});

  final Product product;
  final double current;

  @override
  State<_CorrectCountSheet> createState() => _CorrectCountSheetState();
}

class _CorrectCountSheetState extends State<_CorrectCountSheet> {
  late final TextEditingController _count;
  final TextEditingController _note = TextEditingController();
  String? _reason;
  String? _error;
  bool _busy = false;

  static const _reasons = [
    'Miscounted before',
    'Torn or damaged',
    'Expired',
    'Missing',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _count = TextEditingController(text: stockNumber(widget.current));
  }

  @override
  void dispose() {
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final counted = double.tryParse(_count.text.trim());
    if (counted == null || !counted.isFinite || counted < 0) {
      setState(() => _error = 'Enter how many are on the shelf, 0 or more.');
      return;
    }
    if (!widget.product.allowFractions && counted % 1 != 0) {
      setState(() => _error = 'This is sold in whole units. Enter a whole number.');
      return;
    }
    if ((counted - widget.current).abs() < 0.000001) {
      setState(() => _error = 'That is the same as the count already saved.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = [
      if (_reason != null) _reason!,
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ].join(', ');
    try {
      final branchId = getIt<StorageService>().getBranchId();
      if (branchId == null || branchId.isEmpty) {
        throw StateError('The shop branch is missing. Reopen setup.');
      }
      await getIt<AppDatabase>().correctLocalStock(
        productId: widget.product.id,
        branchId: branchId,
        countedQty: counted,
        reason: reason.isEmpty ? null : reason,
        byName: getIt<AuthService>().currentUser?['name']?.toString(),
      );
      if (mounted) Navigator.of(context).pop(true);
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
    final unit = widget.product.unit;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: palette.line, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Correct the count',
                  style: DesignType.display.copyWith(
                      color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'The count says ${stockNumber(widget.current)} $unit. Enter what you really see on the shelf. The change is kept in the history.',
                style: TextStyle(color: palette.soft, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _count,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
                decoration: kitFieldDecoration(
                  context,
                  label: 'Counted on the shelf',
                  suffixText: unit,
                ).copyWith(errorText: _error),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in _reasons)
                    ChoiceChip(
                      label: Text(reason),
                      selected: _reason == reason,
                      onSelected: (on) =>
                          setState(() => _reason = on ? reason : null),
                      selectedColor: DesignColors.peach,
                      backgroundColor: palette.card,
                      side: BorderSide(
                          color: _reason == reason
                              ? DesignColors.accent
                              : palette.line),
                      labelStyle: TextStyle(
                          color: _reason == reason
                              ? const Color(0xFF6B2A08)
                              : palette.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                style: TextStyle(color: palette.ink),
                decoration: kitFieldDecoration(context,
                    label: 'Note (optional)', hint: 'For example, torn bag'),
              ),
              const SizedBox(height: 18),
              SignInButton(
                label: _busy ? 'Saving…' : 'Save correction',
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
