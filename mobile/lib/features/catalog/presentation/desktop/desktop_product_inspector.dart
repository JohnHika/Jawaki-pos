import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart' show Product;
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../domain/stock_status.dart';
import '../widgets/stock_kit.dart' show ProductAvatar;
import 'desktop_button_styles.dart';

/// What the right-hand panel on the Products page shows for one product: the
/// price, how many are on the shelf, what moved lately, and the actions.
///
/// Plain data in, callbacks out, so a test can render it with sample rows.
class DesktopProductInspector extends StatelessWidget {
  const DesktopProductInspector({
    super.key,
    required this.product,
    required this.categoryName,
    required this.quantity,
    required this.history,
    required this.historyAvailable,
    this.showCost = false,
    this.canEdit = false,
    this.canReceive = false,
    this.onClose,
    this.onEdit,
    this.onReceive,
    this.onCorrectCount,
    this.onToggleRemoved,
  });

  final Product product;
  final String categoryName;

  /// null when no count is saved yet.
  final double? quantity;
  final List<StockMovement> history;

  /// False for shops that keep their records in the cloud, where this
  /// computer has no movement history.
  final bool historyAvailable;
  final bool showCost;
  final bool canEdit;
  final bool canReceive;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onReceive;
  final VoidCallback? onCorrectCount;
  final VoidCallback? onToggleRemoved;

  static final DateFormat _when = DateFormat('EEE d MMM, HH:mm');

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final level = stockLevelFor(
      trackInventory: product.trackInventory,
      quantity: quantity,
      minStock: product.minStock,
    );
    final cost = product.costPrice;
    final hasCost = showCost && cost != null && cost > 0;
    final margin = hasCost ? product.price - cost : null;
    final tracked = product.trackInventory && product.isActive;

    return DesktopInspector(
      title: product.name,
      subtitle:
          product.sku.isEmpty ? categoryName : '${product.sku} · $categoryName',
      onClose: onClose,
      footer: _footer(context, tracked),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProductAvatar(
                name: product.name,
                imageUrl: product.imageUrl,
                size: 64,
                tint: product.isActive ? null : DesignColors.textTertiary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatMoney(product.price),
                      style: DesignType.numeric(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: p.text,
                      ),
                    ),
                    Text(
                      'per ${product.unit}',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!product.isActive)
                const DesktopStatusChip(
                  label: 'Removed',
                  color: DesignColors.textTertiary,
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (product.trackInventory)
            _stockBlock(context, level)
          else
            _note(
              context,
              'Stock is not counted for this',
              canEdit
                  ? 'It sells without a count. Edit it to count how many are left.'
                  : 'It sells without a count.',
            ),
          const SizedBox(height: 18),
          _fact(context, 'Category', categoryName),
          _fact(context, 'Code', product.sku.isEmpty ? 'None' : product.sku,
              copyable: product.sku.isNotEmpty),
          if (hasCost) _fact(context, 'You paid', '${formatMoney(cost)} each'),
          if (margin != null)
            _fact(
              context,
              'You make',
              margin >= 0
                  ? '${formatMoney(margin)} each, about ${(margin / product.price * 100).round()}%'
                  : 'You lose ${formatMoney(-margin)} each. Check the price.',
              emphasis: margin < 0 ? DesignColors.error : null,
            ),
          if (product.trackInventory && product.minStock > 0)
            _fact(
                context, 'Warns below', '${product.minStock} ${product.unit}'),
          if ((product.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              product.description!.trim(),
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 22),
          Text(
            'Recent movements',
            style: GoogleFonts.sora(
              color: p.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _movements(context),
        ],
      ),
    );
  }

  Widget? _footer(BuildContext context, bool tracked) {
    final buttons = <Widget>[];
    if (!product.isActive) {
      if (canEdit && onToggleRemoved != null) {
        buttons.add(
          Expanded(
            child: FilledButton(
              style: desktopPrimaryButton(context),
              onPressed: onToggleRemoved,
              child: const Text('Bring back'),
            ),
          ),
        );
      }
    } else {
      if (canReceive && tracked && onReceive != null) {
        buttons.add(
          Expanded(
            child: FilledButton(
              style: desktopPrimaryButton(context),
              onPressed: onReceive,
              child: const Text('Receive stock'),
            ),
          ),
        );
      }
      if (canEdit && onEdit != null) {
        buttons.add(
          Expanded(
            child: OutlinedButton(
              style: desktopSecondaryButton(context),
              onPressed: onEdit,
              child: const Text('Edit'),
            ),
          ),
        );
      }
    }
    final menu = <PopupMenuEntry<String>>[
      if (canEdit && tracked && onCorrectCount != null)
        const PopupMenuItem(value: 'count', child: Text('Correct count')),
      if (product.sku.isNotEmpty)
        const PopupMenuItem(value: 'copy', child: Text('Copy code')),
      if (canEdit && product.isActive && onToggleRemoved != null)
        const PopupMenuItem(value: 'remove', child: Text('Remove')),
    ];
    if (buttons.isEmpty && menu.isEmpty) return null;
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          buttons[i],
        ],
        if (menu.isNotEmpty) ...[
          if (buttons.isNotEmpty) const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) async {
              switch (value) {
                case 'count':
                  onCorrectCount?.call();
                case 'remove':
                  onToggleRemoved?.call();
                case 'copy':
                  await Clipboard.setData(ClipboardData(text: product.sku));
                  if (!context.mounted) return;
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('Code copied')),
                  );
              }
            },
            itemBuilder: (context) => menu,
          ),
        ],
      ],
    );
  }

  Widget _stockBlock(BuildContext context, StockLevel level) {
    final p = context.desktop;
    final qty = quantity;
    final color = switch (level) {
      StockLevel.inStock => DesignColors.success,
      StockLevel.low => DesignColors.warning,
      StockLevel.out => DesignColors.error,
      _ => DesignColors.textTertiary,
    };
    final top = qty == null
        ? 1.0
        : [qty, product.minStock * 4.0, 1.0].reduce((a, b) => a > b ? a : b);
    final fill = qty == null ? 0.0 : (qty / top).clamp(0.0, 1.0);
    final tick = (product.minStock / top).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.panelAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'On the shelf',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (level == StockLevel.low)
                const DesktopStatusChip(
                  label: 'Low stock',
                  color: DesignColors.warning,
                )
              else if (level == StockLevel.out)
                const DesktopStatusChip(
                  label: 'Out of stock',
                  color: DesignColors.error,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                qty == null ? '—' : stockNumber(qty),
                style: DesignType.numeric(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: p.text,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  qty == null ? 'No count yet' : product.unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (qty != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 10,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 2,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.borderStrong.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 2,
                      height: 6,
                      width: box.maxWidth * fill,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    if (product.minStock > 0)
                      Positioned(
                        left: box.maxWidth * tick - 1,
                        top: 0,
                        width: 2,
                        height: 10,
                        child: ColoredBox(color: p.text),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(
    BuildContext context,
    String label,
    String value, {
    bool copyable = false,
    Color? emphasis,
  }) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: copyable
                ? SelectableText(
                    value,
                    style: GoogleFonts.plusJakartaSans(
                      color: emphasis ?? p.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Text(
                    value,
                    style: GoogleFonts.plusJakartaSans(
                      color: emphasis ?? p.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String title, String body) {
    final p = context.desktop;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.panelAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.sora(
              color: p.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _movements(BuildContext context) {
    final p = context.desktop;
    if (!historyAvailable) {
      return Text(
        'Stock history shows for shops that keep their records on this computer.',
        style: GoogleFonts.plusJakartaSans(
          color: p.textMuted,
          fontSize: 13,
          height: 1.4,
        ),
      );
    }
    if (history.isEmpty) {
      return Text(
        'No movement yet. Sales, deliveries and count corrections show here.',
        style: GoogleFonts.plusJakartaSans(
          color: p.textMuted,
          fontSize: 13,
          height: 1.4,
        ),
      );
    }
    final shown = history.take(8).toList();
    return Column(
      children: [
        for (final m in shown)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          _when.format(m.at),
                          if (m.unitCost != null)
                            '${formatMoney(m.unitCost)} each',
                          if ((m.note ?? '').isNotEmpty) m.note!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  m.signed,
                  style: DesignType.numeric(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: m.quantity >= 0 ? DesignColors.success : p.text,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
