import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../../../../core/widgets/motion_kit_extras.dart';
import '../../domain/collections_ledger.dart';
import '../../domain/finance_models.dart';
import '../providers/finance_hub_controller.dart';
import '../widgets/shop_installment_sheet.dart';

/// Everything one other shop owes us and has paid back: the running balance,
/// each debt with its progress, and a dated list of every instalment received.
class ShopLedgerScreen extends ConsumerWidget {
  const ShopLedgerScreen({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = ref.watch(financeHubProvider);
    final controller = ref.read(financeHubProvider.notifier);
    final snapshot = hub.snapshot;
    PeerDebtor? shop;
    if (snapshot != null) {
      for (final d in snapshot.peerDebtors) {
        if (d.id == shopId) shop = d;
      }
    }
    if (snapshot == null || shop == null) {
      return const Scaffold(
        appBar: BrandedAppBar(title: 'Shop account', showLogo: false),
        body: Center(child: Text('This shop is not available right now.')),
      );
    }
    final statement = shopStatement(snapshot, shop);
    final instalments = mergeInstalments(statement.collections);
    return Scaffold(
      appBar: BrandedAppBar(title: shop.name, showLogo: false),
      bottomNavigationBar: statement.outstanding > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    DesignSpacing.lg, DesignSpacing.sm, DesignSpacing.lg, DesignSpacing.md),
                child: SizedBox(
                  height: DesignSpacing.huge,
                  child: FilledButton.icon(
                    key: const ValueKey('record-installment'),
                    icon: const Icon(Icons.add_card_rounded),
                    label: const Text('Record instalment'),
                    onPressed: () => _record(context, statement,
                        snapshot.branchId, controller),
                  ),
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, DesignSpacing.xxxl),
          children: <Widget>[
            FadeSlideIn(child: _BalanceCard(statement: statement)),
            const SizedBox(height: DesignSpacing.xl),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: _SectionTitle(
                  'Debts', '${statement.debts.length} on record'),
            ),
            const SizedBox(height: DesignSpacing.sm),
            if (statement.debts.isEmpty)
              const _Hint('No debts recorded for this shop yet.')
            else
              for (var i = 0; i < statement.debts.length; i++)
                FadeSlideIn(
                  delay: Duration(milliseconds: 120 + 50 * i.clamp(0, 8)),
                  child: _DebtCard(debt: statement.debts[i]),
                ),
            const SizedBox(height: DesignSpacing.xl),
            _SectionTitle('Instalments received',
                '${instalments.length} payment${instalments.length == 1 ? '' : 's'}'),
            const SizedBox(height: DesignSpacing.sm),
            if (statement.collections.isEmpty)
              const _Hint(
                  'Nothing collected yet. Record an instalment when this shop pays.')
            else
              _Timeline(entries: instalments),
          ],
        ),
      ),
    );
  }

  Future<void> _record(BuildContext context, ShopStatement statement,
      String branchId, FinanceHubController controller) async {
    final messenger = ScaffoldMessenger.of(context);
    final collected = await showShopInstallmentSheet(
      context,
      statement: statement,
      branchId: branchId,
      controller: controller,
    );
    if (collected == null) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
          'Collected ${formatMoney(collected)} from ${statement.shop.name}'),
    ));
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.statement});
  final ShopStatement statement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settled = statement.isSettled;
    final accent = settled
        ? context.readable(DesignColors.success)
        : context.readable(DesignColors.brand);
    return GlassCard(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      borderRadius: DesignSpacing.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(settled ? 'All settled' : 'Still owes you',
                    style: theme.textTheme.labelLarge),
              ),
              if (settled)
                const StatusBadge(
                    label: 'Paid up',
                    color: DesignColors.success,
                    icon: Icons.check_circle_rounded)
              else if (statement.collections.isNotEmpty)
                StatusBadge(
                    label: '${(statement.progress * 100).round()}% repaid',
                    color: DesignColors.brand),
            ],
          ),
          const SizedBox(height: DesignSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: CountUpText(
                  formatMoney(statement.outstanding),
                  style:
                      DesignType.numeric(fontSize: 34).copyWith(color: accent),
                ),
              ),
              // The share of the original debt already paid back.
              ArcGauge(
                value: statement.progress,
                size: 54,
                strokeWidth: 6,
                color: settled ? DesignColors.success : DesignColors.accent,
                child: Text('${(statement.progress * 100).round()}%',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.md),
          AnimatedProgressBar(
            value: statement.progress,
            height: 10,
            color: settled ? DesignColors.success : DesignColors.accent,
          ),
          const SizedBox(height: DesignSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                  child: _Figure('Original total',
                      formatMoney(statement.originalTotal))),
              Expanded(
                  child: _Figure('Paid so far', formatMoney(statement.paid),
                      color: context.readable(DesignColors.success))),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: DesignType.numeric(fontSize: 16)
                    .copyWith(color: color)),
          ),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.trailing);
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.titleMedium)),
          Text(trailing, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(DesignSpacing.xl),
        child: Text(message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      );
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.debt});
  final PeerReceivable debt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settled = debt.outstandingAmount <= 0;
    final paid = debt.originalAmount - debt.outstandingAmount;
    final progress = debt.originalAmount <= 0
        ? 0.0
        : (paid / debt.originalAmount).clamp(0.0, 1.0);
    final due = debt.dueDate;
    final overdue = !settled && due != null && due.isBefore(DateTime.now());
    final created = debt.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: GlassCard(
        padding: const EdgeInsets.all(DesignSpacing.lg),
        borderRadius: DesignSpacing.radiusMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(debt.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall),
                      if (created != null)
                        Text(
                            'Taken ${DateFormat('d MMM y').format(created.toLocal())}',
                            style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
                const SizedBox(width: DesignSpacing.sm),
                if (settled)
                  const StatusBadge(label: 'Paid', color: DesignColors.success)
                else if (overdue)
                  const StatusBadge(label: 'Overdue', color: DesignColors.error)
                else if (due != null)
                  StatusBadge(
                      label: 'Due ${DateFormat('d MMM').format(due.toLocal())}',
                      color: DesignColors.warning),
              ],
            ),
            const SizedBox(height: DesignSpacing.md),
            AnimatedProgressBar(
              value: progress,
              height: 6,
              color: settled ? DesignColors.success : DesignColors.accent,
            ),
            const SizedBox(height: DesignSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                      '${formatMoney(paid)} of ${formatMoney(debt.originalAmount)} paid',
                      style: theme.textTheme.labelSmall),
                ),
                Text(
                  settled ? 'Cleared' : '${formatMoney(debt.outstandingAmount)} left',
                  style: DesignType.numeric(fontSize: 13).copyWith(
                      color: settled
                          ? context.readable(DesignColors.success)
                          : null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _dayLabel(DateTime d) {
  final today = startOfDay(DateTime.now());
  final day = startOfDay(d);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat('EEEE').format(d);
  return DateFormat('d MMM y').format(d);
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});
  final List<CollectionEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <DateTime, List<CollectionEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(startOfDay(e.paidAt), () => []).add(e);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final day in days) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(
                top: DesignSpacing.sm, bottom: DesignSpacing.xs),
            child: Row(
              children: <Widget>[
                Expanded(
                    child: Text(_dayLabel(day),
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700))),
                Text(
                  formatMoney(collectedBetween(groups[day]!, day,
                      day.add(const Duration(days: 1)))),
                  style: DesignType.numeric(fontSize: 13).copyWith(
                      color: context.readable(DesignColors.success)),
                ),
              ],
            ),
          ),
          for (final e in groups[day]!) _InstalmentRow(entry: e),
        ],
      ],
    );
  }
}

class _InstalmentRow extends StatelessWidget {
  const _InstalmentRow({required this.entry});
  final CollectionEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = <String>[
      DateFormat('h:mm a').format(entry.paidAt),
      paymentMethodLabel(entry.method),
      if (entry.reference != null) entry.reference!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(
            horizontal: DesignSpacing.lg, vertical: DesignSpacing.md),
        borderRadius: DesignSpacing.radiusMd,
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: DesignColors.success.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.south_west_rounded,
                  size: 18, color: context.readable(DesignColors.success)),
            ),
            const SizedBox(width: DesignSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                  Text('Towards ${entry.what}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            const SizedBox(width: DesignSpacing.sm),
            Text('+${formatMoney(entry.amount)}',
                style: DesignType.numeric(fontSize: 14)
                    .copyWith(color: context.readable(DesignColors.success))),
          ],
        ),
      ),
    );
  }
}
