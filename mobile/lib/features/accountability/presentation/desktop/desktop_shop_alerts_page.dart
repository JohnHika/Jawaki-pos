import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/storage_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/accountability_provider.dart';
import 'desktop_shop_alerts_view.dart';

/// The routed Shop Alerts page inside the desktop shell. Same providers as the
/// phone page; the filter and the open alert are kept locally.
class DesktopShopAlertsPage extends ConsumerStatefulWidget {
  const DesktopShopAlertsPage({super.key});

  @override
  ConsumerState<DesktopShopAlertsPage> createState() =>
      _DesktopShopAlertsPageState();
}

class _DesktopShopAlertsPageState extends ConsumerState<DesktopShopAlertsPage> {
  DesktopAlertFilter _filter = DesktopAlertFilter.open;
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(alertsProvider);
    final controller = ref.read(alertsProvider.notifier);
    final perms = ref.watch(permissionsProvider);
    final branchId = getIt<StorageService>().getBranchId();

    var today = DesktopTodayState.none;
    String? todayTitle;
    String? todayBody;
    if (branchId != null) {
      final summary = ref.watch(branchSummaryProvider(branchId));
      summary.when(
        loading: () => today = DesktopTodayState.loading,
        error: (_, __) => today = DesktopTodayState.error,
        data: (data) {
          today = DesktopTodayState.ready;
          final text = (data['text'] as Map?)?.cast<String, dynamic>() ?? {};
          todayTitle = '${text['title'] ?? 'Today'}';
          todayBody = '${text['body'] ?? ''}';
        },
      );
    }

    return Scaffold(
      body: DesktopShopAlertsView(
        title: ref
            .watch(businessLayoutProvider)
            .actionLabel('/shop-alerts', 'Shop alerts'),
        alerts: state.page.items,
        openCount: state.page.openCount,
        loadedOnce: state.loadedOnce,
        error: state.error,
        filter: _filter,
        onFilter: (f) => setState(() => _filter = f),
        selectedId: _selected,
        onSelect: (a) => setState(() => _selected = a?.id),
        onSeen: (a) => controller.acknowledge([a.id]),
        onSeenAll: controller.acknowledgeAll,
        onRetry: controller.refresh,
        onRules: perms.has('accountability.manage')
            ? () => context.push('/shop-alerts/rules')
            : null,
        todayState: today,
        todayTitle: todayTitle,
        todayBody: todayBody,
        onRefreshToday: branchId == null
            ? null
            : () => ref.invalidate(branchSummaryProvider(branchId)),
      ),
    );
  }
}
