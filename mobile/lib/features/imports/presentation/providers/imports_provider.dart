import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/import_models.dart';

final importsProvider =
    FutureProvider.autoDispose<List<ImportSummary>>((ref) async {
  final rows = await getIt<ApiClient>().getImports();
  return rows.map(ImportSummary.fromJson).toList();
});

final importDetailProvider = FutureProvider.autoDispose
    .family<ImportDetail, String>((ref, id) async {
  final json = await getIt<ApiClient>().getImport(id);
  return ImportDetail.fromJson(json);
});
