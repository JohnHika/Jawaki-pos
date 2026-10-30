import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

Future<void> _configureSqlCipherForDatabaseIsolate() async {
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }
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
  static const List<int> _sqliteFileHeader = [
    0x53,
    0x51,
    0x4c,
    0x69,
    0x74,
    0x65,
    0x20,
    0x66,
    0x6f,
    0x72,
    0x6d,
    0x61,
    0x74,
    0x20,
    0x33,
    0x00,
  ];

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
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'pos_database_encrypted.sqlite'));
      final existingPlaintextDatabase = await _hasPlaintextSqliteHeader(file);

      // Get encryption key
      final key = await _getOrCreateKey();

      return NativeDatabase.createInBackground(
        file,
        isolateSetup: _configureSqlCipherForDatabaseIsolate,
        setup: (rawDb) async {
          final cipherVersion = rawDb.select('PRAGMA cipher_version;');
          if (cipherVersion.isEmpty) {
            throw StateError(
              'SQLCipher is unavailable. The local database was not opened.',
            );
          }

          if (existingPlaintextDatabase) {
            // Earlier builds used regular SQLite, which silently ignored
            // PRAGMA key and left the database readable as plaintext. Rekey
            // that existing file in place before Drift runs any migrations.
            rawDb.execute("PRAGMA rekey = '$key';");
          } else {
            // New databases and already encrypted databases need the key
            // before their first schema read.
            rawDb.execute("PRAGMA key = '$key';");
          }

          try {
            rawDb.select('SELECT count(*) FROM sqlite_master');
          } catch (error) {
            // Never silently swap to a different key. Continuing would make
            // an encrypted database look empty and risks overwriting data.
            throw StateError('Unable to open encrypted local database: $error');
          }
        },
      );
    });
  }

  static Future<bool> _hasPlaintextSqliteHeader(File file) async {
    if (!await file.exists() ||
        await file.length() < _sqliteFileHeader.length) {
      return false;
    }

    final handle = await file.open(mode: FileMode.read);
    try {
      final header = await handle.read(_sqliteFileHeader.length);
      return listEquals(header, _sqliteFileHeader);
    } finally {
      await handle.close();
    }
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
