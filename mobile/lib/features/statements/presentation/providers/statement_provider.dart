import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/statement_models.dart';

/// Replies from customers, newest first, pending ones before handled ones.
final statementClaimsProvider =
    FutureProvider.autoDispose<List<StatementClaim>>((ref) async {
  final rows = await getIt<ApiClient>().getStatementClaims();
  final claims = rows.map(StatementClaim.fromJson).toList();
  claims.sort((a, b) {
    if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
    return (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000));
  });
  return claims;
});

final pendingClaimCountProvider = Provider.autoDispose<int>((ref) {
  final claims = ref.watch(statementClaimsProvider).valueOrNull ?? const [];
  return claims.where((c) => c.isPending).length;
});
