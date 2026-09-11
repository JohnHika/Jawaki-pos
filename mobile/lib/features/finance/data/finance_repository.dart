import '../../../core/network/api_client.dart';
import '../../../core/services/storage_service.dart';
import '../domain/finance_models.dart';

/// Coordinates Finance API reads with the tenant-and-branch scoped local cache.
/// Remote failures intentionally propagate: callers can retain/render the cache
/// while preserving the actual Dio failure for retry or session handling.
class FinanceRepository {
  FinanceRepository({
    required ApiClient apiClient,
    required StorageService storage,
    required this.tenantId,
  })  : _apiClient = apiClient,
        _storage = storage;

  final ApiClient _apiClient;
  final StorageService _storage;
  final String tenantId;

  /// Synchronous cache access keeps the Finance entry path instant even when
  /// the next remote refresh fails due to expired credentials or connectivity.
  FinanceSnapshot? loadCachedSnapshot(String tenantId, String branchId) =>
      _storage.getFinanceSnapshot(tenantId: tenantId, branchId: branchId);

  /// Fetches all Finance resources concurrently. The cache is replaced exactly
  /// once only after every response has completed successfully.
  Future<FinanceSnapshot> refresh(String branchId) async {
    final responses = await Future.wait<Object>(<Future<Object>>[
      _apiClient.getFinanceOverview(branchId),
      _apiClient.getFinancePayables(branchId),
      _apiClient.getRetailReceivables(branchId),
      _apiClient.getPeerDebtors(),
      _apiClient.getPeerReceivables(branchId),
    ]);

    final snapshot = (responses[0] as FinanceSnapshot).copyWith(
      payables: responses[1] as List<FinancePayable>,
      retailReceivables: responses[2] as List<RetailReceivable>,
      peerDebtors: responses[3] as List<PeerDebtor>,
      peerReceivables: responses[4] as List<PeerReceivable>,
      savedAt: DateTime.now().toUtc(),
    );
    await _storage.saveFinanceSnapshot(
      tenantId: tenantId,
      branchId: branchId,
      snapshot: snapshot,
    );
    return snapshot;
  }
}
