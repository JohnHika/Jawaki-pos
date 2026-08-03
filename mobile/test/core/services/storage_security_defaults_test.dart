import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:axon_pos/core/services/storage_service.dart';

void main() {
  test(
      'new devices keep an authenticated session open until auto-lock is enabled',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();

    expect(storage.requireUnlockOnResume(), isFalse);
    expect(storage.getAutoLockMinutes(), 0);
    expect(storage.isRememberLoginEnabled(), isTrue);
  });
}
