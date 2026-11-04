import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/licence/data/licence_service.dart';
import 'package:axon_pos/features/licence/domain/licence_codec.dart';
import 'package:axon_pos/features/licence/domain/licence_standing.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LicenceClaims _claims({
  String shop = 'shop-1',
  String plan = 'CORE',
  DateTime? due,
  bool paid = true,
}) =>
    LicenceClaims(
      shopId: shop,
      plan: plan,
      issuedAt: DateTime.utc(2026, 11, 4),
      dueAt: due ?? DateTime.utc(2026, 12, 4),
      everPaid: paid,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimpleKeyPair keys;
  late List<int> publicKey;

  setUpAll(() async {
    keys = await Ed25519().newKeyPair();
    publicKey = (await keys.extractPublicKey()).bytes;
  });

  group('licence code', () {
    test('a code made by Arche Axon checks out for its shop', () async {
      final token = await signLicence(_claims(), keys);
      expect(token, startsWith('CBL1.'));

      final check =
          await verifyLicence(token, publicKey: publicKey, shopId: 'shop-1');
      expect(check.isValid, isTrue);
      expect(check.claims!.plan, 'CORE');
      expect(check.claims!.dueAt, DateTime.utc(2026, 12, 4));
      expect(check.claims!.everPaid, isTrue);
    });

    test('spaces and line breaks from copying do not matter', () async {
      final token = await signLicence(_claims(), keys);
      final spread = token.replaceAllMapped(
          RegExp(r'.{20}'), (m) => '${m.group(0)}\n ');
      final check =
          await verifyLicence(spread, publicKey: publicKey, shopId: 'shop-1');
      expect(check.isValid, isTrue);
    });

    test('another shop\'s code is refused', () async {
      final token = await signLicence(_claims(shop: 'shop-2'), keys);
      final check =
          await verifyLicence(token, publicKey: publicKey, shopId: 'shop-1');
      expect(check.problem, LicenceProblem.wrongShop);
    });

    test('a changed payload is refused', () async {
      final token = await signLicence(_claims(), keys);
      final other = await signLicence(
          _claims(due: DateTime.utc(2030, 1, 1)), keys);
      // Put the later due date's payload under the first signature.
      final forged =
          '${other.split('.')[0]}.${other.split('.')[1]}.${token.split('.')[2]}';
      final check =
          await verifyLicence(forged, publicKey: publicKey, shopId: 'shop-1');
      expect(check.problem, LicenceProblem.badSignature);
    });

    test('a code signed with someone else\'s key is refused', () async {
      final stranger = await Ed25519().newKeyPair();
      final token = await signLicence(_claims(), stranger);
      final check =
          await verifyLicence(token, publicKey: publicKey, shopId: 'shop-1');
      expect(check.problem, LicenceProblem.badSignature);
    });

    test('rubbish is malformed', () async {
      for (final text in ['', 'hello', 'CBL1.a.b', 'CBL2.a.b.c', 'CBL1..']) {
        final check =
            await verifyLicence(text, publicKey: publicKey, shopId: 'shop-1');
        expect(check.problem, LicenceProblem.malformed, reason: text);
      }
    });
  });

  group('licence service', () {
    late StorageService storage;
    late DateTime now;

    LicenceService service({List<int>? key}) => LicenceService(
          storage,
          publicKey: key ?? publicKey,
          clock: () => now,
        );

    setUp(() async {
      LicenceGate.standing = null;
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      await storage.initialize();
      await storage.saveLocalWorkspace({
        'tenant': {'id': 'shop-1'},
        'createdAt': DateTime.utc(2026, 11, 4).toIso8601String(),
      });
      now = DateTime.utc(2026, 11, 5);
    });

    test('nothing is enforced while no public key is set', () async {
      final s = LicenceService(storage, publicKey: null, clock: () => now);
      expect(s.enforced, isFalse);
      expect(await s.refresh(), isNull);
      expect(LicenceGate.canSell, isTrue);
    });

    test('a new shop is on trial for seven days', () async {
      final standing = (await service().refresh())!;
      expect(standing.status, LicenceStatus.trial);
      expect(standing.daysLeft, 6);
      expect(LicenceGate.canSell, isTrue);
    });

    test('after the trial and the grace days new sales pause', () async {
      now = DateTime.utc(2026, 11, 14);
      final standing = (await service().refresh())!;
      expect(standing.status, LicenceStatus.salesPaused);
      expect(LicenceGate.canSell, isFalse);
      expect(standing.canViewAndExport, isTrue);
    });

    test('entering a good code unpauses sales', () async {
      now = DateTime.utc(2026, 11, 14);
      final s = service();
      await s.refresh();
      expect(LicenceGate.canSell, isFalse);

      final token = await signLicence(
          _claims(due: DateTime.utc(2026, 12, 14)), keys);
      final check = await s.redeem(token);
      expect(check.isValid, isTrue);
      expect(LicenceGate.canSell, isTrue);
      expect(LicenceGate.standing!.status, LicenceStatus.active);
    });

    test('a code for another shop is not saved', () async {
      final token = await signLicence(_claims(shop: 'shop-2'), keys);
      final check = await service().redeem(token);
      expect(check.problem, LicenceProblem.wrongShop);
      expect(storage.getLicenceToken(), isNull);
    });

    test('winding the clock back does not buy more time', () async {
      final s = service();
      now = DateTime.utc(2026, 11, 14);
      await s.refresh();
      expect(LicenceGate.canSell, isFalse);

      now = DateTime.utc(2026, 11, 5); // clock set back
      await s.refresh();
      expect(LicenceGate.canSell, isFalse);
    });

    test('an expired paid licence follows the same grace', () async {
      final token = await signLicence(
          _claims(due: DateTime.utc(2026, 11, 20)), keys);
      await service().redeem(token);

      now = DateTime.utc(2026, 11, 21);
      expect((await service().refresh())!.status, LicenceStatus.grace);
      now = DateTime.utc(2026, 11, 24);
      expect((await service().refresh())!.status, LicenceStatus.salesPaused);
    });
  });
}
