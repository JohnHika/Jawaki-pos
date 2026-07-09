import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/widgets/coach_mark_overlay.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sales/presentation/screens/pos_screen.dart';
import 'home_nav_keys.dart';

/// First-login destination for a fresh staff session: renders the real POS
/// screen underneath (so the tour has real, correctly-laid-out targets to
/// spotlight — HomeScreen's own shell/bottom nav is already active since
/// this route sits inside the same ShellRoute) and, one frame later, runs
/// an interactive coach-mark tour over it. On finish or skip, marks the
/// tour seen and hands off to the plain POS route so subsequent
/// navigation behaves normally.
class StaffTourScreen extends ConsumerStatefulWidget {
  const StaffTourScreen({super.key});

  @override
  ConsumerState<StaffTourScreen> createState() => _StaffTourScreenState();
}

class _StaffTourScreenState extends ConsumerState<StaffTourScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTour());
  }

  Future<void> _startTour() async {
    if (!mounted) return;
    final perms = ref.read(permissionsProvider);

    final steps = <CoachMarkStep>[
      CoachMarkStep(
        targetKey: HomeNavKeys.pos,
        title: 'Make a sale here',
        description:
            'Search or browse products, add them to the cart, and take payment — this is where you\'ll spend most of your time.',
      ),
      CoachMarkStep(
        targetKey: HomeNavKeys.more,
        title: 'Everything else lives here',
        description: 'Tap "More" any time to find Inventory, Reports, Settings, and more.',
        beforeShow: () async {
          HomeNavKeys.moreSheetOpenRequest.value = true;
        },
      ),
      if (perms.canSeeInventory)
        CoachMarkStep(
          targetKey: HomeNavKeys.moreSheetInventory,
          title: 'Track your stock',
          description: 'Check stock levels and receive new deliveries here.',
        ),
      if (perms.canSeeReports)
        CoachMarkStep(
          targetKey: HomeNavKeys.moreSheetReports,
          title: 'See how business is going',
          description: 'Daily, weekly, and monthly sales — all in one place.',
        ),
      CoachMarkStep(
        targetKey: HomeNavKeys.moreSheetSettings,
        title: 'Your account & preferences',
        description: 'Change your PIN, adjust notifications, and find help here.',
        onLeave: () {
          HomeNavKeys.moreSheetOpenRequest.value = false;
        },
      ),
    ];

    final tour = CoachMarkTour(steps: steps, onFinished: _finish);
    await tour.show(context);
  }

  void _finish() {
    getIt<StorageService>().setHasSeenStaffTour(true);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    // The real POS screen underneath — HomeScreen's ShellRoute already
    // supplies the bottom nav chrome the tour spotlights.
    return const POSScreen();
  }
}
