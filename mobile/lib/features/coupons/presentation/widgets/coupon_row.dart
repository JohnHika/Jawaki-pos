import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/coupon_rules.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../sales/presentation/providers/cart_provider.dart';
import '../../data/coupon_service.dart';

/// "Add a coupon" on the cart, and the applied coupon once it is on. The value
/// is recomputed from the cart every time, so removing an item can switch a
/// minimum-spend coupon off and the cashier sees why.
class CouponRow extends ConsumerWidget {
  const CouponRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final coupon = cart.coupon;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (coupon == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => showCouponSheet(context, ref),
          style: TextButton.styleFrom(
            foregroundColor: DesignColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          icon: const Icon(Icons.local_offer_outlined, size: 18),
          label: const Text('Add a coupon code',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
    }

    final verdict = cart.couponVerdict!;
    final ok = verdict.ok;
    final color = ok ? DesignColors.success : DesignColors.warning;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          DesignSpacing.md, DesignSpacing.sm, DesignSpacing.xs, DesignSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.local_offer_rounded : Icons.info_outline_rounded,
              color: color, size: 20),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(coupon.code,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                Text(
                  ok
                      ? '${kesWhole(cart.couponDiscount)} off'
                      : 'No longer applies: ${verdict.message}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove coupon',
            onPressed: () => ref.read(cartProvider.notifier).removeCoupon(),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Asks for a code, finds it in the shop's coupons (cached, so this works with
/// no signal) and puts it on the cart if it qualifies.
Future<void> showCouponSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _CouponSheet(),
  );
}

class _CouponSheet extends ConsumerStatefulWidget {
  const _CouponSheet();

  @override
  ConsumerState<_CouponSheet> createState() => _CouponSheetState();
}

class _CouponSheetState extends ConsumerState<_CouponSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final typed = normaliseCouponCode(_code.text);
    if (typed.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final service = CouponService.instance;
    var coupon = await service.find(typed);
    if (coupon == null) {
      // The shop may have made it a moment ago; pull a fresh list once.
      await service.refreshIfStale(force: true);
      coupon = await service.find(typed);
    }
    if (!mounted) return;
    if (coupon == null) {
      setState(() {
        _busy = false;
        _error =
            'That code was not found. Check the spelling, or connect to the internet to refresh the list.';
      });
      return;
    }

    final cart = ref.read(cartProvider);
    final verdict = evaluateCoupon(coupon, cart.couponLines,
        customerId: cart.customerId);
    if (!verdict.ok) {
      setState(() {
        _busy = false;
        _error = verdict.message;
      });
      return;
    }
    HapticFeedback.mediumImpact();
    ref.read(cartProvider.notifier).applyCoupon(coupon);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(DesignSpacing.lg, 0, DesignSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + DesignSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Coupon code',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: DesignSpacing.xs),
          Text(
            'The discount comes off this sale and is recorded against the code.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: DesignSpacing.md),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _apply(),
            decoration: kitFieldDecoration(context,
                label: 'Code', hint: 'e.g. SAVE10', prefixIcon: Icons.local_offer_outlined),
          ),
          if (_error != null) ...[
            const SizedBox(height: DesignSpacing.sm),
            Text(_error!,
                style: const TextStyle(
                    color: DesignColors.error, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: DesignSpacing.lg),
          GradientButton(
            label: _busy ? 'Checking...' : 'Apply coupon',
            icon: Icons.check_rounded,
            onPressed: _busy ? null : _apply,
          ),
        ],
      ),
    );
  }
}
