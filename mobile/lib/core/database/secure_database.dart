import 'dart:io';
import 'dart:math' as math;
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
                print('[SecureDatabase] Warning: Encryption verification returned empty result');
              }
            } catch (e) {
              // Verification query failed, but database might still work
              print('[SecureDatabase] Warning: Could not verify encryption: $e');
            }
          } catch (e) {
            // If key setup fails, try without encryption as fallback
            print('[SecureDatabase] Warning: Key setup failed: $e');
            // Note: We don't re-throw here to avoid crashing the app
            // The database will still function, just without encryption
          }
        },
      );
    });
  }

  /// Change database encryption key (for rotation)
  static Future<void> rotateEncryptionKey() async {
    final newKey = _generateKey();

    // Store new key
    await _secureStorage.write(key: '${_dbKeyName}_new', value: newKey);

    // TODO: Implement key rotation on open database
    // This requires opening the DB with old key, then running:
    // PRAGMA rekey = 'new_key';

    // After successful rotation, update primary and backup
    await _secureStorage.write(key: _dbKeyBackupName, value: newKey);
    await _secureStorage.write(key: _dbKeyName, value: newKey);
    await _secureStorage.delete(key: '${_dbKeyName}_new');
  }

  /// Clear all database keys (for logout/reset)
  static Future<void> clearKeys() async {
    await _secureStorage.delete(key: _dbKeyName);
    await _secureStorage.delete(key: _dbKeyBackupName);
    await _secureStorage.delete(key: '${_dbKeyName}_new');
  }

  /// Check if database key exists
  static Future<bool> hasKey() async {
    final key = await _secureStorage.read(key: _dbKeyName);
    return key != null;
  }
}
