import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/statement_models.dart';
import '../providers/statement_provider.dart';

/// Customer responses to a statement link. A customer's "I have paid" claim
/// stays informational until a provider-confirmed payment settles the debt.
class StatementRepliesScreen extends ConsumerWidget {
  const StatementRepliesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(statementClaimsProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Debt Replies',
        showBackButton: GoRouter.of(context).canPop(),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(statementClaimsProvider),
        child: claims.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(DesignSpacing.lg),
            children: [
              InlineRetryNotice(
                message: apiErrorMessage(e),
                onRetry: () => ref.invalidate(statementClaimsProvider),
              ),
            ],
          ),
          data: (rows) => rows.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 80),
                    EmptyState(
                      icon: Icons.mark_chat_read_outlined,
                      title: 'No replies yet',
                      subtitle:
                          'When a customer opens a statement you sent and taps "I have paid" or "I will pay on", it shows up here.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                      DesignSpacing.md, DesignSpacing.lg, DesignSpacing.xxxl),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _ReplyCard(claim: rows[i]),
                ),
        ),
      ),
    );
  }
}

class _ReplyCard extends ConsumerStatefulWidget {
  const _ReplyCard({required this.claim});

  final StatementClaim claim;

  @override
  ConsumerState<_ReplyCard> createState() => _ReplyCardState();
}

class _ReplyCardState extends ConsumerState<_ReplyCard> {
  bool _busy = false;

  Future<void> _decide({required bool confirm}) async {
    setState(() => _busy = true);
    try {
      final result = await getIt<ApiClient>()
          .decideStatementClaim(widget.claim.id, confirm: confirm);
      if (!mounted) return;
      if (result['message'] is String) {
        showGlassSnackBar(context, result['message'] as String,
            icon: Icons.info_outline_rounded);
      }
      ref.invalidate(statementClaimsProvider);
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        apiErrorMessage(e),
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final claim = widget.claim;
    final canDecide =
        ref.watch(permissionsProvider).has('finance.manage_receivables');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    final (badge, color) = switch (claim.status) {
      'CONFIRMED' => ('Done', DesignColors.success),
      'REJECTED' => ('Rejected', DesignColors.error),
      _ => (claim.isPaid ? 'Says paid' : 'Promise', DesignColors.warning),
    };
    final headline = claim.isPaid
        ? 'Says they paid ${kesWhole(claim.amount ?? 0)}'
        : 'Will pay on ${claim.promisedFor == null ? 'a later date' : '${claim.promisedFor!.day}/${claim.promisedFor!.month}'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.md),
      child: GlassCard(
        padding: const EdgeInsets.all(DesignSpacing.lg),
        borderRadius: DesignSpacing.radiusLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(claim.debtorName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              StatusBadge(label: badge, color: color),
            ]),
            const SizedBox(height: 4),
            Text(headline, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (claim.isPaid && claim.mpesaCode != null)
              Text('M-Pesa code ${claim.mpesaCode}',
                  style: TextStyle(color: secondary)),
            if (claim.payerName != null && claim.payerName!.isNotEmpty)
              Text('Sent by ${claim.payerName}',
                  style: TextStyle(color: secondary)),
            const SizedBox(height: 4),
            Text(
              'Still owes ${kesWhole(claim.outstanding)}'
              '${claim.createdAt != null ? ' · ${timeAgo(claim.createdAt!)}' : ''}',
              style: TextStyle(color: secondary, fontSize: 13),
            ),
            if (claim.isPending && claim.isPaid) ...[
              const SizedBox(height: DesignSpacing.md),
              const Text(
                'This is the customer’s claim, not payment confirmation. Check '
                'Paystack or a trusted M-Pesa statement before recording it. '
                'A new payment request is only for money still owed.',
              ),
              const SizedBox(height: DesignSpacing.sm),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push('/finance'),
                    icon: const Icon(Icons.phone_android_rounded),
                    label: const Text('Open Finance'),
                  ),
                ),
                if (canDecide) ...[
                  const SizedBox(width: DesignSpacing.sm),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _decide(confirm: false),
                    child: const Text('Reject claim'),
                  ),
                ],
              ]),
            ],
            if (claim.isPending && !claim.isPaid && canDecide) ...[
              const SizedBox(height: DesignSpacing.md),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _decide(confirm: true),
                    child: const Text('Noted'),
                  ),
                ),
                const SizedBox(width: DesignSpacing.sm),
                OutlinedButton(
                  onPressed: _busy ? null : () => _decide(confirm: false),
                  child: const Text('Reject'),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
