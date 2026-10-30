import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'auth_service.dart';
import 'storage_service.dart';

class MobilePortableBackupPreview {
  const MobilePortableBackupPreview({
    required this.path,
    required this.tenantName,
    required this.ownerName,
    required this.createdAt,
    required this.counts,
    required this.images,
    required this.bytes,
    required String passphrase,
  }) : _passphrase = passphrase;

  final String path;
  final String tenantName;
  final String ownerName;
  final DateTime createdAt;
  final Map<String, int> counts;
  final int images;
  final int bytes;
  final String _passphrase;

  int get products => counts['products'] ?? 0;
  int get customers => counts['customers'] ?? 0;
  int get sales => counts['sales'] ?? 0;
  int get branches => counts['branches'] ?? 0;
}

/// Password-encrypted transfer for the live mobile SQLCipher workspace.
/// Device credentials and Gateway keys stay on their device; referenced local
/// shop photos travel inside the encrypted database and are path-rebased.
class LocalPortableBackupService {
  LocalPortableBackupService({
    required AppDatabase database,
    required StorageService storage,
    required AuthService auth,
  })  : _database = database,
        _storage = storage,
        _auth = auth;

  static const _maxBackupBytes = 1024 * 1024 * 1024;
  static const _maxPortableImageBytes = 128 * 1024 * 1024;
  static const _maxSingleImageBytes = 16 * 1024 * 1024;

  final AppDatabase _database;
  final StorageService _storage;
  final AuthService _auth;

  Future<File> createBackup({required String passphrase}) async {
    _validatePassphrase(passphrase);
    _requireOwner();
    final user = _storage.getUser();
    final localWorkspace = _storage.getLocalWorkspace();
    final tenantId = _storage.getTenantId()?.trim() ?? '';
    final tenantSlug = _storage.getTenantSlug()?.trim() ?? '';
    final branchId = _storage.getBranchId()?.trim() ?? '';
    if (user == null ||
        localWorkspace == null ||
        tenantId.isEmpty ||
        tenantSlug.isEmpty ||
        branchId.isEmpty) {
      throw StateError(
        'The local shop profile is incomplete. Reopen the shop and try again.',
      );
    }

    final tenant = _asMap(user['tenant']) ?? _asMap(localWorkspace['tenant']);
    final savedBranch = _asMap(localWorkspace['branch']);
    final branches = user['branches'];
    Map<String, dynamic>? activeBranch;
    if (branches is List) {
      for (final value in branches.whereType<Map>()) {
        final candidate = Map<String, dynamic>.from(value);
        if (candidate['id']?.toString() == branchId) {
          activeBranch = candidate;
          break;
        }
      }
    }
    final branch = activeBranch ?? savedBranch;
    if (tenant == null ||
        branch == null ||
        branch['id']?.toString() != branchId) {
      throw StateError(
        'The active shop or branch profile is missing. Reopen the shop and try again.',
      );
    }

    final transferBranches = branches is List
        ? branches
            .whereType<Map>()
            .map((value) => <String, dynamic>{
                  ...Map<String, dynamic>.from(value),
                  'isPrimary': value['id']?.toString() == branchId,
                })
            .toList(growable: false)
        : <Map<String, dynamic>>[_sanitize(branch)];
    final transferUser = <String, dynamic>{
      ...user,
      'tenantId': tenantId,
      'tenantSlug': tenantSlug,
      'branchId': branchId,
      'branchName': branch['name']?.toString() ?? '',
      'tenant': tenant,
      'branches': transferBranches,
    };
    final transferWorkspace = <String, dynamic>{
      ...localWorkspace,
      'tenant': tenant,
      'branch': branch,
      'branches': transferBranches,
      'user': transferUser,
    };

    final heldSales = await _storage.getSecureHeldSalesSnapshot(
      tenantId: tenantId,
      branchId: branchId,
    );
    _requireOwner();
    final metadata = <String, dynamic>{
      'tenantId': tenantId,
      'tenantSlug': tenantSlug,
      'branchId': branchId,
      'tenant': _sanitize(tenant),
      'branch': _sanitize(branch),
      'user': _sanitize(transferUser),
      'workspace': _sanitize(transferWorkspace),
      if (heldSales != null) 'heldSales': heldSales,
      'platform': Platform.operatingSystem,
    };
    final transferImages = await _collectTransferImages(metadata);

    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/Counterbase/transfers');
    await directory.create(recursive: true);
    final now = DateTime.now();
    final stamp = '${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}'
        '-${now.microsecondsSinceEpoch % 1000000}';
    final file = File('${directory.path}/Counterbase-$stamp.cbmobile');
    try {
      _requireOwner();
      await _database.createPortableBackup(
        path: file.path,
        passphrase: passphrase,
        metadata: metadata,
        transferImages: transferImages,
      );
      final length = await file.length();
      if (length < 1024 || length > _maxBackupBytes) {
        throw const FormatException(
          'This shop database is larger than the 1 GB phone-transfer limit.',
        );
      }
      final preview = await _database.inspectPortableBackup(
        path: file.path,
        passphrase: passphrase,
      );
      if ((preview['tenantName']?.toString() ?? '').trim().isEmpty) {
        throw const FormatException(
          'The backup could not verify its shop profile.',
        );
      }
      _requireOwner();
      return file;
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Preserve the useful export error if temporary-file cleanup fails.
      }
      debugPrint('[LocalPortableBackup] Backup creation failed.');
      rethrow;
    }
  }

  Future<void> shareBackup(File file) async {
    if (!await file.exists()) {
      throw const FileSystemException(
          'The backup file is no longer available.');
    }
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Counterbase encrypted shop backup',
      text: 'Keep this encrypted backup and its password in separate places.',
    );
  }

  Future<MobilePortableBackupPreview?> pickAndInspect({
    required Future<String?> Function() requestPassphrase,
  }) async {
    _requireOwner();
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['cbmobile'],
      allowMultiple: false,
      withData: false,
    );
    _requireOwner();
    if (selection == null || selection.files.isEmpty) return null;
    final path = selection.files.single.path;
    if (path == null || path.isEmpty) {
      throw const FileSystemException(
        'Counterbase could not open that file. Save it to this device and try again.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException(
        'That backup is no longer available. Select it again.',
      );
    }
    final bytes = await file.length();
    if (bytes < 1024 || bytes > _maxBackupBytes) {
      throw const FormatException(
        'That backup is empty or larger than the 1 GB phone-transfer limit.',
      );
    }
    final passphrase = await requestPassphrase();
    if (passphrase == null) return null;
    _requireOwner();
    _validatePassphrase(passphrase);
    try {
      final raw = await _database.inspectPortableBackup(
        path: file.path,
        passphrase: passphrase,
      );
      _requireOwner();
      return MobilePortableBackupPreview(
        path: file.path,
        tenantName: raw['tenantName']?.toString() ?? 'Your shop',
        ownerName: raw['ownerName']?.toString() ?? '',
        createdAt: raw['createdAt'] as DateTime,
        counts: Map<String, int>.from(raw['counts'] as Map),
        images: raw['imageCount'] as int? ?? 0,
        bytes: bytes,
        passphrase: passphrase,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      debugPrint('[LocalPortableBackup] Backup inspection failed.');
      throw const FormatException(
        'Counterbase could not open that backup. Check the password and file.',
      );
    }
  }

  Future<void> restoreBackup({
    required MobilePortableBackupPreview preview,
  }) async {
    _requireOwner();
    final archivedImages = await _database.readPortableImageAssets(
      path: preview.path,
      passphrase: preview._passphrase,
    );
    final assetPathRemap = await _installTransferImages(archivedImages);
    _requireOwner();
    await _database.restorePortableBackup(
      path: preview.path,
      passphrase: preview._passphrase,
      storage: _storage,
      assetPathRemap: assetPathRemap,
      validateOwner: _requireOwner,
    );
    await _auth.refreshLocalWorkspaceProfile();
  }

  Future<Map<String, Uint8List?>> _collectTransferImages(
    Map<String, dynamic> metadata,
  ) async {
    final support = await getApplicationSupportDirectory();
    final assetRoots = _transferAssetRoots(support.path);
    final references = <String>{
      ...await _database.getPortableImageReferences(),
    };
    _collectImagePaths(metadata, assetRoots, references);

    final images = <String, Uint8List?>{};
    var totalBytes = 0;
    for (final originalPath in references) {
      if (!_isInsideTransferAssetRoot(originalPath, assetRoots)) continue;
      final file = File(originalPath);
      if (!await file.exists()) {
        images[originalPath] = null;
        continue;
      }
      final length = await file.length();
      if (length > _maxSingleImageBytes) {
        throw const FormatException(
          'A saved shop photo is larger than 16 MB. Choose a smaller image before making the phone backup.',
        );
      }
      totalBytes += length;
      if (totalBytes > _maxPortableImageBytes) {
        throw const FormatException(
          'Shop photos exceed the 128 MB phone-backup limit. Remove unused large photos and try again.',
        );
      }
      images[originalPath] = await file.readAsBytes();
    }
    return images;
  }

  Future<Map<String, String?>> _installTransferImages(
    Map<String, Uint8List?> images,
  ) async {
    if (images.isEmpty) return const <String, String?>{};
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'Counterbase', 'images', 'restored'),
    );
    await directory.create(recursive: true);
    final remap = <String, String?>{};
    for (final entry in images.entries) {
      final contents = entry.value;
      if (contents == null || contents.isEmpty) {
        remap[entry.key] = null;
        continue;
      }
      final extension = p.extension(entry.key).toLowerCase();
      final safeExtension = const {
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.heic',
      }.contains(extension)
          ? extension
          : '.jpg';
      final destination = File(
        p.join(directory.path, '${const Uuid().v4()}$safeExtension'),
      );
      await destination.writeAsBytes(contents, flush: true);
      remap[entry.key] = destination.path;
    }
    return remap;
  }

  List<String> _transferAssetRoots(String supportPath) => [
        p.normalize(p.join(supportPath, 'Counterbase', 'images')),
        p.normalize(p.join(supportPath, 'Counterbase', 'supplier-receipts')),
      ];

  void _collectImagePaths(
    Object? value,
    List<String> assetRoots,
    Set<String> destination,
  ) {
    if (value is String) {
      final path = value.trim();
      if (path.isNotEmpty && _isInsideTransferAssetRoot(path, assetRoots)) {
        destination.add(path);
      }
      return;
    }
    if (value is Map) {
      for (final item in value.values) {
        _collectImagePaths(item, assetRoots, destination);
      }
      return;
    }
    if (value is Iterable) {
      for (final item in value) {
        _collectImagePaths(item, assetRoots, destination);
      }
    }
  }

  bool _isInsideTransferAssetRoot(String value, List<String> assetRoots) {
    if (!p.isAbsolute(value)) return false;
    final normalized = p.normalize(value);
    return assetRoots.any((root) => p.isWithin(root, normalized));
  }

  void _requireOwner() {
    if (!_auth.isAuthenticated || !_auth.isLocalWorkspace) {
      throw StateError('Unlock the local shop before using its backup.');
    }
    if (!_auth.isLocalWorkspaceOwner) {
      throw StateError(
        'Only the saved local shop owner can create or restore a backup.',
      );
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  Map<String, dynamic> _sanitize(Map<String, dynamic> value) => {
        for (final entry in value.entries)
          if (!_isCredentialField(entry.key))
            entry.key: _sanitizeValue(entry.value),
      };

  dynamic _sanitizeValue(dynamic value) {
    if (value is Map) return _sanitize(Map<String, dynamic>.from(value));
    if (value is List) {
      return value.map(_sanitizeValue).toList(growable: false);
    }
    return value;
  }

  bool _isCredentialField(String field) {
    final normalized = field.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('password') ||
        normalized == 'pin' ||
        normalized.contains('pinhash') ||
        normalized.contains('pincredential') ||
        normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('credential') ||
        normalized.contains('authorization') ||
        normalized.contains('apikey');
  }

  void _validatePassphrase(String passphrase) {
    if (passphrase.length < 12 ||
        passphrase.length > 1024 ||
        passphrase.contains('\u0000')) {
      throw const FormatException(
        'Use a backup password between 12 and 1024 characters.',
      );
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
