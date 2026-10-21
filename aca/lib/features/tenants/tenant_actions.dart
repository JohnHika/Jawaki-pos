import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import 'tenants_logic.dart';

/// The "Actions" sheet on a company and the flow behind every action in it.
/// Every flow is: ask (confirm / small form) -> runAction -> toast -> [onChanged].
Future<void> showTenantActionsSheet(
  BuildContext context, {
  required TenantDetail tenant,
  required Future<void> Function() onChanged,
}) async {
  final session = context.read<SessionController>();
  final actions = availableActions(
    can: session.can,
    subscriptionStatus: tenant.subscriptionStatus,
    isActive: tenant.isActive,
  );
  if (actions.isEmpty) return;

  final picked = await showModalBottomSheet<TenantAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => _ActionsSheet(tenant: tenant, actions: actions),
  );
  if (picked == null || !context.mounted) return;
  await runTenantAction(context, picked, tenant: tenant, onChanged: onChanged);
}

Future<void> runTenantAction(
  BuildContext context,
  TenantAction action, {
  required TenantDetail tenant,
  required Future<void> Function() onChanged,
}) async {
  final repo = context.read<AcaRepository>();
  final name = tenant.name;

  switch (action) {
    case TenantAction.extend:
      final days = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ExtendSheet(currentEnd: tenant.currentPeriodEnd),
      );
      if (days == null || !context.mounted) return;
      DateTime? newEnd;
      final ok = await runAction(context, () async {
        newEnd = await repo.extendTenant(tenant.id, days);
      });
      if (ok && context.mounted) {
        toast(
          context,
          newEnd == null
              ? 'Extended by ${plural(days, 'day')}'
              : 'Extended by ${plural(days, 'day')}. Now ends ${Fmt.date(newEnd)}',
        );
        await onChanged();
      }

    case TenantAction.suspend:
      final yes = await confirmAction(
        context,
        title: 'Suspend $name?',
        message: 'Their subscription status becomes Suspended. You can reactivate it at any time.',
        confirmLabel: 'Suspend company',
        destructive: true,
      );
      if (!yes || !context.mounted) return;
      final ok = await runAction(context, () => repo.suspendTenant(tenant.id), success: '$name suspended');
      if (ok && context.mounted) await onChanged();

    case TenantAction.reactivate:
      final from = Fmt.label(tenant.subscriptionStatus).toLowerCase();
      final yes = await confirmAction(
        context,
        title: 'Reactivate $name?',
        message: 'Their subscription status goes from $from back to Active.',
        confirmLabel: 'Reactivate company',
      );
      if (!yes || !context.mounted) return;
      final ok = await runAction(context, () => repo.reactivateTenant(tenant.id), success: '$name reactivated');
      if (ok && context.mounted) await onChanged();

    case TenantAction.credit:
      final credit = await showModalBottomSheet<CreditRequest>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const CreditSheet(),
      );
      if (credit == null || !context.mounted) return;
      final yes = await confirmAction(
        context,
        title: 'Issue ${Fmt.kes(credit.amount)} credit?',
        message: '$name gets a goodwill credit of ${Fmt.kes(credit.amount)} on their invoices. '
            'Reason: ${credit.reason}. A credit cannot be removed afterwards.',
        confirmLabel: 'Issue credit',
      );
      if (!yes || !context.mounted) return;
      final ok = await runAction(
        context,
        () => repo.creditTenant(tenant.id, amountKes: credit.amount, reason: credit.reason),
        success: '${Fmt.kes(credit.amount)} credit issued',
      );
      if (ok && context.mounted) await onChanged();

    case TenantAction.forceLogout:
      final yes = await confirmAction(
        context,
        title: 'Sign everyone out?',
        message: 'Every user of $name is signed out on every device. They can sign in again straight away.',
        confirmLabel: 'Sign everyone out',
        destructive: true,
      );
      if (!yes || !context.mounted) return;
      var ended = 0;
      final ok = await runAction(context, () async {
        ended = await repo.forceTenantLogout(tenant.id);
      });
      if (ok && context.mounted) {
        toast(context, ended == 0 ? 'Nobody was signed in' : 'Signed out ${plural(ended, 'session')}');
        await onChanged();
      }

    case TenantAction.lockOut:
      final reason = await promptText(
        context,
        title: 'Lock $name out?',
        message: 'Nobody at this company can sign in, and every session ends right now. '
            'Use this only in an emergency. You can lift it later. The reason is kept in the audit trail.',
        label: 'Reason (optional)',
        confirmLabel: 'Lock company out',
        maxLength: 300,
        destructive: true,
      );
      if (reason == null || !context.mounted) return;
      final ok = await runAction(context, () => repo.lockTenantOut(tenant.id, reason: reason), success: '$name is locked out');
      if (ok && context.mounted) await onChanged();

    case TenantAction.liftLockout:
      await liftTenantLockout(context, tenant: tenant, onChanged: onChanged);
  }
}

/// Shared by the red banner and the Actions sheet.
Future<void> liftTenantLockout(
  BuildContext context, {
  required TenantDetail tenant,
  required Future<void> Function() onChanged,
}) async {
  final repo = context.read<AcaRepository>();
  final reason = await promptText(
    context,
    title: 'Lift the lockout?',
    message: 'People at ${tenant.name} will be able to sign in again. The reason is kept in the audit trail.',
    label: 'Reason (optional)',
    confirmLabel: 'Lift lockout',
    maxLength: 300,
  );
  if (reason == null || !context.mounted) return;
  final ok = await runAction(
    context,
    () => repo.liftTenantLockout(tenant.id, reason: reason),
    success: '${tenant.name} can sign in again',
  );
  if (ok && context.mounted) await onChanged();
}

// ------------------------------------------------------------------ the sheet

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.tenant, required this.actions});

  final TenantDetail tenant;
  final List<TenantAction> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tenant.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final a in actions) _tile(context, p, a),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, AcaPalette p, TenantAction a) {
    final (icon, title, subtitle, danger) = _describe(a);
    final color = danger ? p.danger : p.text;
    return ListTile(
      minTileHeight: 56,
      leading: Icon(icon, color: danger ? p.danger : p.textMuted),
      title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
      onTap: () => Navigator.pop(context, a),
    );
  }

  (IconData, String, String, bool) _describe(TenantAction a) {
    switch (a) {
      case TenantAction.extend:
        return (Icons.update_rounded, 'Extend subscription', 'Push the end date forward by up to a year', false);
      case TenantAction.suspend:
        return (Icons.pause_circle_outline_rounded, 'Suspend', 'Mark the subscription as suspended', true);
      case TenantAction.reactivate:
        return (Icons.play_circle_outline_rounded, 'Reactivate', 'Set the subscription back to active', false);
      case TenantAction.credit:
        return (Icons.card_giftcard_rounded, 'Issue credit', 'Goodwill credit with a reason', false);
      case TenantAction.forceLogout:
        return (Icons.logout_rounded, 'Force sign-out of every user', 'Ends all sessions; they can sign in again', true);
      case TenantAction.lockOut:
        return (Icons.lock_outline_rounded, 'Lock company out', 'Emergency kill switch: nobody can sign in', true);
      case TenantAction.liftLockout:
        return (Icons.lock_open_rounded, 'Lift lockout', 'Let people sign in again', false);
    }
  }
}

// ------------------------------------------------------------- extend sheet

class ExtendSheet extends StatefulWidget {
  const ExtendSheet({super.key, required this.currentEnd});
  final DateTime? currentEnd;

  @override
  State<ExtendSheet> createState() => _ExtendSheetState();
}

class _ExtendSheetState extends State<ExtendSheet> {
  static const _quick = [7, 14, 30];
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int? get _days => parseExtendDays(_c.text);

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final days = _days;
    final typed = _c.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Extend subscription', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Moves the end date forward. It does not change the status or create an invoice. '
              'Currently ${widget.currentEnd == null ? 'no end date is set' : 'ends ${Fmt.date(widget.currentEnd)} (${Fmt.daysUntil(widget.currentEnd)})'}.',
              style: TextStyle(color: p.textMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in _quick)
                  ChoiceChip(
                    label: Text('$d days'),
                    selected: days == d,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _c.text = '$d'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _c,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Or a custom number of days (1–365)',
                errorText: typed && days == null ? 'Enter a whole number from 1 to 365' : null,
              ),
            ),
            if (days != null) ...[
              const SizedBox(height: 12),
              Text(
                'New end date: ${Fmt.date(projectedPeriodEnd(widget.currentEnd, days))}',
                style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: days == null ? null : () => Navigator.pop(context, days),
              child: Text(days == null ? 'Choose how long' : 'Extend by ${plural(days, 'day')}'),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- credit sheet

class CreditRequest {
  const CreditRequest(this.amount, this.reason);
  final num amount;
  final String reason;
}

class CreditSheet extends StatefulWidget {
  const CreditSheet({super.key});

  @override
  State<CreditSheet> createState() => _CreditSheetState();
}

class _CreditSheetState extends State<CreditSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final amount = parseKesAmount(_amount.text);
    final reason = _reason.text.trim();
    final amountBad = _amount.text.trim().isNotEmpty && amount == null;
    final canSubmit = amount != null && reason.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Issue credit', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'A goodwill credit appears on the company\'s invoices as a negative amount. It is recorded in the audit trail.',
              style: TextStyle(color: p.textMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: 'KES ',
                errorText: amountBad ? 'Enter at least KES 1' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLength: 170,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: canSubmit ? () => Navigator.pop(context, CreditRequest(amount, reason)) : null,
              child: Text(amount == null ? 'Review credit' : 'Review ${Fmt.kes(amount)} credit'),
            ),
          ],
        ),
      ),
    );
  }
}
