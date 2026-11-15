import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/alive_feedback.dart';
import '../../domain/price_freshness.dart';
import '../../domain/price_history.dart';
import '../../domain/price_list_builder.dart';
import '../../domain/price_row_data.dart';

/// Opens one product's price: the price in large type, any recent move, the
/// bulk prices with what each unit costs, and Send / Copy for just this item.
/// A bottom sheet on a phone or tablet, a dialog on a computer.
Future<void> showPriceDetail(
  BuildContext context, {
  required PriceListRowData data,
  required Color accent,
  required String shareText,
  required VoidCallback onWhatsApp,
  required VoidCallback onCopy,
  DateTime? now,
}) {
  final when = now ?? DateTime.now();
  if (context.inDesktopShell) {
    return showDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignSpacing.xl),
            child: PriceDetailBody(
              data: data,
              accent: accent,
              shareText: shareText,
              now: when,
              onWhatsApp: () {
                Navigator.of(dialog).pop();
                onWhatsApp();
              },
              onCopy: onCopy,
              onClose: () => Navigator.of(dialog).pop(),
            ),
          ),
        ),
      ),
    );
  }
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 520),
    backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(DesignSpacing.radiusXxl)),
    ),
    builder: (sheet) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        DesignSpacing.xl,
        DesignSpacing.md,
        DesignSpacing.xl,
        MediaQuery.viewInsetsOf(sheet).bottom + DesignSpacing.xl,
      ),
      child: PriceDetailBody(
        data: data,
        accent: accent,
        shareText: shareText,
        now: when,
        showHandle: true,
        onWhatsApp: () {
          Navigator.of(sheet).pop();
          onWhatsApp();
        },
        onCopy: onCopy,
        onClose: () => Navigator.of(sheet).pop(),
      ),
    ),
  );
}

class PriceDetailBody extends StatefulWidget {
  const PriceDetailBody({
    super.key,
    required this.data,
    required this.accent,
    required this.shareText,
    required this.now,
    required this.onWhatsApp,
    required this.onCopy,
    required this.onClose,
    this.showHandle = false,
  });

  final PriceListRowData data;
  final Color accent;
  final String shareText;
  final DateTime now;
  final VoidCallback onWhatsApp;
  final VoidCallback onCopy;
  final VoidCallback onClose;
  final bool showHandle;

  @override
  State<PriceDetailBody> createState() => _PriceDetailBodyState();
}

class _PriceDetailBodyState extends State<PriceDetailBody> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    widget.onCopy();
    _timer?.cancel();
    _timer = AliveIcon.flash((v) {
      if (mounted) setState(() => _copied = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;
    final item = widget.data.item;
    final unit = item.unit.isEmpty || item.unit == 'piece' ? null : item.unit;
    final sub = [
      if (item.categoryName.trim().isNotEmpty) item.categoryName.trim(),
      if ((widget.data.sku ?? '').isNotEmpty) widget.data.sku!,
    ].join(' · ');
    final change = item.change;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHandle)
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: DesignSpacing.lg),
              decoration: BoxDecoration(
                color: border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Text(
          item.name,
          key: const ValueKey('price-detail-name'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: primary,
          ),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(fontSize: 13, color: secondary)),
        ],
        const SizedBox(height: DesignSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              priceKes(item.price),
              key: const ValueKey('price-detail-price'),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 8),
              Text('per $unit',
                  style: TextStyle(fontSize: 14, color: secondary)),
            ],
          ],
        ),
        if (change != null) ...[
          const SizedBox(height: DesignSpacing.sm),
          _ChangeLine(change: change, now: widget.now),
        ],
        if (widget.data.stock == PriceStock.low ||
            widget.data.stock == PriceStock.out) ...[
          const SizedBox(height: DesignSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: PriceStockChip(widget.data.stock),
          ),
        ],
        if (item.tiers.isNotEmpty) ...[
          const SizedBox(height: DesignSpacing.xl),
          Text(
            'BULK PRICES',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: isDark
                  ? DesignColors.darkTextTertiary
                  : DesignColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          for (final tier in item.tiers)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${tier.unit} of ${_qty(tier.quantityPerUnit)}',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        priceKes(tier.price),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: primary,
                        ),
                      ),
                      if (tier.quantityPerUnit > 1)
                        Text(
                          '${priceKes(tier.price / tier.quantityPerUnit)} each',
                          style: TextStyle(fontSize: 11.5, color: secondary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: DesignSpacing.xl),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('price-detail-whatsapp'),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: widget.onWhatsApp,
                icon: const Icon(Icons.chat_rounded, size: 19),
                label: const Text('Send this price'),
              ),
            ),
            const SizedBox(width: DesignSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('price-detail-copy'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _copy,
              icon: AliveIcon(
                done: _copied,
                idle: const Icon(Icons.copy_rounded, size: 19),
                size: 19,
              ),
              label: const Text('Copy'),
            ),
          ],
        ),
      ],
    );
  }
}

String _qty(double q) => q == q.roundToDouble() ? q.round().toString() : '$q';

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.change, required this.now});

  final PriceChange change;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final style = PriceChangeStyle.of(change);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 16, color: style.color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${priceChangeLabel(change, priceKes)} · was ${priceKes(change.previous)} · ${priceChangeWhen(change.changedAt, now)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The colour and arrow for a price move. Up is amber (customers pay more),
/// down is blue (cheaper), so neither reads as an error.
class PriceChangeStyle {
  const PriceChangeStyle(this.color, this.icon);

  final Color color;
  final IconData icon;

  static PriceChangeStyle of(PriceChange change) =>
      change.direction == PriceDirection.up
          ? const PriceChangeStyle(
              DesignColors.warning, Icons.arrow_upward_rounded)
          : const PriceChangeStyle(
              DesignColors.info, Icons.arrow_downward_rounded);
}

/// "Low stock" / "Out of stock" chip, used by the list rows and the detail.
class PriceStockChip extends StatelessWidget {
  const PriceStockChip(this.stock, {super.key});

  final PriceStock stock;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (stock) {
      PriceStock.available => ('In stock', DesignColors.success),
      PriceStock.low => ('Low stock', DesignColors.warning),
      PriceStock.out => ('Out of stock', DesignColors.error),
      PriceStock.untracked => ('', Colors.transparent),
    };
    if (stock == PriceStock.untracked) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: isDark ? color : Color.alphaBlend(Colors.black38, color),
            ),
          ),
        ],
      ),
    );
  }
}
