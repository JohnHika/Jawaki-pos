import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/stock_status.dart';
import 'stock_kit.dart';

enum _StockView { all, reorder, receipts }

/// The Stock side of Products: what the shelves are worth, what to buy first,
/// every item's count, and the deliveries received.
class StockPane extends StatefulWidget {
  const StockPane({
    super.key,
    required this.products,
    required this.quantities,
    required this.canReceive,
  });

  final List<Product> products;
  final Map<String, double> quantities;
  final bool canReceive;

  @override
  State<StockPane> createState() => _StockPaneState();
}

class _StockPaneState extends State<StockPane> {
  _StockView? _view;
  Future<List<Map<String, dynamic>>>? _receipts;
  static final _number = NumberFormat('#,##0');
  static final _day = DateFormat('d MMM');

  StockLevel _levelOf(Product p) => stockLevelFor(
        trackInventory: p.trackInventory,
        quantity: widget.quantities[p.id],
        minStock: p.minStock,
      );

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final lines = [
      for (final p in widget.products)
        StockLine(
          trackInventory: p.trackInventory,
          quantity: widget.quantities[p.id],
          minStock: p.minStock,
          price: p.price,
          costPrice: p.costPrice,
        ),
    ];
    final summary = summarizeStock(lines);
    // Open on what to buy when anything is short, otherwise on everything.
    final view = _view ??
        (summary.needsReorder > 0 ? _StockView.reorder : _StockView.all);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        _SummaryCard(summary: summary, number: _number),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Chip(
                label: 'All',
                selected: view == _StockView.all,
                onTap: () => setState(() => _view = _StockView.all),
              ),
              const SizedBox(width: 8),
              _Chip(
                label: summary.needsReorder > 0
                    ? 'Needs reorder ${summary.needsReorder}'
                    : 'Needs reorder',
                selected: view == _StockView.reorder,
                onTap: () => setState(() => _view = _StockView.reorder),
              ),
              const SizedBox(width: 8),
              _Chip(
                label: 'Receipts',
                selected: view == _StockView.receipts,
                onTap: () => setState(() {
                  _view = _StockView.receipts;
                  _receipts ??= getIt<AppDatabase>().getLocalStockReceiptHistory();
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ..._body(context, palette, view),
      ],
    );
  }

  List<Widget> _body(BuildContext context, SignInPalette palette, _StockView view) {
    switch (view) {
      case _StockView.receipts:
        return [_receiptsList(palette)];
      case _StockView.reorder:
        final out = widget.products
            .where((p) => _levelOf(p) == StockLevel.out)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final low = widget.products
            .where((p) => _levelOf(p) == StockLevel.low)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        if (out.isEmpty && low.isEmpty) {
          return [
            _Note(
              palette: palette,
              title: 'Nothing to reorder',
              body: 'Everything you count is above its warning level.',
            ),
          ];
        }
        return [
          if (out.isNotEmpty) ...[
            _Heading(palette, 'OUT'),
            _Group(palette, [for (final p in out) _row(context, palette, p, receive: true)]),
            const SizedBox(height: 14),
          ],
          if (low.isNotEmpty) ...[
            _Heading(palette, 'RUNNING LOW'),
            _Group(palette, [for (final p in low) _row(context, palette, p, receive: true)]),
          ],
        ];
      case _StockView.all:
        final all = [...widget.products]..sort((a, b) => a.name.compareTo(b.name));
        if (all.isEmpty) {
          return [
            _Note(
              palette: palette,
              title: 'No products yet',
              body: 'Add a product first, then count it here.',
            ),
          ];
        }
        return [_Group(palette, [for (final p in all) _row(context, palette, p)])];
    }
  }

  Widget _row(BuildContext context, SignInPalette palette, Product p,
      {bool receive = false}) {
    final level = _levelOf(p);
    final qty = widget.quantities[p.id];
    final warn = p.minStock > 0 ? ' · warns below ${p.minStock}' : '';
    // The chip already says "Not tracked"; the line says how to change that.
    final detail = level == StockLevel.notTracked
        ? 'Edit it to start counting'
        : '${stockNumber(qty ?? 0)} left$warn';
    return InkWell(
      onTap: () => context.push('/products/${p.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            ProductAvatar(
              name: p.name,
              imageUrl: p.imageUrl,
              tint: level == StockLevel.out
                  ? DesignColors.error
                  : level == StockLevel.low
                      ? MoneyColors.recorded
                      : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: palette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.soft, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (receive && widget.canReceive)
              MiniAction(
                label: 'Receive',
                onTap: () => context.push('/inventory/receive?productId=${p.id}'),
              )
            else
              StockChip(level: level, quantity: qty),
          ],
        ),
      ),
    );
  }

  Widget _receiptsList(SignInPalette palette) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _receipts,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (snapshot.hasError || rows.isEmpty) {
          return _Note(
            palette: palette,
            title: snapshot.hasError ? 'Could not read receipts' : 'No deliveries yet',
            body: snapshot.hasError
                ? 'Your stock is safe. Close and open Stock to try again.'
                : 'When you receive stock, each delivery is listed here.',
          );
        }
        return _Group(palette, [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r['productName'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: palette.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        Text(
                          [
                            _day.format(DateTime.parse(r['receivedAt'] as String).toLocal()),
                            if ((r['supplierReferences'] as String?)?.isNotEmpty == true)
                              r['supplierReferences'] as String,
                            if (r['costComplete'] == true && (r['totalCost'] as double) > 0)
                              'KES ${_number.format(r['totalCost'])} paid',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: palette.soft, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '+${stockNumber(r['totalQuantity'] as double)}',
                    style: DesignType.numeric(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MoneyColors.cash),
                  ),
                ],
              ),
            ),
        ]);
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.number});

  final StockSummary summary;
  final NumberFormat number;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const soft = Color(0xFFB3A89A);
    Widget stat(String value, String label, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: DesignType.display.copyWith(
                      color: color, fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(color: soft, fontSize: 11.5)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211C16) : const Color(0xFF1A1610),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.worthAtCost
                ? 'STOCK WORTH, AT WHAT YOU PAID'
                : 'STOCK WORTH, AT SELLING PRICE',
            style: DesignType.numeric(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: soft,
                letterSpacing: 1.1),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('KES ',
                  style: TextStyle(
                      color: soft, fontSize: 14, fontWeight: FontWeight.w600)),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(number.format(summary.worth),
                      style: DesignType.display.copyWith(
                          color: const Color(0xFFF6EFE6),
                          fontSize: 32,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              stat('${summary.products}', 'products', const Color(0xFFF6EFE6)),
              stat('${summary.low}', 'running low', const Color(0xFFF0B24A)),
              stat('${summary.out}', 'out', const Color(0xFFFF8A7A)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected
                ? (palette.isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary)
                : palette.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected
                    ? (palette.isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary)
                    : palette.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected
                  ? (palette.isDark ? DesignColors.darkBg : Colors.white)
                  : palette.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.palette, this.text);

  final SignInPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: DesignType.numeric(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.soft,
                letterSpacing: 1.1)),
      );
}

class _Group extends StatelessWidget {
  const _Group(this.palette, this.children);

  final SignInPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final separated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) separated.add(Divider(height: 1, color: palette.line));
      separated.add(children[i]);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Column(children: separated),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.palette, required this.title, required this.body});

  final SignInPalette palette;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
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
            Text(body, style: TextStyle(color: palette.soft, fontSize: 13)),
          ],
        ),
      );
}
