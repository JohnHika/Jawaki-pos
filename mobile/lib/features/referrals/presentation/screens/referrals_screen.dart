import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';

final referralSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return getIt<ApiClient>().getReferralSummary();
});

/// Invite other shops. Both get free days: the new shop when it activates, the
/// referrer once that shop has paid. Also where a code someone gave you (or a
/// promo code) is entered.
class ReferralsScreen extends ConsumerWidget {
  const ReferralsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(referralSummaryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Invite Shops',
        showBackButton: GoRouter.of(context).canPop(),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(referralSummaryProvider),
        child: summary.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(DesignSpacing.lg),
            children: [
              InlineRetryNotice(
                message: apiErrorMessage(e),
                onRetry: () => ref.invalidate(referralSummaryProvider),
              ),
            ],
          ),
          data: (data) {
            final code = '${data['code'] ?? ''}';
            final referrerDays = asInt(data['referrerDays'], 30);
            final referredDays = asInt(data['referredDays'], 14);
            final rewarded = asInt(data['rewarded']);
            final pending = asInt(data['pending']);
            final daysEarned = asInt(data['daysEarned']);
            final referrals = [
              for (final r in (data['referrals'] as List?) ?? const [])
                if (r is Map) r.cast<String, dynamic>(),
            ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                  DesignSpacing.md, DesignSpacing.lg, DesignSpacing.xxxl),
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(DesignSpacing.lg),
                  borderRadius: DesignSpacing.radiusLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your code',
                          style: TextStyle(
                              color: secondary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(code,
                          style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2)),
                      const SizedBox(height: DesignSpacing.sm),
                      Text(
                        'A shop that signs up with your code gets $referredDays extra free days. When it activates, you get $referrerDays free days.',
                        style: TextStyle(color: secondary),
                      ),
                      const SizedBox(height: DesignSpacing.lg),
                      GradientButton(
                        label: 'Share on WhatsApp',
                        icon: Icons.share_rounded,
                        onPressed: () => Share.share('${data['shareText']}'),
                      ),
                      const SizedBox(height: DesignSpacing.sm),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          showGlassSnackBar(context, 'Code copied',
                              icon: Icons.copy_rounded,
                              color: DesignColors.success);
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy code'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DesignSpacing.lg),
                Row(children: [
                  Expanded(
                      child: _Stat(
                          label: 'Joined', value: '$rewarded', color: DesignColors.success)),
                  const SizedBox(width: DesignSpacing.md),
                  Expanded(
                      child: _Stat(
                          label: 'Waiting', value: '$pending', color: DesignColors.warning)),
                  const SizedBox(width: DesignSpacing.md),
                  Expanded(
                      child: _Stat(
                          label: 'Days earned',
                          value: '$daysEarned',
                          color: DesignColors.accent)),
                ]),
                if (referrals.isNotEmpty) ...[
                  const SizedBox(height: DesignSpacing.lg),
                  const FormLabel('Shops you invited'),
                  const SizedBox(height: 6),
                  for (final r in referrals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                      child: ListCard(
                        leading: Icon(
                          r['status'] == 'REWARDED'
                              ? Icons.check_circle_rounded
                              : Icons.hourglass_top_rounded,
                          color: r['status'] == 'REWARDED'
                              ? DesignColors.success
                              : DesignColors.warning,
                        ),
                        title: '${r['name']}',
                        subtitle: r['status'] == 'REWARDED'
                            ? 'Joined · you earned ${asInt(r['daysEarned'])} days'
                            : 'Signed up · waiting for them to activate',
                      ),
                    ),
                ],
                const SizedBox(height: DesignSpacing.xl),
                const _RedeemCard(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(DesignSpacing.md),
      borderRadius: DesignSpacing.radiusLg,
      child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

/// "Have a code?" Works for another shop's referral code and for a promo code.
class _RedeemCard extends ConsumerStatefulWidget {
  const _RedeemCard();

  @override
  ConsumerState<_RedeemCard> createState() => _RedeemCardState();
}

class _RedeemCardState extends ConsumerState<_RedeemCard> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _ok = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await getIt<ApiClient>().redeemCode(_code.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = true;
        _message = '${result['message'] ?? 'Code accepted.'}';
        _code.clear();
      });
      ref.invalidate(referralSummaryProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = false;
        _message = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(DesignSpacing.lg),
      borderRadius: DesignSpacing.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Have a code?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
              'Enter a code another shop gave you, or a promo code from Counterbase.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: DesignSpacing.md),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _redeem(),
            decoration: kitFieldDecoration(context,
                label: 'Code', prefixIcon: Icons.redeem_rounded),
          ),
          if (_message != null) ...[
            const SizedBox(height: DesignSpacing.sm),
            Text(_message!,
                style: TextStyle(
                    color: _ok ? DesignColors.success : DesignColors.error,
                    fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: DesignSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _redeem,
              child: Text(_busy ? 'Checking...' : 'Use code'),
            ),
          ),
        ],
      ),
    );
  }
}
