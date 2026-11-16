import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/auth_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/statement_models.dart';
import '../../domain/statement_sync_recovery.dart';
import '../providers/statement_provider.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../desktop/desktop_statement_replies_view.dart';
import '../../../../core/desktop/desktop_refresh.dart';

/// Customer responses to a statement link. A customer's "I have paid" claim
/// stays informational until a provider-confirmed payment settles the debt.
class StatementRepliesScreen extends ConsumerWidget {
  const StatementRepliesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(businessLayoutProvider);
    if (context.inDesktopShell) {
      return _DesktopRepliesPage(
        title: layout.actionLabel('/statements/replies', 'Debt Replies'),
      );
    }
    if (getIt<AuthService>().isLocalWorkspace) {
      return Scaffold(
        appBar: BrandedAppBar(
          title: layout.actionLabel('/statements/replies', 'Debt Replies'),
          showBackButton: GoRouter.of(context).canPop(),
        ),
        body: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(DesignSpacing.lg),
          children: [
            const SizedBox(height: DesignSpacing.xxl),
            EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Replies need a hosted statement link',
              subtitle:
                  'This standalone workspace keeps records on this device. '
                  'It cannot receive replies from a customer’s online statement '
                  'link. You can still share a local statement from a customer profile.',
              iconColor: DesignColors.warning,
              actionLabel: 'Open customers',
              onAction: () => context.push('/customers'),
            ),
          ],
        ),
      );
    }

    final claims = ref.watch(statementClaimsProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: layout.actionLabel('/statements/replies', 'Debt Replies'),
        showBackButton: GoRouter.of(context).canPop(),
      ),
      body: DesktopRefresh(
        onRefresh: () async => ref.invalidate(statementClaimsProvider),
        child: claims.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) {
            final needsOnlineWorkspace = statementNeedsOnlineWorkspace(e);
            final serviceNeedsUpdate = statementServiceNeedsUpdate(e);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(DesignSpacing.lg),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: DesignSpacing.xl),
                  child: EmptyState(
                    icon: needsOnlineWorkspace
                        ? Icons.cloud_off_rounded
                        : Icons.mark_chat_read_outlined,
                    title: needsOnlineWorkspace
                        ? 'Replies need the online workspace'
                        : serviceNeedsUpdate
                            ? 'Debt replies are temporarily unavailable'
                            : "Couldn't load customer replies",
                    subtitle: needsOnlineWorkspace
                        ? 'Customer replies are available when this app is connected to your online Counterbase workspace. Your sales and debts remain saved on this device.'
                        : serviceNeedsUpdate
                            ? 'Customer replies could not be reached. Your sales and debts are safe. Try again shortly.'
                            : apiErrorMessage(e),
                    iconColor: DesignColors.warning,
                    actionLabel: needsOnlineWorkspace ? null : 'Try again',
                    onAction: needsOnlineWorkspace
                        ? null
                        : () => ref.invalidate(statementClaimsProvider),
                  ),
                ),
              ],
            );
          },
          data: (rows) => rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
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
              : _RepliesList(rows: rows),
        ),
      ),
    );
  }
}

/// The computer page: the same claims and the same approve / reject call,
/// shown as a table with the open reply beside it.
class _DesktopRepliesPage extends ConsumerStatefulWidget {
  const _DesktopRepliesPage({required this.title});

  final String title;

  @override
  ConsumerState<_DesktopRepliesPage> createState() =>
      _DesktopRepliesPageState();
}

class _DesktopRepliesPageState extends ConsumerState<_DesktopRepliesPage> {
  String? _busyId;

  Future<void> _decide(StatementClaim claim, {required bool confirm}) async {
    setState(() => _busyId = claim.id);
    try {
      final result = await getIt<ApiClient>()
          .decideStatementClaim(claim.id, confirm: confirm);
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
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDecide =
        ref.watch(permissionsProvider).has('finance.manage_receivables');
    void refresh() => ref.invalidate(statementClaimsProvider);
    void openFinance() => context.push('/finance');

    DesktopStatementRepliesView view({
      List<StatementClaim> claims = const [],
      bool loading = false,
      DesktopRepliesNotice? notice,
      String? message,
    }) =>
        DesktopStatementRepliesView(
          title: widget.title,
          claims: claims,
          loading: loading,
          notice: notice,
          noticeMessage: message,
          canDecide: canDecide,
          busyId: _busyId,
          onDecide: _decide,
          onOpenFinance: openFinance,
          onOpenCustomers: () => context.push('/customers'),
          onRefresh: refresh,
        );

    if (getIt<AuthService>().isLocalWorkspace) {
      return Scaffold(
        body: view(notice: DesktopRepliesNotice.localWorkspace),
      );
    }
    final claims = ref.watch(statementClaimsProvider);
    return Scaffold(
      body: claims.when(
        loading: () => view(loading: true),
        error: (e, _) => view(
          notice: statementNeedsOnlineWorkspace(e)
              ? DesktopRepliesNotice.needsOnline
              : DesktopRepliesNotice.failed,
          message: statementServiceNeedsUpdate(e)
              ? 'Customer replies could not be reached. Your sales and debts '
                  'are safe. Try again shortly.'
              : apiErrorMessage(e),
        ),
        data: (rows) => view(claims: rows),
      ),
    );
  }
}

/// Replies that still need an answer come first, then the ones already dealt
/// with, each under one quiet label.
class _RepliesList extends StatelessWidget {
  const _RepliesList({required this.rows});

  final List<StatementClaim> rows;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final waiting = rows.where((c) => c.isPending).toList();
    final earlier = rows.where((c) => !c.isPending).toList();

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: label,
            ),
          ),
        );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, DesignSpacing.xxxl),
      children: [
        if (waiting.isNotEmpty) ...[
          heading('Waiting for you (${waiting.length})'),
          for (final claim in waiting) _ReplyCard(claim: claim),
        ],
        if (earlier.isNotEmpty) ...[
          if (waiting.isNotEmpty) const SizedBox(height: DesignSpacing.sm),
          heading('Earlier'),
          for (final claim in earlier) _ReplyCard(claim: claim),
        ],
      ],
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

    final ink = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final edge =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;
    final name = claim.debtorName.trim();
    final owes = 'Still owes ${kesWhole(claim.outstanding)}'
        '${claim.createdAt != null ? '  ·  ${timeAgo(claim.createdAt!)}' : ''}';
    final extras = [
      if (claim.isPaid && claim.mpesaCode != null) 'M-Pesa code ${claim.mpesaCode}',
      if (claim.payerName != null && claim.payerName!.isNotEmpty)
        'Sent by ${claim.payerName}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.readable(color),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Customer' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700, color: ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      headline,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(label: badge, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 50),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(owes, style: TextStyle(color: secondary, fontSize: 12.5)),
                for (final line in extras)
                  Text(line, style: TextStyle(color: secondary, fontSize: 12.5)),
              ],
            ),
          ),
          if (claim.isPending && claim.isPaid) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Text(
                'Not confirmed yet. Check your M-Pesa messages before you '
                'record it.',
                style: TextStyle(color: secondary, fontSize: 12.5, height: 1.35),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => context.push('/finance'),
                  child: const Text('Open Finance'),
                ),
              ),
              if (canDecide) ...[
                const SizedBox(width: DesignSpacing.sm),
                TextButton(
                  onPressed: _busy ? null : () => _decide(confirm: false),
                  child: const Text('Reject'),
                ),
              ],
            ]),
          ],
          if (claim.isPending && !claim.isPaid && canDecide) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _decide(confirm: true),
                  child: const Text('Noted'),
                ),
              ),
              const SizedBox(width: DesignSpacing.sm),
              TextButton(
                onPressed: _busy ? null : () => _decide(confirm: false),
                child: const Text('Reject'),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
