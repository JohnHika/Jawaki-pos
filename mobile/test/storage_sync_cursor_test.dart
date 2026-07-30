import 'package:axon_pos/core/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'sync cursors are isolated by branch while retaining the latest global value',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();

    final branchATime = DateTime.utc(2026, 7, 30, 10);
    final branchBTime = DateTime.utc(2026, 7, 30, 11);

    await storage.saveLastSyncAt(branchATime, branchId: 'branch-a');
    await storage.saveLastSyncAt(branchBTime, branchId: 'branch-b');

    expect(storage.getLastSyncAt(branchId: 'branch-a'), branchATime);
    expect(storage.getLastSyncAt(branchId: 'branch-b'), branchBTime);
    expect(storage.getLastSyncAt(branchId: 'branch-c'), isNull);
    expect(storage.getLastSyncAt(), branchBTime);

    const cursorA = 'v1|cutoff-a|timestamp-a|STOCK_ADJUSTED|event-a';
    const cursorB = 'v1|cutoff-b|timestamp-b|SALE_CREATED|event-b';
    await storage.saveSyncCursor(cursorA, branchId: 'branch-a');
    await storage.saveSyncCursor(cursorB, branchId: 'branch-b');

    expect(storage.getSyncCursor(branchId: 'branch-a'), cursorA);
    expect(storage.getSyncCursor(branchId: 'branch-b'), cursorB);
    expect(storage.getSyncCursor(branchId: 'branch-c'), isNull);
  });
}
