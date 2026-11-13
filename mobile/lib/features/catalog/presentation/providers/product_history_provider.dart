import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../domain/stock_status.dart';

/// A product's latest stock movements (sales, deliveries, count corrections),
/// kept live while its inspector is open. Only shops kept on this computer have
/// the history; a connected shop gets an empty list.
final productMovementsProvider = StreamProvider.autoDispose
    .family<List<StockMovement>, String>((ref, productId) async* {
  if (!getIt<AuthService>().isLocalWorkspace) {
    yield const <StockMovement>[];
    return;
  }
  final db = getIt<AppDatabase>();
  await for (final _ in db.watchStockForProduct(productId)) {
    try {
      final rows =
          await db.getLocalProductStockHistory(productId, limit: 12);
      yield [
        for (final row in rows)
          StockMovement(
            kind: switch (row['kind']) {
              'sale' => StockMovementKind.sale,
              'delivery' => StockMovementKind.delivery,
              _ => StockMovementKind.correction,
            },
            at: row['at'] as DateTime,
            quantity: (row['quantity'] as num).toDouble(),
            note: row['note'] as String?,
            unitCost: (row['unitCost'] as num?)?.toDouble(),
          ),
      ];
    } catch (_) {
      // History is a convenience. The inspector still works without it.
      yield const <StockMovement>[];
    }
  }
});
