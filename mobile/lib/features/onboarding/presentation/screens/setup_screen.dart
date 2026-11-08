import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../../settings/presentation/widgets/receipt_details_sheet.dart';
import '../../domain/setup_checklist.dart';
import '../setup_providers.dart';

/// The owner's setup checklist. Each step opens the place where it is done,
/// and ticks itself once the phone can see it done.
class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  Future<void> _open(
      BuildContext context, WidgetRef ref, SetupStep step) async {
    switch (step.action) {
      case SetupAction.receiptDetails:
        await editReceiptDetails(context, ref);
      case SetupAction.products:
        await context.push('/products');
      case SetupAction.staff:
        await context.push('/users');
      case SetupAction.payments:
        await context.push('/settings/recorded-payments');
      case SetupAction.logo:
        await context.push('/settings?open=logo');
      case SetupAction.backup:
        await context.push('/settings?open=backup');
      case SetupAction.sell:
        context.go('/');
        return;
    }
    ref.invalidate(setupChecklistProvider);
  }

  Future<void> _skip(WidgetRef ref, SetupStep step, BuildContext context) =>
      _note(context, ref, () {
        return getIt<AppDatabase>().noteSetupStep(
          step.key,
          status: 'SKIPPED',
          notedBy: getIt<AuthService>().currentUser?['name']?.toString(),
        );
      });

  Future<void> _reopen(WidgetRef ref, SetupStep step, BuildContext context) =>
      _note(context, ref, () => getIt<AppDatabase>().reopenSetupStep(step.key));

  Future<void> _note(BuildContext context, WidgetRef ref,
      Future<void> Function() write) async {
    try {
      await write();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(error))));
      }
    }
    ref.invalidate(setupChecklistProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = SignInPalette.of(context);
    final shop = ref.watch(tenantIdentityProvider).companyName;
    final checklist = ref.watch(setupChecklistProvider);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: Text('Set up your shop',
            style: DesignType.display.copyWith(
                color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: checklist.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not read the checklist. ${apiErrorMessage(error)}',
            style: TextStyle(color: palette.soft),
          ),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(setupChecklistProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _ProgressHeader(shop: shop, checklist: list),
              const SizedBox(height: 20),
              if (list.next case final next?) ...[
                _NextStepCard(
                  step: next,
                  onOpen: () => _open(context, ref, next),
                  onSkip: next.canSkip ? () => _skip(ref, next, context) : null,
                ),
                const SizedBox(height: 24),
              ] else ...[
                _FinishedCard(onOpenShop: () => context.go('/')),
                const SizedBox(height: 24),
              ],
              Text('ALL STEPS',
                  style: TextStyle(
                      color: palette.faint,
                      fontSize: 11.5,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.line),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < list.steps.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: palette.line),
                      _StepRow(
                        number: i + 1,
                        step: list.steps[i],
                        onOpen: () => _open(context, ref, list.steps[i]),
                        onReopen: () => _reopen(ref, list.steps[i], context),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: SignInTextLink(
                  label: 'See the welcome tour again',
                  onPressed: () => context.push('/welcome'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.shop, required this.checklist});

  final String shop;
  final SetupChecklist checklist;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final total = checklist.steps.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          checklist.isFinished
              ? '$shop is ready to sell'
              : 'Get $shop ready to sell',
          style: DesignType.display.copyWith(
              color: palette.ink, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '${checklist.doneCount} of $total done. Steps tick themselves once '
          'the app sees them done.',
          style: TextStyle(color: palette.soft, fontSize: 14.5, height: 1.4),
        ),
        const SizedBox(height: 14),
        Semantics(
          label: '${checklist.doneCount} of $total steps done',
          child: Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: switch (checklist.steps[i].status) {
                        SetupStatus.done => DesignColors.success,
                        SetupStatus.skipped => palette.faint,
                        SetupStatus.todo => palette.line,
                      },
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({
    required this.step,
    required this.onOpen,
    required this.onSkip,
  });

  final SetupStep step;
  final VoidCallback onOpen;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignColors.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(step.icon, color: DesignColors.accentDark, size: 22),
              const SizedBox(width: 8),
              Text('NEXT UP',
                  style: TextStyle(
                      color: palette.soft,
                      fontSize: 11.5,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Text(step.title,
              style: TextStyle(
                  color: palette.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.25)),
          const SizedBox(height: 6),
          Text(step.why,
              style:
                  TextStyle(color: palette.soft, fontSize: 14.5, height: 1.45)),
          const SizedBox(height: 16),
          SignInButton(label: step.actionLabel, onPressed: onOpen),
          SizedBox(
            height: 48,
            child: onSkip == null
                ? null
                : Center(
                    child: SignInTextLink(label: 'Not now', onPressed: onSkip),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FinishedCard extends StatelessWidget {
  const _FinishedCard({required this.onOpenShop});

  final VoidCallback onOpenShop;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignColors.success, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: DesignColors.success, size: 28),
          const SizedBox(height: 10),
          Text('Nothing left to set up',
              style: TextStyle(
                  color: palette.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Steps you put off stay below. Make a backup every week.',
            style: TextStyle(color: palette.soft, fontSize: 14.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          SignInButton(label: 'Start selling', onPressed: onOpenShop),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.step,
    required this.onOpen,
    required this.onReopen,
  });

  final int number;
  final SetupStep step;
  final VoidCallback onOpen;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final done = step.status == SetupStatus.done;
    final skipped = step.status == SetupStatus.skipped;
    final Widget marker = done
        ? const Icon(Icons.check_circle_rounded,
            color: DesignColors.success, size: 26, semanticLabel: 'Done')
        : Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: palette.line, width: 1.5),
            ),
            child: Text('$number',
                style: TextStyle(
                    color: palette.soft,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          );
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            marker,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title,
                      style: TextStyle(
                        color: done ? palette.soft : palette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 3),
                  Text(
                    done
                        ? step.doneText
                        : skipped
                            ? 'Put off for now.'
                            : step.why,
                    style: TextStyle(
                        color: palette.soft, fontSize: 13.5, height: 1.4),
                  ),
                ],
              ),
            ),
            if (skipped)
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
                onPressed: onReopen,
                child: const Text('Bring back'),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right_rounded, color: palette.faint),
              ),
          ],
        ),
      ),
    );
  }
}
