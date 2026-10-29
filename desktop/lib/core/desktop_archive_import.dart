import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';

import 'desktop_workspace.dart';

class DesktopArchivePreview {
  const DesktopArchivePreview({
    required this.archiveId,
    required this.createdAt,
    required this.tenant,
    required this.payload,
    required this.counts,
  });

  final String archiveId;
  final DateTime createdAt;
  final Map<String, dynamic> tenant;
  final Map<String, dynamic> payload;
  final Map<String, int> counts;

  String get tenantName => tenant['name']?.toString() ?? 'Shop';
  int get products => counts['products'] ?? 0;
  int get customers => counts['customers'] ?? 0;
  int get sales => counts['sales'] ?? 0;
  int get branches => counts['branches'] ?? 0;
  int get totalRecords => counts.values.fold(0, (sum, count) => sum + count);
}

class DesktopArchiveImportService {
  static const _maxBytes = 64 * 1024 * 1024;
  static const _maxRecords = 250000;

  Future<DesktopArchivePreview?> pickArchive({
    required Future<String?> Function() requestPassphrase,
  }) async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a Counterbase shop archive',
      type: FileType.custom,
      allowedExtensions: const ['cbarchive'],
    );
    if (file == null) return null;
    final length = await file.length();
    if (length == null) {
      throw const LocalWorkspaceFailure(
        'Counterbase could not read that archive. Copy it to this computer and try again.',
      );
    }
    if (length > _maxBytes) {
      throw const LocalWorkspaceFailure(
        'That archive is larger than 64 MB. Prepare a single shop archive and try again.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const LocalWorkspaceFailure(
        'Counterbase could not read that archive. Copy it to this computer and try again.',
      );
    }
    if (bytes.length > _maxBytes) {
      throw const LocalWorkspaceFailure(
        'That archive is larger than 64 MB. Prepare a single shop archive and try again.',
      );
    }

    final passphrase = await requestPassphrase();
    if (passphrase == null) return null;
    return previewBytes(bytes, passphrase: passphrase);
  }

  Future<DesktopArchivePreview> previewBytes(
    List<int> bytes, {
    required String passphrase,
  }) async {
    try {
      final envelope = jsonDecode(utf8.decode(bytes));
      if (envelope is! Map<String, dynamic> ||
          envelope['format'] != 'counterbase-local-archive' ||
          envelope['version'] != 2 ||
          envelope['encryption'] != 'AES-256-GCM' ||
          envelope['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          envelope['iterations'] != 310000) {
        throw const LocalWorkspaceFailure(
          'This is not a supported password-protected Counterbase archive.',
        );
      }
      if (passphrase.length < 12) {
        throw const LocalWorkspaceFailure(
          'Enter the archive password with at least 12 characters.',
        );
      }
      final createdAtText = envelope['createdAt']?.toString() ?? '';
      final createdAt = DateTime.tryParse(createdAtText);
      if (createdAt == null) {
        throw const LocalWorkspaceFailure(
          'The archive creation date is invalid.',
        );
      }
      final saltText = envelope['salt']?.toString() ?? '';
      final nonceText = envelope['nonce']?.toString() ?? '';
      final salt = _decodeArchiveBytes(saltText, 16, 'salt');
      final nonce = _decodeArchiveBytes(nonceText, 12, 'nonce');
      final tag = _decodeArchiveBytes(
        envelope['tag']?.toString() ?? '',
        16,
        'authentication tag',
      );
      final ciphertext = _decodeArchiveBytes(
        envelope['ciphertext']?.toString() ?? '',
        null,
        'encrypted data',
      );
      if (ciphertext.isEmpty) {
        throw const LocalWorkspaceFailure(
          'The archive does not contain shop data.',
        );
      }
      final secretKey = await Pbkdf2.hmacSha256(
        iterations: 310000,
        bits: 256,
      ).deriveKeyFromPassword(password: passphrase, nonce: salt);
      final plaintext = await AesGcm.with256bits().decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: secretKey,
        aad: utf8.encode(
          'counterbase-local-archive:v2:$createdAtText:$saltText:$nonceText:310000',
        ),
      );
      const maxPlaintextBytes = 45 * 1024 * 1024;
      if (plaintext.length > maxPlaintextBytes) {
        throw const LocalWorkspaceFailure(
          'This archive exceeds the safe restore size. Prepare one smaller shop archive.',
        );
      }
      final payloadText = utf8.decode(plaintext);
      final digest = sha256.convert(plaintext).toString();
      final payloadValue = jsonDecode(payloadText);
      if (payloadValue is! Map<String, dynamic> ||
          payloadValue['tenant'] is! Map<String, dynamic>) {
        throw const LocalWorkspaceFailure(
          'The archive does not identify a shop.',
        );
      }
      final tenant = Map<String, dynamic>.from(payloadValue['tenant'] as Map);
      if (_text(tenant['id']).isEmpty || _text(tenant['name']).isEmpty) {
        throw const LocalWorkspaceFailure(
          'The archive shop identity is incomplete.',
        );
      }
      final counts = <String, int>{};
      var total = 0;
      for (final entry in payloadValue.entries) {
        if (entry.key == 'tenant') continue;
        if (entry.value is! List ||
            (entry.value as List).any((row) => row is! Map)) {
          throw LocalWorkspaceFailure(
            'The ${entry.key} section is incomplete.',
          );
        }
        final count = (entry.value as List).length;
        counts[entry.key] = count;
        total += count;
      }
      if (total > _maxRecords || (counts['branches'] ?? 0) == 0) {
        throw const LocalWorkspaceFailure(
          'The archive is too large or does not contain a shop branch.',
        );
      }
      return DesktopArchivePreview(
        archiveId: digest,
        createdAt: createdAt,
        tenant: tenant,
        payload: payloadValue,
        counts: counts,
      );
    } on LocalWorkspaceFailure {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const LocalWorkspaceFailure(
        'That archive password is incorrect, or the file has been changed.',
      );
    } on FormatException {
      throw const LocalWorkspaceFailure(
        'Counterbase could not read that archive. Prepare a fresh copy and try again.',
      );
    } catch (_) {
      throw const LocalWorkspaceFailure(
        'Counterbase could not validate that archive.',
      );
    }
  }

  static List<int> _decodeArchiveBytes(
    String encoded,
    int? expectedLength,
    String label,
  ) {
    final bytes = base64.decode(encoded);
    if (expectedLength != null && bytes.length != expectedLength) {
      throw LocalWorkspaceFailure('The archive $label has an invalid length.');
    }
    return bytes;
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';
}
