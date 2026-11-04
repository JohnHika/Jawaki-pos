import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/licence/data/licence_service.dart';
import 'package:axon_pos/features/licence/domain/licence_codec.dart';
import 'package:axon_pos/features/licence/presentation/licence_providers.dart';
import 'package:axon_pos/features/licence/presentation/plan_licence_screen.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimpleKeyPair keys;
  late StorageService storage;
  late DateTime now;

  setUp(() async {
    keys = await Ed25519().newKeyPair();
    final publicKey = (await keys.extractPublicKey()).bytes;
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialize();
    await storage.saveLocalWorkspace({
      'tenant': {'id': 'shop-1'},
      'createdAt': DateTime.utc(2026, 11, 4).toIso8601String(),
    });
    now = DateTime.utc(2026, 11, 5);
    licenceServiceBuilder =
        () => LicenceService(storage, publicKey: publicKey, clock: () => now);
    LicenceGate.standing = null;
  });

  tearDown(() {
    licenceServiceBuilder = () => throw StateError('reset');
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: PlanLicenceScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a new shop sees its free trial and its shop ID', (tester) async {
    await open(tester);
    expect(find.text('Free trial'), findsOneWidget);
    expect(find.textContaining('Your free trial ends on'), findsOneWidget);
    expect(find.text('shop-1'), findsOneWidget);
    expect(find.textContaining('never charge a late fee'), findsOneWidget);
  });

  testWidgets('a good code makes the shop active', (tester) async {
    final token = await tester.runAsync(() => signLicence(
          LicenceClaims(
            shopId: 'shop-1',
            plan: 'CORE',
            issuedAt: DateTime.utc(2026, 11, 5),
            dueAt: DateTime.utc(2026, 12, 5),
            everPaid: true,
          ),
          keys,
        ));
    await open(tester);

    await tester.enterText(find.byType(TextField), token!);
    await tester.tap(find.text('Apply code'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('CORE'), findsOneWidget);
  });

  testWidgets('a code for another shop is explained', (tester) async {
    final token = await tester.runAsync(() => signLicence(
          LicenceClaims(
            shopId: 'shop-2',
            plan: 'CORE',
            issuedAt: DateTime.utc(2026, 11, 5),
            dueAt: DateTime.utc(2026, 12, 5),
            everPaid: true,
          ),
          keys,
        ));
    await open(tester);

    await tester.enterText(find.byType(TextField), token!);
    await tester.tap(find.text('Apply code'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.textContaining('different shop'), findsOneWidget);
    expect(find.text('Free trial'), findsOneWidget);
  });

  testWidgets('sales paused says records stay open', (tester) async {
    now = DateTime.utc(2026, 11, 20);
    await open(tester);
    expect(find.text('New sales paused'), findsOneWidget);
    expect(find.textContaining('safe and you can still view and export'),
        findsOneWidget);
  });
}
