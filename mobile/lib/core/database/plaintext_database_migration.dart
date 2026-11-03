import 'dart:io';

import 'package:flutter/foundation.dart';

/// Copies the plain SQLite database at [plain] into an encrypted database at
/// [target] using [key]. Must not modify [plain].
typedef PlaintextDatabaseExport = Future<void> Function(
  File plain,
  File target,
  String key,
);

/// Proves that [target] opens with [key] and is readable. Throws if not.
typedef EncryptedDatabaseVerifier = Future<void> Function(
  File target,
  String key,
);

/// Encrypts a database file that older builds left as plain SQLite.
///
/// Before the SQLCipher libraries were really linked, `PRAGMA key` was
/// silently ignored, so installed apps hold a plaintext file under the
/// "encrypted" name. `PRAGMA rekey` cannot encrypt such a file in place
/// (SQLCipher refuses it), so the data is exported into a new encrypted
/// file and the two files are swapped.
///
/// The original is never modified until the new file has been verified.
/// Any failure leaves the original in place and throws.
class PlaintextDatabaseMigration {
  PlaintextDatabaseMigration({
    required this.file,
    required this.key,
    required this.export,
    required this.verify,
  });

  /// The live database file.
  final File file;
  final String key;
  final PlaintextDatabaseExport export;
  final EncryptedDatabaseVerifier verify;

  static const List<int> sqliteFileHeader = [
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, //
    0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
  ];

  File get _staging => File('${file.path}.encrypting');

  /// Plaintext copy of the data kept until the encrypted file has opened
  /// successfully once. See [discardPlaintextBackup].
  File get plaintextBackup => File('${file.path}.plaintext.bak');

  /// True when [file] starts with the standard (unencrypted) SQLite header.
  static Future<bool> hasPlaintextHeader(File file) async {
    if (!await file.exists() ||
        await file.length() < sqliteFileHeader.length) {
      return false;
    }
    final handle = await file.open(mode: FileMode.read);
    try {
      final header = await handle.read(sqliteFileHeader.length);
      return listEquals(header, sqliteFileHeader);
    } finally {
      await handle.close();
    }
  }

  /// Encrypts [file] if it is plaintext. Returns true when a migration ran.
  Future<bool> migrateIfNeeded() async {
    if (!await hasPlaintextHeader(file)) {
      return false;
    }

    final staging = _staging;
    await _deleteWithSidecars(staging);

    try {
      await export(file, staging, key);
      await verify(staging, key);
      if (await hasPlaintextHeader(staging)) {
        throw StateError('The exported database is still unencrypted.');
      }
    } catch (error) {
      await _deleteWithSidecars(staging);
      throw StateError(
        'Could not encrypt the local database. The original data is '
        'untouched. $error',
      );
    }

    // Swap: keep the plaintext original as a backup until the new file has
    // opened once, and undo the swap if the rename fails half way.
    final backup = plaintextBackup;
    await _deleteWithSidecars(backup);
    await file.rename(backup.path);
    try {
      await staging.rename(file.path);
    } catch (_) {
      await backup.rename(file.path);
      await _deleteWithSidecars(staging);
      rethrow;
    }
    // Stale journal files belong to the plaintext original, never the new one.
    await _deleteIfExists(File('${file.path}-wal'));
    await _deleteIfExists(File('${file.path}-shm'));
    await _deleteIfExists(File('${file.path}-journal'));
    return true;
  }

  /// Removes the plaintext backup. Call only after the encrypted database has
  /// been opened and read successfully with its key.
  static void discardPlaintextBackup(File file) {
    final base = '${file.path}.plaintext.bak';
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$base$suffix');
      try {
        if (f.existsSync()) {
          f.deleteSync();
        }
      } on FileSystemException {
        // Best effort: the backup is only a safety copy.
      }
    }
  }

  static Future<void> _deleteWithSidecars(File f) async {
    await _deleteIfExists(f);
    await _deleteIfExists(File('${f.path}-wal'));
    await _deleteIfExists(File('${f.path}-shm'));
    await _deleteIfExists(File('${f.path}-journal'));
  }

  static Future<void> _deleteIfExists(File f) async {
    if (await f.exists()) {
      await f.delete();
    }
  }
}
