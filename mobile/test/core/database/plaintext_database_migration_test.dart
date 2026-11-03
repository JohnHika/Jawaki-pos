import 'dart:io';
import 'dart:typed_data';

import 'package:axon_pos/core/database/plaintext_database_migration.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real SQLCipher is not available on the test host, so these tests cover the
/// file handling that decides whether a customer keeps their data: when a
/// migration runs, what survives each kind of failure, and what is left on
/// disk afterwards. The SQL export itself is exercised on a device.
void main() {
  late Directory dir;
  late File dbFile;
  const key = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

  final plaintextBytes = Uint8List.fromList([
    ...PlaintextDatabaseMigration.sqliteFileHeader,
    ...List<int>.generate(200, (i) => i % 251),
  ]);
  final encryptedBytes = Uint8List.fromList(
    List<int>.generate(300, (i) => (i * 7 + 13) % 256),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('plaintext_migration_test');
    dbFile = File('${dir.path}/pos_database_encrypted.sqlite');
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  PlaintextDatabaseMigration build({
    PlaintextDatabaseExport? export,
    EncryptedDatabaseVerifier? verify,
  }) {
    return PlaintextDatabaseMigration(
      file: dbFile,
      key: key,
      export: export ??
          (plain, target, k) async {
            expect(k, key);
            await target.writeAsBytes(encryptedBytes);
          },
      verify: verify ?? (target, k) async {},
    );
  }

  group('hasPlaintextHeader', () {
    test('is false when the file does not exist', () async {
      expect(await PlaintextDatabaseMigration.hasPlaintextHeader(dbFile), false);
    });

    test('is false for a file shorter than the header', () async {
      await dbFile.writeAsBytes([1, 2, 3]);
      expect(await PlaintextDatabaseMigration.hasPlaintextHeader(dbFile), false);
    });

    test('is true for a plain SQLite file and false for an encrypted one',
        () async {
      await dbFile.writeAsBytes(plaintextBytes);
      expect(await PlaintextDatabaseMigration.hasPlaintextHeader(dbFile), true);
      await dbFile.writeAsBytes(encryptedBytes);
      expect(await PlaintextDatabaseMigration.hasPlaintextHeader(dbFile), false);
    });
  });

  group('migrateIfNeeded', () {
    test('does nothing for a brand new install', () async {
      var exported = false;
      final migrated = await build(export: (a, b, c) async {
        exported = true;
      }).migrateIfNeeded();

      expect(migrated, false);
      expect(exported, false);
      expect(await dbFile.exists(), false);
    });

    test('does nothing for a database that is already encrypted', () async {
      await dbFile.writeAsBytes(encryptedBytes);
      var exported = false;

      final migrated = await build(export: (a, b, c) async {
        exported = true;
      }).migrateIfNeeded();

      expect(migrated, false);
      expect(exported, false);
      expect(await dbFile.readAsBytes(), encryptedBytes);
    });

    test('swaps in the encrypted file and keeps the plaintext as a backup',
        () async {
      await dbFile.writeAsBytes(plaintextBytes);

      final migration = build();
      final migrated = await migration.migrateIfNeeded();

      expect(migrated, true);
      expect(await dbFile.readAsBytes(), encryptedBytes);
      expect(await migration.plaintextBackup.readAsBytes(), plaintextBytes);
      expect(await File('${dbFile.path}.encrypting').exists(), false);
    });

    test('removes stale journal files that belonged to the plaintext file',
        () async {
      await dbFile.writeAsBytes(plaintextBytes);
      await File('${dbFile.path}-wal').writeAsBytes([1]);
      await File('${dbFile.path}-shm').writeAsBytes([1]);

      await build().migrateIfNeeded();

      expect(await File('${dbFile.path}-wal').exists(), false);
      expect(await File('${dbFile.path}-shm').exists(), false);
    });

    test('a leftover staging file from an earlier crash is replaced', () async {
      await dbFile.writeAsBytes(plaintextBytes);
      await File('${dbFile.path}.encrypting').writeAsBytes([9, 9, 9]);

      final migrated = await build().migrateIfNeeded();

      expect(migrated, true);
      expect(await dbFile.readAsBytes(), encryptedBytes);
    });

    test('an export failure leaves the original untouched and cleans up',
        () async {
      await dbFile.writeAsBytes(plaintextBytes);

      await expectLater(
        build(export: (plain, target, k) async {
          await target.writeAsBytes([1, 2, 3]); // half-written output
          throw StateError('row count differs');
        }).migrateIfNeeded(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('original data is untouched'),
              contains('row count differs')),
        )),
      );

      expect(await dbFile.readAsBytes(), plaintextBytes);
      expect(await File('${dbFile.path}.encrypting').exists(), false);
      expect(await File('${dbFile.path}.plaintext.bak').exists(), false);
    });

    test('a failed verification leaves the original untouched', () async {
      await dbFile.writeAsBytes(plaintextBytes);

      await expectLater(
        build(verify: (target, k) async {
          throw StateError('file is not a database');
        }).migrateIfNeeded(),
        throwsA(isA<StateError>()),
      );

      expect(await dbFile.readAsBytes(), plaintextBytes);
      expect(await File('${dbFile.path}.encrypting').exists(), false);
    });

    test('refuses an export that is still plaintext', () async {
      await dbFile.writeAsBytes(plaintextBytes);

      await expectLater(
        build(export: (plain, target, k) async {
          await plain.copy(target.path); // "export" that did not encrypt
        }).migrateIfNeeded(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('still unencrypted'),
        )),
      );

      expect(await dbFile.readAsBytes(), plaintextBytes);
      expect(await File('${dbFile.path}.encrypting').exists(), false);
    });

    test('an older backup is replaced, not kept alongside', () async {
      await dbFile.writeAsBytes(plaintextBytes);
      final migration = build();
      await migration.plaintextBackup.writeAsBytes([7, 7, 7]);

      await migration.migrateIfNeeded();

      expect(await migration.plaintextBackup.readAsBytes(), plaintextBytes);
    });

    test('running it again after success is a no-op', () async {
      await dbFile.writeAsBytes(plaintextBytes);
      final migration = build();
      expect(await migration.migrateIfNeeded(), true);
      expect(await migration.migrateIfNeeded(), false);
      expect(await dbFile.readAsBytes(), encryptedBytes);
    });
  });

  group('discardPlaintextBackup', () {
    test('removes the backup and its journal files', () async {
      final base = '${dbFile.path}.plaintext.bak';
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        await File('$base$suffix').writeAsBytes([1]);
      }

      PlaintextDatabaseMigration.discardPlaintextBackup(dbFile);

      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        expect(await File('$base$suffix').exists(), false);
      }
    });

    test('is safe when there is no backup', () {
      expect(() => PlaintextDatabaseMigration.discardPlaintextBackup(dbFile),
          returnsNormally);
    });
  });
}
