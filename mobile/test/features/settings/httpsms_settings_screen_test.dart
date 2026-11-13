import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/settings/presentation/screens/httpsms_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage extends StorageService {
  String? apiKey;
  String? sender;

  @override
  Future<String?> getHttpsmsApiKey() async => apiKey;

  @override
  Future<String?> getHttpsmsSenderNumber() async => sender;

  @override
  Future<void> saveHttpsmsApiKey(String key) async => apiKey = key;

  @override
  Future<void> saveHttpsmsSenderNumber(String number) async => sender = number;

  @override
  Future<void> clearHttpsmsCredentials() async {
    apiKey = null;
    sender = null;
  }
}

void main() {
  late _MemoryStorage storage;

  setUp(() async {
    await getIt.reset();
    storage = _MemoryStorage();
    getIt.registerSingleton<StorageService>(storage);
  });

  tearDown(() async => getIt.reset());

  testWidgets('stores the account key and sender in device settings',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HttpsmsSettingsScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('httpsms-account-api-key')),
      'sensitive-account-key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('httpsms-sender-number')),
      '0712 345 678',
    );
    await tester.tap(find.byKey(const ValueKey('httpsms-save')));
    await tester.pumpAndSettle();

    expect(storage.apiKey, 'sensitive-account-key');
    expect(storage.sender, '+254712345678');
    expect(find.text('sensitive-account-key'), findsNothing);
    expect(find.text('HTTPSMS connection saved securely on this device.'),
        findsOneWidget);
  });

  testWidgets('rejects an invalid sender number before saving the key',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HttpsmsSettingsScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('httpsms-account-api-key')),
      'sensitive-account-key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('httpsms-sender-number')),
      '123',
    );
    await tester.tap(find.byKey(const ValueKey('httpsms-save')));
    await tester.pumpAndSettle();

    expect(storage.apiKey, isNull);
    expect(storage.sender, isNull);
    expect(find.textContaining('valid phone number'), findsOneWidget);
  });
}
