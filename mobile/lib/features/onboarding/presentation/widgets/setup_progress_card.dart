import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/setup_checklist.dart';
import '../setup_providers.dart';

/// Sits on the owner's home screen until every setup step is done or put
/// off, and names the next one.
class SetupProgressCard extends ConsumerWidget {
  const SetupProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist = ref.watch(setupChecklistProvider).valueOrNull;
    final next = checklist?.next;
    if (checklist == null || next == null) return const SizedBox.shrink();
    final palette = SignInPalette.of(context);
    final total = checklist.steps.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.xl),
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await context.push('/setup');
            ref.invalidate(setupChecklistProvider);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.line),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: checklist.doneCount / total,
                        strokeWidth: 4,
                        backgroundColor: palette.line,
                        color: DesignColors.success,
                      ),
                      Text('${checklist.doneCount}/$total',
                          style: TextStyle(
                              color: palette.ink,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Finish setting up',
                          style: TextStyle(
                              color: palette.ink,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Next: ${_lower(next)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: palette.soft, fontSize: 13.5)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _lower(SetupStep step) =>
      step.title[0].toLowerCase() + step.title.substring(1);
}
