import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/api_message.dart';
import '../../domain/accountability_models.dart';

class AlertsState {
  const AlertsState({
    this.page = const AlertsPage(),
    this.isLoading = false,
    this.loadedOnce = false,
    this.error,
  });

  final AlertsPage page;
  final bool isLoading;
  final bool loadedOnce;
  final String? error;

  AlertsState copyWith({
    AlertsPage? page,
    bool? isLoading,
    bool? loadedOnce,
    String? error,
    bool clearError = false,
  }) =>
      AlertsState(
        page: page ?? this.page,
        isLoading: isLoading ?? this.isLoading,
        loadedOnce: loadedOnce ?? this.loadedOnce,
        error: clearError ? null : (error ?? this.error),
      );
}

/// The owner's alert feed. Refreshes every minute while a screen watches it.
class AlertsController extends StateNotifier<AlertsState> {
  AlertsController() : super(const AlertsState()) {
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    refresh();
  }

  Timer? _timer;
  ApiClient get _api => getIt<ApiClient>();

  Future<void> refresh() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final json = await _api.getAccountabilityAlerts(limit: 60);
      state = state.copyWith(
        page: AlertsPage.fromJson(json),
        isLoading: false,
        loadedOnce: true,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        loadedOnce: true,
        error: apiErrorMessage(e),
      );
    }
  }

  Future<void> acknowledge(List<String> ids) async {
    try {
      await _api.acknowledgeAccountabilityAlerts(ids: ids);
    } finally {
      await refresh();
    }
  }

  Future<void> acknowledgeAll() async {
    try {
      await _api.acknowledgeAccountabilityAlerts(all: true);
    } finally {
      await refresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final alertsProvider =
    StateNotifierProvider.autoDispose<AlertsController, AlertsState>(
  (ref) => AlertsController(),
);

/// Today at one branch, as the owner would read it.
final branchSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, branchId) async {
  return getIt<ApiClient>().getBranchDaySummary(branchId);
});

final accountabilityRulesProvider =
    FutureProvider.autoDispose<AccountabilityRules>((ref) async {
  final json = await getIt<ApiClient>().getAccountabilitySettings();
  return AccountabilityRules(json);
});
