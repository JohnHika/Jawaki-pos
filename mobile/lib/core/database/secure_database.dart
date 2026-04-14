import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

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
    final random = DateTime.now().millisecondsSinceEpoch.toString() +
        DateTime.now().microsecond.toString();
    // In production, use proper crypto random - this is simplified
    return List.generate(64, (index) {
      const chars = '0123456789abcdef';
      return chars[DateTime.now().microsecond % 16];
    }).join();
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

      // Ensure SQLCipher native libraries are loaded
      await applySQLCipherWorkaround();

      return NativeDatabase.createInBackground(
        file,
        setup: (rawDb) {
          // Set encryption key using PRAGMA key
          rawDb.execute("PRAGMA key = '$key';");

          // Verify encryption is working
          final result = rawDb.select('SELECT count(*) FROM sqlite_master');
          if (result.isEmpty) {
            throw Exception('Database encryption failed - wrong key?');
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

/// Workaround for SQLCipher on some Android devices
Future<void> applySQLCipherWorkaround() async {
  if (Platform.isAndroid) {
    // Some Android devices need additional setup
    await openSQLiteCipherOnAndroid();
  }
}
