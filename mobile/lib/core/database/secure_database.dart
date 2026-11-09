import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

import 'plaintext_database_migration.dart';

void _loadSqlCipherLibrary() {
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }
}

Future<void> _configureSqlCipherForDatabaseIsolate() async {
  _loadSqlCipherLibrary();
}

/// Secure database connection with SQLCipher encryption
/// Key is stored in flutter_secure_storage (iOS Keychain / Android Keystore)
class SecureDatabaseConnection {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accountName: 'pos_secure_db_key',
    ),
  );

  static const _dbKeyName = 'pos_database_key';
  static const _dbKeyBackupName = 'pos_database_key_backup';
  static const _dbKeyPendingName = 'pos_database_key_pending';
  /// Generate a cryptographically secure 256-bit key (64 hex chars)
  static String _generateKey() {
    final random = math.Random.secure();
    final randomBytes = List<int>.generate(32, (_) => random.nextInt(256));
    return randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Get or create encryption key from secure storage
  static Future<String> _getOrCreateKey() async {
    // Try primary key first
    String? key = await _secureStorage.read(key: _dbKeyName);

    if (key == null) {
      // Try backup key
      key = await _secureStorage.read(key: _dbKeyBackupName);

      if (key == null) {
        // Generate new key
        key = _generateKey();
        await _secureStorage.write(key: _dbKeyName, value: key);
        // Also write to backup
        await _secureStorage.write(key: _dbKeyBackupName, value: key);
      } else {
        // Restore from backup
        await _secureStorage.write(key: _dbKeyName, value: key);
      }
    }

    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw StateError(
          'The encrypted database key is invalid. Restore the device backup or reset local data.');
    }

    return key;
  }

  /// Open encrypted database connection
  static LazyDatabase openSecureConnection() {
    return LazyDatabase(() async {
      // On a computer the documents folder is the person's own files, so the
      // shop database goes in the app's support folder instead.
      final dbFolder = Platform.isWindows || Platform.isLinux || Platform.isMacOS
          ? await getApplicationSupportDirectory()
          : await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'pos_database_encrypted.sqlite'));

      // Get encryption key
      final key = await _getOrCreateKey();

      // Builds from before SQLCipher was really linked left a plain SQLite
      // file under this name (PRAGMA key was silently ignored). PRAGMA rekey
      // cannot encrypt such a file in place, so export it into a new
      // encrypted file first. The original is kept until the new one opens.
      final migrated = await PlaintextDatabaseMigration(
        file: file,
        key: key,
        export: _exportPlaintextToEncrypted,
        verify: _verifyEncryptedDatabase,
      ).migrateIfNeeded();

      // Keep this callback synchronous. drift does not await it, so an error
      // thrown from an async closure escapes as an unhandled exception and
      // the database never finishes opening instead of failing visibly.
      return NativeDatabase.createInBackground(
        file,
        isolateSetup: _configureSqlCipherForDatabaseIsolate,
        setup: (rawDb) {
          final cipherVersion = rawDb.select('PRAGMA cipher_version;');
          if (cipherVersion.isEmpty) {
            throw StateError(
              'SQLCipher is unavailable. The local database was not opened.',
            );
          }

          // New databases and already encrypted databases need the key
          // before their first schema read.
          rawDb.execute("PRAGMA key = '$key';");

          try {
            rawDb.select('SELECT count(*) FROM sqlite_master');
          } catch (error) {
            // Never silently swap to a different key. Continuing would make
            // an encrypted database look empty and risks overwriting data.
            throw StateError('Unable to open encrypted local database: $error');
          }

          if (migrated) {
            // The encrypted copy opened and read back, so the plaintext
            // backup is no longer needed and should not stay on the device.
            PlaintextDatabaseMigration.discardPlaintextBackup(file);
          }
        },
      );
    });
  }

  /// Copies a plain SQLite file into a new SQLCipher file with
  /// `sqlcipher_export`, then checks that every table's row count matches.
  /// Runs in a short-lived isolate so it loads the SQLCipher library the same
  /// way the database isolate does.
  static Future<void> _exportPlaintextToEncrypted(
    File plain,
    File target,
    String key,
  ) {
    final plainPath = plain.path;
    final targetPath = target.path;
    return Isolate.run(() {
      _loadSqlCipherLibrary();
      final db = sqlite3.open(plainPath);
      try {
        if (db.select('PRAGMA cipher_version;').isEmpty) {
          throw StateError('SQLCipher is unavailable.');
        }
        final userVersion =
            db.select('PRAGMA user_version;').first.columnAt(0) as int;
        final quotedTarget = targetPath.replaceAll("'", "''");
        db.execute("ATTACH DATABASE '$quotedTarget' AS encrypted KEY '$key';");
        db.select("SELECT sqlcipher_export('encrypted');");
        // sqlcipher_export does not copy user_version, which drift uses as
        // the schema version. Without this it would re-run every migration.
        db.execute('PRAGMA encrypted.user_version = $userVersion;');

        final tables = db.select(
          "SELECT name FROM main.sqlite_master WHERE type = 'table' "
          "AND substr(name, 1, 7) != 'sqlite_' ORDER BY name",
        );
        for (final row in tables) {
          final name = (row['name'] as String).replaceAll('"', '""');
          final before =
              db.select('SELECT count(*) AS c FROM main."$name"').first['c'];
          final after = db
              .select('SELECT count(*) AS c FROM encrypted."$name"')
              .first['c'];
          if (before != after) {
            throw StateError(
              'Row count differs in table "$name" ($before vs $after).',
            );
          }
        }
        db.execute('DETACH DATABASE encrypted;');
      } finally {
        db.dispose();
      }
    });
  }

  /// Opens the new encrypted file with its key and reads the schema.
  static Future<void> _verifyEncryptedDatabase(File target, String key) {
    final targetPath = target.path;
    return Isolate.run(() {
      _loadSqlCipherLibrary();
      final db = sqlite3.open(targetPath);
      try {
        db.execute("PRAGMA key = '$key';");
        db.select('SELECT count(*) FROM sqlite_master');
      } finally {
        db.dispose();
      }
    });
  }

  /// Change the database encryption key atomically.
  ///
  /// The caller owns the open SQLCipher connection and must rekey it first.
  /// Persisting a replacement key before `PRAGMA rekey` succeeds would lock a
  /// user out of their existing offline sales, so this method intentionally
  /// cannot perform a partial rotation.
  static Future<void> rotateEncryptionKey({
    required Future<void> Function(String oldKey, String newKey) rekey,
  }) async {
    final oldKey = await _getOrCreateKey();
    final newKey = _generateKey();

    // Preserve a recoverable pending value while the database is rekeyed.
    await _secureStorage.write(key: _dbKeyPendingName, value: newKey);
    await rekey(oldKey, newKey);

    // Only commit key material after the database has confirmed the rekey.
    await _secureStorage.write(key: _dbKeyBackupName, value: newKey);
    await _secureStorage.write(key: _dbKeyName, value: newKey);
    await _secureStorage.delete(key: _dbKeyPendingName);
  }

  /// Clear all database keys (for logout/reset)
  static Future<void> clearKeys() async {
    await _secureStorage.delete(key: _dbKeyName);
    await _secureStorage.delete(key: _dbKeyBackupName);
    await _secureStorage.delete(key: _dbKeyPendingName);
  }

  /// Check if database key exists
  static Future<bool> hasKey() async {
    final key = await _secureStorage.read(key: _dbKeyName);
    return key != null;
  }
}
