import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/legal_link.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../../../subscription/domain/subscription_plans.dart';

/// A plan change that is waiting for the next renewal.
class ScheduledPlanChange {
  const ScheduledPlanChange({required this.planId, this.effectiveAt});

  /// Lower-case plan id (`core`, `business`, `enterprise`).
  final String planId;
  final DateTime? effectiveAt;
}

/// What the owner just did, so the sheet can acknowledge it.
enum PlanChangeKind { upgrade, downgrade, choose, kept }

/// Every plan side by side, the current one marked, with Upgrade, Downgrade
/// and Keep. Opened from Manage plan on the phone and the computer.
///
/// It only decides and displays; [onChange] and [onCancelChange] do the saving
/// (and throw on failure, which the sheet shows without closing).
class PlanCompareSheet extends StatefulWidget {
  const PlanCompareSheet({
    super.key,
    required this.currentPlanId,
    required this.onChange,
    required this.onCancelChange,
    required this.errorText,
    this.isTrial = false,
    this.overdue = false,
    this.renewsOn,
    this.scheduled,
  });

  /// Lower-case id of the plan in force now (`trial` during the free trial).
  final String currentPlanId;
  final bool isTrial;

  /// Unpaid and past its date: a change re-prices the open invoice.
  final bool overdue;

  /// When the paid period ends, the day a change takes effect.
  final DateTime? renewsOn;
  final ScheduledPlanChange? scheduled;

  final Future<void> Function(String planId) onChange;
  final Future<void> Function() onCancelChange;
  final String Function(Object error) errorText;

  @override
  State<PlanCompareSheet> createState() => _PlanCompareSheetState();
}

enum _Stage { browsing, saving, done }

class _PlanCompareSheetState extends State<PlanCompareSheet> {
  String? _selected;
  bool _agreed = false;
  _Stage _stage = _Stage.browsing;
  String? _error;
  String _doneTitle = '';
  String _doneBody = '';

  static final _date = DateFormat('d MMM yyyy');

  double _price(String id) => planPriceKes(id);

  PlanChangeKind _kindFor(String id) {
    if (widget.isTrial) return PlanChangeKind.choose;
    return _price(id) >= _price(widget.currentPlanId)
        ? PlanChangeKind.upgrade
        : PlanChangeKind.downgrade;
  }

  String _verb(PlanChangeKind kind) => switch (kind) {
        PlanChangeKind.upgrade => 'Upgrade',
        PlanChangeKind.downgrade => 'Downgrade',
        PlanChangeKind.choose => 'Choose',
        PlanChangeKind.kept => 'Keep',
      };

  /// One plain sentence on when the change happens and what it costs today.
  String _effectNote(String id) {
    final name = planDisplayName(id);
    if (widget.isTrial) {
      return 'Starts when your trial ends and your first payment is confirmed. Nothing is charged today.';
    }
    if (widget.overdue) {
      return 'Your unpaid invoice will be changed to $name. $name starts once it is paid.';
    }
    final when = widget.renewsOn == null
        ? 'your next renewal'
        : 'your next renewal on ${_date.format(widget.renewsOn!)}';
    return 'Takes effect at $when. You keep ${planDisplayName(widget.currentPlanId)} until then and nothing is charged today.';
  }

  Future<void> _confirm() async {
    final id = _selected;
    if (id == null) return;
    final kind = _kindFor(id);
    setState(() {
      _stage = _Stage.saving;
      _error = null;
    });
    try {
      await widget.onChange(id);
      if (!mounted) return;
      final name = planDisplayName(id);
      setState(() {
        _stage = _Stage.done;
        _doneTitle = switch (kind) {
          PlanChangeKind.upgrade => 'Upgrade to $name scheduled',
          PlanChangeKind.downgrade => 'Downgrade to $name scheduled',
          _ => '$name selected',
        };
        _doneBody = _effectNote(id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.browsing;
        _error = widget.errorText(error);
      });
    }
  }

  Future<void> _keepCurrent() async {
    setState(() {
      _stage = _Stage.saving;
      _error = null;
    });
    try {
      await widget.onCancelChange();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.done;
        _doneTitle = 'Staying on ${planDisplayName(widget.currentPlanId)}';
        _doneBody = 'The scheduled change was cancelled. Nothing else changes.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.browsing;
        _error = widget.errorText(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.themed(DesignColors.darkTextPrimary);
    final secondary = context.themed(DesignColors.darkTextSecondary);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _stage == _Stage.done
              ? _buildDone(context, primary, secondary)
              : SingleChildScrollView(
                  key: const ValueKey('compare'),
                  padding: const EdgeInsets.fromLTRB(
                    DesignSpacing.xl,
                    DesignSpacing.lg,
                    DesignSpacing.xl,
                    DesignSpacing.xxl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: context.themed(DesignColors.darkBorder),
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusFull),
                          ),
                        ),
                      ),
                      const SizedBox(height: DesignSpacing.lg),
                      Text(
                        widget.isTrial ? 'Choose your plan' : 'Change your plan',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: DesignSpacing.xs),
                      Text(
                        widget.isTrial
                            ? 'Pick the plan for after your trial. Paid features start only once the payment is confirmed.'
                            : 'You are on ${planDisplayName(widget.currentPlanId)}. A change never cuts off what you have already paid for.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: secondary, height: 1.4),
                      ),
                      if (widget.scheduled != null) ...[
                        const SizedBox(height: DesignSpacing.lg),
                        _buildScheduledBanner(context),
                      ],
                      const SizedBox(height: DesignSpacing.lg),
                      for (final plan in kAvailablePlans) ...[
                        _buildPlanTile(context, plan),
                        const SizedBox(height: DesignSpacing.sm),
                      ],
                      if (PlanPrices.isLastKnown)
                        Padding(
                          padding: const EdgeInsets.only(top: DesignSpacing.xs),
                          child: Text(
                            'Prices shown are the last ones we received. They update when you are back online.',
                            key: const ValueKey('prices-last-known'),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: secondary),
                          ),
                        ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _selected == null
                            ? const SizedBox(width: double.infinity)
                            : _buildConfirm(context),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: DesignSpacing.md),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 18, color: DesignColors.error),
                            const SizedBox(width: DesignSpacing.sm),
                            Expanded(
                              child: Text(
                                _error!,
                                key: const ValueKey('plan-change-error'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: context.readable(DesignColors.error),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildScheduledBanner(BuildContext context) {
    final s = widget.scheduled!;
    final theme = Theme.of(context);
    final busy = _stage == _Stage.saving;
    final when = s.effectiveAt == null ? '' : ' on ${_date.format(s.effectiveAt!)}';
    return Container(
      key: const ValueKey('scheduled-banner'),
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: DesignColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded,
              size: 20, color: DesignColors.accent),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              'Switching to ${planDisplayName(s.planId)}$when',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.themed(DesignColors.darkTextPrimary),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('plan-change-cancel-scheduled'),
            onPressed: busy ? null : _keepCurrent,
            child: Text(busy ? 'Cancelling…' : 'Cancel change'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanTile(BuildContext context, SubscriptionPlan plan) {
    final theme = Theme.of(context);
    final isCurrent = plan.id == widget.currentPlanId;
    final isPending = widget.scheduled?.planId == plan.id;
    final isSelected = _selected == plan.id;
    final primary = context.themed(DesignColors.darkTextPrimary);
    final secondary = context.themed(DesignColors.darkTextSecondary);
    const accent = DesignColors.accent;
    final busy = _stage == _Stage.saving;

    final kind = isCurrent ? null : _kindFor(plan.id);
    final tag = isCurrent
        ? 'Current plan'
        : isPending
            ? 'Scheduled'
            : plan.isPopular
                ? 'Popular'
                : null;

    return Semantics(
      button: !isCurrent,
      selected: isSelected,
      label: '${plan.name}, ${formatKes(plan.priceKes)} a month'
          '${isCurrent ? ', your current plan' : ''}',
      child: TapScale(
        enabled: !isCurrent && !busy,
        child: Material(
          color: isSelected
              ? accent.withValues(alpha: 0.08)
              : context.themed(DesignColors.darkSurface).withValues(alpha: 0.82),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            side: BorderSide(
              color: isSelected
                  ? accent
                  : isCurrent
                      ? DesignColors.success.withValues(alpha: 0.55)
                      : context.themed(DesignColors.darkBorder),
              width: isSelected || isCurrent ? 1.6 : 1,
            ),
          ),
          child: InkWell(
            key: ValueKey('plan-tile-${plan.id}'),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            onTap: isCurrent || busy
                ? null
                : () => setState(() {
                      if (_selected != plan.id) _agreed = false;
                      _selected = plan.id;
                      _error = null;
                    }),
            child: Padding(
              padding: const EdgeInsets.all(DesignSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              plan.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (tag != null) ...[
                              const SizedBox(width: DesignSpacing.sm),
                              _Pill(
                                label: tag,
                                color: isCurrent
                                    ? DesignColors.success
                                    : accent,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: DesignSpacing.xs),
                        Text(
                          plan.tagline,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: secondary, height: 1.35),
                        ),
                        const SizedBox(height: DesignSpacing.sm),
                        Text(
                          _limits(plan.id),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatKes(plan.priceKes),
                        style: DesignType.numeric(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: primary,
                        ),
                      ),
                      Text(
                        'a month',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: secondary),
                      ),
                      if (kind != null) ...[
                        const SizedBox(height: DesignSpacing.sm),
                        Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : kind == PlanChangeKind.downgrade
                                  ? Icons.south_east_rounded
                                  : Icons.north_east_rounded,
                          size: 20,
                          color: isSelected ? accent : secondary,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Branch and staff limits straight from the plan, in one line.
  String _limits(String id) => switch (id) {
        'core' => 'Up to 3 branches · 10 staff',
        'business' => 'Up to 10 branches · 50 staff',
        'enterprise' => 'Unlimited branches and staff',
        _ => '',
      };

  Widget _buildConfirm(BuildContext context) {
    final id = _selected!;
    final kind = _kindFor(id);
    final name = planDisplayName(id);
    final theme = Theme.of(context);
    final busy = _stage == _Stage.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: DesignSpacing.md),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(DesignSpacing.md),
          decoration: BoxDecoration(
            color: context.themed(DesignColors.darkSurfaceElevated),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: context.themed(DesignColors.darkTextSecondary)),
              const SizedBox(width: DesignSpacing.sm),
              Expanded(
                child: Text(
                  _effectNote(id),
                  key: const ValueKey('plan-effect-note'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.themed(DesignColors.darkTextSecondary),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignSpacing.sm),
        CheckboxListTile(
          key: const ValueKey('plan-terms-checkbox'),
          value: _agreed,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: busy ? null : (v) => setState(() => _agreed = v ?? false),
          title: const TermsConsentText(
            before: 'I agree to the subscription, billing and refund ',
            linkText: 'terms',
            after: ' for the plan shown above.',
            route: '/legal/billing',
          ),
        ),
        const SizedBox(height: DesignSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: SettingsPrimaryButton(
            key: const ValueKey('plan-change-confirm'),
            label: '${_verb(kind)} to $name',
            isLoading: busy,
            onPressed: !_agreed || busy ? null : _confirm,
          ),
        ),
        const SizedBox(height: DesignSpacing.xs),
        Center(
          child: TextButton(
            onPressed: busy ? null : () => setState(() => _selected = null),
            child: Text('Keep ${planDisplayName(widget.currentPlanId)}'),
          ),
        ),
      ],
    );
  }

  Widget _buildDone(BuildContext context, Color primary, Color secondary) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(
        DesignSpacing.xl,
        DesignSpacing.xxxl,
        DesignSpacing.xl,
        DesignSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AnimatedCheckmark(size: 84),
          const SizedBox(height: DesignSpacing.xl),
          Text(
            _doneTitle,
            key: const ValueKey('plan-change-done'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge
                ?.copyWith(color: primary, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: DesignSpacing.sm),
          Text(
            _doneBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: secondary, height: 1.4),
          ),
          const SizedBox(height: DesignSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: SettingsPrimaryButton(
              key: const ValueKey('plan-change-close'),
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.readable(color),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
