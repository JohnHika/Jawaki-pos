import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/stocktake_models.dart';

final stockCountsProvider =
    FutureProvider.autoDispose<List<StockCountSummary>>((ref) async {
  final branchId = getIt<StorageService>().getBranchId();
  final rows = getIt<AuthService>().isLocalWorkspace
      ? await getIt<AppDatabase>().getLocalStockCounts()
      : await getIt<ApiClient>().getStockCounts(branchId: branchId);
  return rows.map(StockCountSummary.fromJson).toList();
});

final stockCountProvider = FutureProvider.autoDispose
    .family<StockCountDetail, String>((ref, id) async {
  final json = getIt<AuthService>().isLocalWorkspace
      ? await getIt<AppDatabase>().getLocalStockCount(id)
      : await getIt<ApiClient>().getStockCount(id);
  return StockCountDetail.fromJson(json);
});
