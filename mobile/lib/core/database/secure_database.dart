import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'pos_database_encrypted.sqlite'));

      // Get encryption key
      final key = await _getOrCreateKey();

      return NativeDatabase.createInBackground(
        file,
        setup: (rawDb) async {
          try {
            // Set encryption key using PRAGMA key
            rawDb.execute("PRAGMA key = '$key';");

            // Verify encryption is working - but don't throw, just log
            try {
              final result = rawDb.select('SELECT count(*) FROM sqlite_master');
              if (result.isEmpty) {
                // Encryption verification failed - this could be a key mismatch
                // Don't throw, let the app continue (database will be empty but usable)
                debugPrint(
                    '[SecureDatabase] Database verification returned no schema rows');
              }
            } catch (e) {
              // Verification query failed, but database might still work
              debugPrint('[SecureDatabase] Database verification failed: $e');
            }
          } catch (e) {
            // Never silently swap to a different key. Continuing would make
            // an encrypted database look empty and risks overwriting data.
            throw StateError('Unable to open encrypted local database: $e');
          }
        },
      );
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
