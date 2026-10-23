import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/company_caches.dart';
import '../../../core/services/till_guard.dart';
import '../../../core/services/till_rules_cache.dart';
import '../../../core/theme/design_system.dart';

/// Applies the shop's price, discount and credit rules at the till.
///
/// The rules live on the phone because a sale rung up with no signal never
/// reaches the server until later, and by then it has already happened. A
/// sale that slips through (or is made on a phone with stale rules) is still
/// recorded for the owner when it syncs.
class TillGuardService {
  TillGuardService._() {
    // Rules and price floors belong to one company: forget them on sign-out.
    CompanyCaches.register(_cache.clear);
  }

  static final TillGuardService instance = TillGuardService._();

  final TillRulesCache _cache = TillRulesCache();
  bool _refreshing = false;

  /// Pulls the latest rules if the cached ones are old. Never throws: the till
  /// carries on with whatever it already has.
  Future<void> refreshIfStale({bool force = false}) async {
    await _cache.load();
    if (!force && !_cache.isStale) return;
    if (_refreshing) return;
    _refreshing = true;
    try {
      final json = await getIt<ApiClient>().getTillRules();
      if (json.isNotEmpty) await _cache.save(TillRules.fromJson(json));
    } catch (e) {
      debugPrint('[TillGuard] refresh failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> clear() => _cache.clear();

  /// Checks a sale. Returns true when it may go ahead (possibly after the
  /// cashier confirms) and false when the sale must be changed first.
  Future<bool> review(
    BuildContext context, {
    required List<GuardLine> lines,
    double cartDiscount = 0,
    double creditAmount = 0,
    String? customerId,
    String? customerName,
    bool includePricing = true,
  }) async {
    final rules = await _cache.load();
    if (rules == null) return true; // never loaded: nothing to apply yet

    // A stale copy is better than none, but try to freshen it for next time.
    if (_cache.isStale) {
      // ignore: unawaited_futures
      refreshIfStale();
    }

    final issues = <GuardIssue>[
      if (includePricing)
        ...assessPricing(rules, lines, cartDiscount: cartDiscount),
    ];

    if (creditAmount > 0) {
      CreditStanding? standing;
      if (customerId != null) {
        try {
          final json = await getIt<ApiClient>()
              .getCustomerCredit(customerId)
              .timeout(const Duration(seconds: 4));
          if (json.isNotEmpty) standing = CreditStanding.fromJson(json);
        } catch (_) {
          // Offline or slow: the server will still record it when it syncs.
        }
      }
      issues.addAll(assessCreditSale(
        rules,
        creditAmount: creditAmount,
        hasCustomer: customerId != null,
        customerName: customerName,
        standing: standing,
      ));
    }

    if (issues.isEmpty) return true;
    if (!context.mounted) return false;
    return showTillGuardDialog(context, issues);
  }
}

/// Lists what is wrong with a sale. Blocking issues leave only "Change the
/// sale"; otherwise the cashier can go ahead knowing the owner will be told.
Future<bool> showTillGuardDialog(
  BuildContext context,
  List<GuardIssue> issues,
) async {
  final blocking = issues.any((i) => i.blocking);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _TillGuardDialog(issues: issues, blocking: blocking),
  );
  return result == true;
}

class _TillGuardDialog extends StatelessWidget {
  const _TillGuardDialog({required this.issues, required this.blocking});

  final List<GuardIssue> issues;
  final bool blocking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = blocking ? DesignColors.error : DesignColors.warning;

    return AlertDialog(
      backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
      ),
      title: Row(
        children: [
          Icon(
            blocking ? Icons.lock_outline_rounded : Icons.flag_outlined,
            color: accent,
          ),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              blocking ? 'Needs a manager' : 'Check this sale',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        color: issue.severity == GuardSeverity.high
                            ? DesignColors.error
                            : DesignColors.warning,
                      ),
                    ),
                    const SizedBox(width: DesignSpacing.sm),
                    Expanded(child: Text(issue.message)),
                  ],
                ),
              ),
            const SizedBox(height: DesignSpacing.sm),
            Text(
              blocking
                  ? 'Change the price, or ask a manager to approve this sale.'
                  : 'If you continue, the owner will be told about this sale.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? DesignColors.darkTextSecondary
                    : DesignColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Change the sale'),
        ),
        if (!blocking)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: DesignColors.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sell anyway'),
          ),
      ],
    );
  }
}
