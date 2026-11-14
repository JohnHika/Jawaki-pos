import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';
import 'package:axon_pos/features/home/domain/shop_guidance.dart';

const Color kCashColor = MoneyColors.cash;
const Color kRecordedColor = MoneyColors.recorded;
const Color kCreditColor = MoneyColors.credit;
const Color kOtherColor = MoneyColors.verified;

TextStyle get _mono => DesignType.numeric();

final NumberFormat _kes = NumberFormat.decimalPattern('en_KE');

String _money(num value) => _kes.format(value.round());

/// Today's takings first: the figure, how many sales, and how the money came
/// in. Cash, recorded and credit each have a colour so an owner reads them the
/// same way on every screen.
class HomeTakingsCard extends StatelessWidget {
  const HomeTakingsCard({
    super.key,
    required this.revenue,
    required this.transactions,
    required this.averageTicket,
    this.itemsSold,
    required this.split,
    this.dateLabel,
    this.sellingSince,
  });

  final double revenue;
  final int transactions;
  final double averageTicket;
  final double? itemsSold;
  final TakingsSplit split;
  final String? dateLabel;

  /// "7:42": when today's first sale was rung. Shown in place of the date.
  final String? sellingSince;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final background = palette.card;

    final groups = <({String label, double amount, Color color})>[
      (label: 'Cash', amount: split.cash, color: kCashColor),
      (
        label: 'M-Pesa or bank, recorded',
        amount: split.recorded,
        color: kRecordedColor
      ),
      (label: 'On credit', amount: split.credit, color: kCreditColor),
      (label: 'Other', amount: split.other, color: kOtherColor),
    ].where((g) => g.amount > 0).toList();

    final splitTotal = split.total;

    return Semantics(
      container: true,
      label: 'Sold today KES ${_money(revenue)} in $transactions sales',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
          border: Border.all(color: palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sold today',
                    style: TextStyle(
                      color: palette.soft,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (sellingSince != null)
                  Text(
                    'Selling since $sellingSince',
                    style: TextStyle(
                      color: palette.soft,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (dateLabel != null)
                  Text(
                    dateLabel!,
                    style: TextStyle(
                      color: palette.soft,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'KES ',
                  style: DesignType.numeric(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.soft,
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _money(revenue),
                      style: DesignType.numeric(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              transactions == 0
                  ? 'No sales yet today'
                  : '$transactions ${transactions == 1 ? 'sale' : 'sales'} · average KES ${_money(averageTicket)}${itemsSold == null ? '' : ' · ${_itemsText(itemsSold!)}'}',
              style: TextStyle(
                color: palette.soft,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (splitTotal > 0) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < groups.length; i++) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: (groups[i].amount / splitTotal * 1000)
                              .round()
                              .clamp(1, 1000),
                          child: ColoredBox(
                            color: groups[i].color.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final group in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: group.color.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          group.label,
                          style: TextStyle(color: palette.ink, fontSize: 13),
                        ),
                      ),
                      Text(
                        _money(group.amount),
                        style: DesignType.numeric(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: palette.ink,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _itemsText(double items) {
    final whole = items == items.roundToDouble();
    final text = whole ? items.round().toString() : items.toStringAsFixed(1);
    return '$text ${items == 1 ? 'item' : 'items'}';
  }
}

/// The one button Home exists to offer.
class HomeStartSaleButton extends StatelessWidget {
  const HomeStartSaleButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: DesignColors.accent,
          foregroundColor: SignInPalette.onAccent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Start a sale'),
      ),
    );
  }
}

/// Reminder that recorded payments still need to be matched with the shop's
/// own M-Pesa or bank statement.
class HomeRecordedReminder extends StatelessWidget {
  const HomeRecordedReminder({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final background =
        palette.isDark ? const Color(0xFF3A2A14) : const Color(0xFFFBE9C8);
    final foreground =
        palette.isDark ? const Color(0xFFF0BF82) : const Color(0xFF5A3A06);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.fact_check_outlined, color: foreground, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 recorded payment to check against your M-Pesa or bank statement at end of day.'
                      : '$count recorded payments to check against your M-Pesa or bank statement at end of day.',
                  style:
                      TextStyle(color: foreground, fontSize: 13.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the owner up to date about the system: what changed in the app, and
/// suggestions for the kind of shop they chose.
class ShopUpToDateCard extends StatefulWidget {
  const ShopUpToDateCard({
    super.key,
    required this.profileId,
    required this.profileName,
    required this.onOpen,
  });

  final String profileId;
  final String profileName;
  final void Function(String path) onOpen;

  @override
  State<ShopUpToDateCard> createState() => _ShopUpToDateCardState();
}

class _ShopUpToDateCardState extends State<ShopUpToDateCard> {
  bool _showAllNews = false;
  late final Future<String> _version = PackageInfo.fromPlatform()
      .then((info) => info.version)
      .catchError((_) => '');

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final tips = tipsForProfile(widget.profileId);
    final news = _showAllNews ? kWhatsNew : kWhatsNew.take(1).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: DesignColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 18, color: DesignColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your shop, up to date',
                        style: DesignType.display.copyWith(
                            color: palette.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text('For a ${widget.profileName.toLowerCase()}',
                        style: TextStyle(color: palette.soft, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionLabel('WHAT\'S NEW', palette),
          for (final item in news)
            _Row(
              palette: palette,
              title: item.title,
              body: item.body,
              onTap: item.path == null ? null : () => widget.onOpen(item.path!),
            ),
          if (kWhatsNew.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showAllNews = !_showAllNews),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 36),
                  foregroundColor: DesignColors.accentDark,
                ),
                child: Text(_showAllNews
                    ? 'Show less'
                    : 'Show ${kWhatsNew.length - 1} more'),
              ),
            ),
          const SizedBox(height: 6),
          _SectionLabel('FOR YOUR SHOP', palette),
          for (final tip in tips)
            _Row(
              palette: palette,
              title: tip.title,
              body: tip.body,
              action: tip.action,
              onTap: () => widget.onOpen(tip.path),
            ),
          const SizedBox(height: 8),
          Divider(height: 1, color: palette.line),
          const SizedBox(height: 10),
          FutureBuilder<String>(
            future: _version,
            builder: (context, snapshot) {
              final version = snapshot.data ?? '';
              return Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 15, color: palette.faint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      version.isEmpty
                          ? 'Records stay on this phone.'
                          : 'Counterbase $version · records stay on this phone.',
                      style: TextStyle(color: palette.faint, fontSize: 12),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.palette);

  final String text;
  final SignInPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: _mono.copyWith(
              color: palette.soft,
              fontSize: 10.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.palette,
    required this.title,
    required this.body,
    this.action,
    this.onTap,
  });

  final SignInPalette palette;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: palette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: TextStyle(
                          color: palette.soft, fontSize: 13, height: 1.4)),
                  if (action != null) ...[
                    const SizedBox(height: 4),
                    Text(action!,
                        style: const TextStyle(
                            color: DesignColors.accentDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.chevron_right_rounded,
                    color: palette.faint, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

/// A quiet strip on Home about the shop's payment standing. Shown only when it
/// needs attention: a trial or payment due within three days, a late payment,
/// or paused sales.
class HomeLicenceBanner extends StatelessWidget {
  const HomeLicenceBanner({
    super.key,
    required this.status,
    required this.daysLeft,
    required this.onTap,
  });

  final LicenceStatusKind status;
  final int daysLeft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final paused = status == LicenceStatusKind.paused;
    final background = paused
        ? (palette.isDark ? const Color(0xFF3D1C1C) : const Color(0xFFF6DADA))
        : (palette.isDark ? const Color(0xFF3A2A14) : const Color(0xFFFBE9C8));
    final foreground = paused
        ? (palette.isDark ? const Color(0xFFF2A3A3) : const Color(0xFF7A1F1F))
        : (palette.isDark ? const Color(0xFFF0BF82) : const Color(0xFF5A3A06));
    final days = daysLeft == 1 ? '1 day' : '$daysLeft days';
    final text = switch (status) {
      LicenceStatusKind.trial =>
        'Your free trial ends in $days. Open Plan and licence to keep selling.',
      LicenceStatusKind.due => 'Your payment is due in $days.',
      LicenceStatusKind.late =>
        'Your payment is late. New sales pause in $days.',
      LicenceStatusKind.paused =>
        'New sales are paused. Your records are safe. Tap to pay and unlock.',
    };
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(paused ? Icons.lock_outline_rounded : Icons.schedule_rounded,
                  color: foreground, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: foreground, fontSize: 13.5, height: 1.4)),
              ),
              Icon(Icons.chevron_right_rounded, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

enum LicenceStatusKind { trial, due, late, paused }
