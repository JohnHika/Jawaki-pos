import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'auth_service.dart';
import 'storage_service.dart';

class LocalArchiveImportException implements Exception {
  const LocalArchiveImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocalArchiveImportPreview {
  const LocalArchiveImportPreview({
    required this.archiveId,
    required this.tenantId,
    required this.tenantName,
    required this.createdAt,
    required this.ownerUserId,
    required this.activeWorkspaceTenantId,
    required this.workspaceMatches,
    required this.counts,
    required this.payload,
  });

  final String archiveId;
  final String tenantId;
  final String tenantName;
  final DateTime createdAt;
  final String ownerUserId;
  final String activeWorkspaceTenantId;
  final bool workspaceMatches;
  final Map<String, int> counts;
  final Map<String, dynamic> payload;

  int get productCount => counts['products'] ?? 0;
  int get saleCount => counts['sales'] ?? 0;
  int get customerCount => counts['customers'] ?? 0;
  int get branchCount => counts['branches'] ?? 0;
  int get supplierCount => counts['suppliers'] ?? 0;
  int get supplierInvoiceCount => counts['supplierInvoices'] ?? 0;
  int get customerCreditEntryCount => counts['retailReceivables'] ?? 0;
  int get customerCollectionCount => counts['retailReceivablePayments'] ?? 0;
  int get customerInstallmentCount => counts['customerInstallments'] ?? 0;
  int get customerBalanceCount {
    final customerRows = payload['customers'];
    if (customerRows is! List) return 0;

    final receivableCustomers = <String>{};
    final openBalances = <String, double>{};
    final receivableRows = payload['retailReceivables'];
    if (receivableRows is List) {
      for (final value in receivableRows.whereType<Map>()) {
        final customerId = value['customerId']?.toString() ?? '';
        if (customerId.isEmpty) continue;
        receivableCustomers.add(customerId);
        final status = value['status']?.toString().toUpperCase() ?? '';
        final outstanding = _previewNumber(value['outstandingAmount']);
        if (outstanding > 0.005 &&
            status != 'PAID' &&
            status != 'CANCELLED' &&
            status != 'VOIDED') {
          openBalances.update(
            customerId,
            (current) => current + outstanding,
            ifAbsent: () => outstanding,
          );
        }
      }
    }

    return customerRows.whereType<Map>().where((row) {
      final customerId = row['id']?.toString() ?? '';
      final balance = receivableCustomers.contains(customerId)
          ? openBalances[customerId] ?? 0
          : _previewNumber(row['balance']);
      return balance > 0.005;
    }).length;
  }

  int get totalCount => counts.values.fold(0, (sum, count) => sum + count);

  /// Archive sections preserved inside the encrypted import record but not
  /// currently mapped to active local app screens.
  Map<String, int> get preservedOnlyCounts => Map.unmodifiable({
        for (final entry in counts.entries)
          if (entry.value > 0 && !_restoredSectionKeys.contains(entry.key))
            entry.key: entry.value,
      });

  List<String> get preservedOnlyDescriptions =>
      preservedOnlyCounts.entries.map((entry) {
        final label = preservedSectionLabels[entry.key] ??
            entry.key.replaceAllMapped(
              RegExp(r'([a-z0-9])([A-Z])'),
              (match) => '${match[1]} ${match[2]}',
            );
        return '$label (${entry.value})';
      }).toList(growable: false);

  static const _restoredSectionKeys = <String>{
    'branches',
    'categories',
    'products',
    'productCategories',
    'pricingTiers',
    'customers',
    'suppliers',
    'supplierInvoices',
    'supplierInvoiceItems',
    'supplierPayments',
    'sales',
    'saleItems',
    'payments',
    'stock',
    'retailReceivablePayments',
    'customerInstallments',
  };

  static const preservedSectionLabels = <String, String>{
    'users': 'Staff profiles',
    'userBranches': 'Staff branch assignments',
    'saleItemBatches': 'Sale batch links',
    'stockBatches': 'Inventory batches',
    'stockMovements': 'Stock movement history',
    'stockCounts': 'Stock count sessions',
    'stockCountItems': 'Stock count lines',
    'cashLedgerEntries': 'Cash ledger history',
    'cashReconciliations': 'Cash reconciliation history',
    'dailyCloses': 'End-of-day close history',
    'retailReceivables':
        'Original customer credit entries (open balances carry to customer balances)',
  };
}

double _previewNumber(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return parsed != null && parsed.isFinite ? parsed : 0;
}

class LocalArchiveImportResult {
  const LocalArchiveImportResult({
    required this.alreadyImported,
    required this.recordCount,
    required this.tenantName,
  });

  final bool alreadyImported;
  final int recordCount;
  final String tenantName;
}

class LocalArchiveHistorySummary {
  const LocalArchiveHistorySummary({
    required this.archiveId,
    required this.tenantName,
    required this.importedAt,
  });

  final String archiveId;
  final String tenantName;
  final DateTime importedAt;
}

class LocalArchiveHistorySection {
  const LocalArchiveHistorySection({
    required this.key,
    required this.label,
    required this.rows,
  });

  final String key;
  final String label;
  final List<Map<String, dynamic>> rows;
}

class LocalArchiveHistoryDetail {
  const LocalArchiveHistoryDetail({
    required this.summary,
    required this.sections,
  });

  final LocalArchiveHistorySummary summary;
  final List<LocalArchiveHistorySection> sections;
}

/// Imports a sanitized, single-shop archive prepared from the owner's local
/// JSON export. The archive is validated before one all-or-nothing transaction
/// writes it into the already-encrypted Drift database.
class LocalArchiveImportService {
  LocalArchiveImportService({
    required AppDatabase database,
    required StorageService storage,
    required AuthService auth,
  })  : _database = database,
        _storage = storage,
        _auth = auth;

  static const _maxArchiveBytes = 64 * 1024 * 1024;
  static const _maxRecords = 250000;

  final AppDatabase _database;
  final StorageService _storage;
  final AuthService _auth;

  String _requireArchiveOwnerTenantId() {
    if (!_auth.isLocalWorkspace ||
        !_auth.isAuthenticated ||
        !_auth.isLocalWorkspaceOwner) {
      throw const LocalArchiveImportException(
        'Unlock the local shop owner account to view imported archive history.',
      );
    }
    final tenantId = _storage.getTenantId()?.trim();
    if (tenantId == null || tenantId.isEmpty) {
      throw const LocalArchiveImportException(
        'The active shop could not be identified. Unlock it and try again.',
      );
    }
    return tenantId;
  }

  Future<List<LocalArchiveHistorySummary>> listPreservedHistory() async {
    final tenantId = _requireArchiveOwnerTenantId();
    final table = await _database.customSelect('''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'local_import_archives'
      LIMIT 1
    ''').getSingleOrNull();
    if (table == null) return const [];

    final rows = await _database.customSelect(
      'SELECT archive_id, tenant_name, imported_at '
      'FROM local_import_archives WHERE tenant_id = ? ORDER BY imported_at DESC',
      variables: [Variable.withString(tenantId)],
    ).get();
    return rows.map((row) {
      final importedAt = DateTime.tryParse(row.read<String>('imported_at'));
      if (importedAt == null) {
        throw const LocalArchiveImportException(
          'An imported archive record has an invalid date. Restore the original archive again.',
        );
      }
      return LocalArchiveHistorySummary(
        archiveId: row.read<String>('archive_id'),
        tenantName: row.read<String>('tenant_name'),
        importedAt: importedAt,
      );
    }).toList(growable: false);
  }

  Future<LocalArchiveHistoryDetail> loadPreservedHistory(
    String archiveId,
  ) async {
    final tenantId = _requireArchiveOwnerTenantId();
    final row = await _database.customSelect(
      'SELECT archive_id, tenant_name, imported_at, payload_json '
      'FROM local_import_archives WHERE archive_id = ? AND tenant_id = ? LIMIT 1',
      variables: [
        Variable.withString(archiveId),
        Variable.withString(tenantId),
      ],
    ).getSingleOrNull();
    if (row == null) {
      throw const LocalArchiveImportException(
        'That archive is not available in the current shop workspace.',
      );
    }
    final importedAt = DateTime.tryParse(row.read<String>('imported_at'));
    if (importedAt == null) {
      throw const LocalArchiveImportException(
        'This archive record has an invalid import date.',
      );
    }
    final summary = LocalArchiveHistorySummary(
      archiveId: row.read<String>('archive_id'),
      tenantName: row.read<String>('tenant_name'),
      importedAt: importedAt,
    );
    final data = await compute(
      _decodePreservedArchiveSections,
      row.read<String>('payload_json'),
    );
    final sections = <LocalArchiveHistorySection>[];
    for (final entry
        in LocalArchiveImportPreview.preservedSectionLabels.entries) {
      final rows = data[entry.key];
      if (rows == null || rows.isEmpty) continue;
      sections.add(LocalArchiveHistorySection(
        key: entry.key,
        label: entry.value,
        rows: rows,
      ));
    }
    return LocalArchiveHistoryDetail(
      summary: summary,
      sections: sections,
    );
  }

  static Map<String, List<Map<String, dynamic>>>
      _decodePreservedArchiveSections(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map<String, dynamic>) {
      throw const LocalArchiveImportException(
        'The imported archive history is damaged. Keep the original archive and contact support.',
      );
    }
    final productNames = <String, String>{};
    for (final product in _archiveRecordList(decoded['products'])) {
      final id = product['id']?.toString() ?? '';
      final name = product['name']?.toString().trim() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) productNames[id] = name;
    }
    final productIdsByStockId = <String, String>{};
    for (final stock in _archiveRecordList(decoded['stock'])) {
      final stockId = stock['id']?.toString() ?? '';
      final productId = stock['productId']?.toString() ?? '';
      if (stockId.isNotEmpty && productId.isNotEmpty) {
        productIdsByStockId[stockId] = productId;
      }
    }
    final userNames = <String, String>{};
    for (final user in _archiveRecordList(decoded['users'])) {
      final id = user['id']?.toString() ?? '';
      final name = [user['firstName'], user['lastName']]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(' ');
      if (id.isNotEmpty && name.isNotEmpty) userNames[id] = name;
    }
    final branchNames = <String, String>{};
    for (final branch in _archiveRecordList(decoded['branches'])) {
      final id = branch['id']?.toString() ?? '';
      final name = branch['name']?.toString().trim() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) branchNames[id] = name;
    }
    final customerNames = <String, String>{};
    for (final customer in _archiveRecordList(decoded['customers'])) {
      final id = customer['id']?.toString() ?? '';
      final name = customer['name']?.toString().trim() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) customerNames[id] = name;
    }
    final sections = <String, List<Map<String, dynamic>>>{};
    for (final key in LocalArchiveImportPreview.preservedSectionLabels.keys) {
      final value = decoded[key];
      if (value is! List) continue;
      sections[key] = value
          .whereType<Map>()
          .map((record) => Map<String, dynamic>.from(record))
          .toList(growable: false);
    }
    for (final row in sections['stockBatches'] ?? const []) {
      final stockId = row['stockId']?.toString() ?? '';
      final productId = productIdsByStockId[stockId];
      final productName = productId == null ? null : productNames[productId];
      if (productName != null) row['productName'] = productName;
    }
    for (final row in sections['stockMovements'] ?? const []) {
      final productId = row['productId']?.toString() ?? '';
      final productName = productNames[productId];
      if (productName != null) row['productName'] = productName;
    }
    for (final row in sections['users'] ?? const []) {
      final id = row['id']?.toString() ?? '';
      final name = userNames[id];
      if (name != null) row['name'] = name;
    }
    for (final row in sections['userBranches'] ?? const []) {
      final userId = row['userId']?.toString() ?? '';
      final branchId = row['branchId']?.toString() ?? '';
      final userName = userNames[userId];
      final branchName = branchNames[branchId];
      if (userName != null) row['userName'] = userName;
      if (branchName != null) row['branchName'] = branchName;
    }
    for (final row in sections['retailReceivables'] ?? const []) {
      final customerId = row['customerId']?.toString() ?? '';
      final branchId = row['branchId']?.toString() ?? '';
      final customerName = customerNames[customerId];
      final branchName = branchNames[branchId];
      if (customerName != null) row['customerName'] = customerName;
      if (branchName != null) row['branchName'] = branchName;
    }
    return sections;
  }

  Future<LocalArchiveImportPreview?> pickArchive({
    required Future<String?> Function() requestPassphrase,
  }) async {
    _requireArchiveOwnerTenantId();
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['cbarchive'],
      allowMultiple: false,
      withData: true,
    );
    if (selected == null || selected.files.isEmpty) return null;
    final file = selected.files.single;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) {
      throw const LocalArchiveImportException(
        'Counterbase could not read that archive. Copy it to this device and try again.',
      );
    }
    if (bytes.length > _maxArchiveBytes) {
      throw const LocalArchiveImportException(
        'That archive is larger than 64 MB. Prepare a single shop archive and try again.',
      );
    }
    final passphrase = await requestPassphrase();
    if (passphrase == null) return null;
    return previewBytes(bytes, passphrase: passphrase);
  }

  Future<LocalArchiveImportPreview> previewBytes(
    Uint8List bytes, {
    required String passphrase,
  }) async {
    _requireArchiveOwnerTenantId();
    if (bytes.length > _maxArchiveBytes) {
      throw const LocalArchiveImportException(
        'That archive is larger than 64 MB.',
      );
    }

    try {
      final envelope = jsonDecode(utf8.decode(bytes));
      if (envelope is! Map<String, dynamic> ||
          envelope['format'] != 'counterbase-local-archive' ||
          envelope['version'] != 2 ||
          envelope['encryption'] != 'AES-256-GCM' ||
          envelope['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          envelope['iterations'] != 310000) {
        throw const LocalArchiveImportException(
          'This is not a supported password-protected Counterbase archive.',
        );
      }

      if (passphrase.length < 12) {
        throw const LocalArchiveImportException(
          'Enter the archive password with at least 12 characters.',
        );
      }
      final createdAtText = envelope['createdAt']?.toString() ?? '';
      final createdAt = DateTime.tryParse(createdAtText);
      if (createdAt == null) {
        throw const LocalArchiveImportException(
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
        throw const LocalArchiveImportException(
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
        throw const LocalArchiveImportException(
          'This archive exceeds the safe restore size. Prepare one smaller shop archive.',
        );
      }
      final payloadText = utf8.decode(plaintext);
      final actualHash = sha256.convert(plaintext).toString();

      final decoded = jsonDecode(payloadText);
      if (decoded is! Map<String, dynamic>) {
        throw const LocalArchiveImportException(
          'The archive data is incomplete or unreadable.',
        );
      }
      final tenant = decoded['tenant'];
      if (tenant is! Map<String, dynamic>) {
        throw const LocalArchiveImportException(
          'The archive does not identify a shop.',
        );
      }
      final tenantId = _requiredString(tenant['id'], 'shop id');
      if (!_auth.isLocalWorkspace ||
          !_auth.isAuthenticated ||
          !_auth.isLocalWorkspaceOwner) {
        throw const LocalArchiveImportException(
          'Unlock the device-only shop owner account before restoring its archive.',
        );
      }
      final workspaceMatches = _storage.getTenantId()?.trim() == tenantId;

      final counts = <String, int>{};
      var total = 0;
      for (final entry in decoded.entries) {
        if (entry.key == 'tenant') continue;
        if (entry.value is! List) {
          throw LocalArchiveImportException(
            'The ${entry.key} section is incomplete.',
          );
        }
        final rows = entry.value as List;
        if (rows.any((row) => row is! Map)) {
          throw LocalArchiveImportException(
            'The ${entry.key} section contains an invalid record.',
          );
        }
        counts[entry.key] = rows.length;
        total += rows.length;
      }
      if (total > _maxRecords) {
        throw const LocalArchiveImportException(
          'That archive contains too many records for a safe device restore.',
        );
      }
      if ((counts['branches'] ?? 0) == 0) {
        throw const LocalArchiveImportException(
          'This archive has no shop branches to restore.',
        );
      }

      return LocalArchiveImportPreview(
        archiveId: actualHash,
        tenantId: tenantId,
        tenantName: _requiredString(tenant['name'], 'shop name'),
        createdAt: createdAt,
        ownerUserId: _auth.userId ?? '',
        activeWorkspaceTenantId: _storage.getTenantId()?.trim() ?? '',
        workspaceMatches: workspaceMatches,
        counts: counts,
        payload: decoded,
      );
    } on LocalArchiveImportException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const LocalArchiveImportException(
        'That archive password is incorrect, or the file has been changed.',
      );
    } on FormatException {
      throw const LocalArchiveImportException(
        'Counterbase could not read that archive. Prepare a fresh copy and try again.',
      );
    } catch (error) {
      debugPrint('[LocalArchive] archive preview failed: $error');
      throw const LocalArchiveImportException(
        'Counterbase could not validate that archive.',
      );
    }
  }

  Future<LocalArchiveImportResult> importArchive(
    LocalArchiveImportPreview preview,
  ) async {
    _requirePreviewOwner(preview);

    await _database.customStatement('''
      CREATE TABLE IF NOT EXISTS local_import_archives (
        archive_id TEXT PRIMARY KEY NOT NULL,
        tenant_id TEXT NOT NULL,
        tenant_name TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        payload_json TEXT NOT NULL
      )
    ''');
    final alreadyImported = await _database.customSelect(
      'SELECT archive_id, tenant_id FROM local_import_archives WHERE archive_id = ? LIMIT 1',
      variables: [Variable.withString(preview.archiveId)],
    ).getSingleOrNull();
    if (alreadyImported != null) {
      if (alreadyImported.read<String>('tenant_id') != preview.tenantId) {
        throw const LocalArchiveImportException(
          'The archive identity does not match the copy already stored on this device.',
        );
      }
      final archiveBranches = _maps(preview.payload['branches']);
      final branchProfile = archiveBranches.map((row) {
        final id = row['id'].toString();
        return <String, dynamic>{
          'id': id,
          'name': _string(row['name'], 'Main branch'),
          'code': _string(row['code'], ''),
          'location': _string(row['address'], ''),
          'phone': _string(row['phone'], ''),
          'isActive': _bool(row['isActive'], defaultValue: true),
          'isPrimary': id == _storage.getBranchId(),
          'createdAt':
              _date(row['createdAt'], DateTime.now().toUtc()).toIso8601String(),
        };
      }).toList(growable: false);
      if (preview.workspaceMatches) {
        await _auth.updateLocalWorkspaceBranches(branchProfile);
      } else {
        final activeBranchId = _selectPrimaryBranch(preview.payload);
        for (final branch in branchProfile) {
          branch['isPrimary'] = branch['id']?.toString() == activeBranchId;
        }
        await _auth.adoptLocalArchiveIdentity(
          tenantId: preview.tenantId,
          tenantName: preview.tenantName,
          tenantSlug: _tenantSlug(preview.payload['tenant'] as Map),
          activeBranchId: activeBranchId,
          branches: branchProfile,
        );
      }
      return LocalArchiveImportResult(
        alreadyImported: true,
        recordCount: preview.totalCount,
        tenantName: preview.tenantName,
      );
    }

    final rows = preview.payload;
    final branches = _maps(rows['branches']);
    final currentBranchId = _storage.getBranchId()?.trim();
    if (preview.workspaceMatches &&
        (currentBranchId == null ||
            !branches.any(
                (branch) => branch['id']?.toString() == currentBranchId))) {
      throw const LocalArchiveImportException(
        'The archive does not contain this device’s active shop branch.',
      );
    }
    if (!preview.workspaceMatches && !await _localWorkspaceIsEmpty()) {
      throw const LocalArchiveImportException(
        'This archive belongs to a different shop, and this device already has business data. Restore it on a new, empty local workspace.',
      );
    }
    final activeBranchId = preview.workspaceMatches
        ? currentBranchId!
        : _selectPrimaryBranch(rows);
    final categories = _maps(rows['categories']);
    final products = _maps(rows['products']);
    final productCategories = _maps(rows['productCategories']);
    final pricingTiers = _maps(rows['pricingTiers']);
    final customers = _maps(rows['customers']);
    final sales = _maps(rows['sales']);
    final saleItems = _maps(rows['saleItems']);
    final payments = _maps(rows['payments']);
    final stock = _maps(rows['stock']);
    final receivables = _maps(rows['retailReceivables']);
    final receivablePayments = _maps(rows['retailReceivablePayments']);
    final customerInstallments = _maps(rows['customerInstallments']);
    final suppliers = _maps(rows['suppliers']);
    final supplierInvoices = _maps(rows['supplierInvoices']);
    final supplierInvoiceItems = _maps(rows['supplierInvoiceItems']);
    final supplierPayments = _maps(rows['supplierPayments']);

    _validateReferences(
      branches: branches,
      categories: categories,
      products: products,
      productCategories: productCategories,
      pricingTiers: pricingTiers,
      customers: customers,
      sales: sales,
      saleItems: saleItems,
      payments: payments,
      stock: stock,
      receivables: receivables,
      receivablePayments: receivablePayments,
      customerInstallments: customerInstallments,
      suppliers: suppliers,
      supplierInvoices: supplierInvoices,
      supplierInvoiceItems: supplierInvoiceItems,
      supplierPayments: supplierPayments,
    );

    final tenantId = preview.tenantId;
    final now = DateTime.now().toUtc();
    final categoryIds = categories
        .map((row) => _requiredString(row['id'], 'category id'))
        .toSet();
    final categoryForProduct = <String, String>{};
    for (final relation in productCategories) {
      final productId = relation['productId']?.toString() ?? '';
      final categoryId = relation['categoryId']?.toString() ?? '';
      if (productId.isNotEmpty &&
          categoryIds.contains(categoryId) &&
          !categoryForProduct.containsKey(productId)) {
        categoryForProduct[productId] = categoryId;
      }
    }
    const defaultCategoryId = 'local-default-category';
    final customerIds = customers.map((row) => row['id'].toString()).toSet();
    final outstandingByCustomer = <String, double>{};
    final receivableCustomerIds = <String>{};
    for (final row in receivables) {
      final customerId = row['customerId']?.toString() ?? '';
      if (customerIds.contains(customerId)) {
        receivableCustomerIds.add(customerId);
      }
      final outstanding = _number(row['outstandingAmount']);
      final status = row['status']?.toString().toUpperCase() ?? '';
      if (customerIds.contains(customerId) &&
          outstanding > 0 &&
          status != 'PAID' &&
          status != 'CANCELLED' &&
          status != 'VOIDED') {
        outstandingByCustomer.update(
          customerId,
          (amount) => amount + outstanding,
          ifAbsent: () => outstanding,
        );
      }
    }
    // Older online archives carry explicit receivable rows. Local-first
    // archives instead carry the customer's current balance directly. Prefer
    // explicit rows when present so a stale cached balance cannot be counted
    // again, and use the balance field only for customers without those rows.
    for (final row in customers) {
      final customerId = row['id']?.toString() ?? '';
      if (customerId.isNotEmpty &&
          !receivableCustomerIds.contains(customerId) &&
          _number(row['balance']) > 0.005) {
        outstandingByCustomer[customerId] = _number(row['balance']);
      }
    }
    final completedSalesByCustomer = <String, List<Map<String, dynamic>>>{};
    for (final row in sales) {
      final customerId = row['customerId']?.toString() ?? '';
      if (customerIds.contains(customerId) &&
          (row['status']?.toString().toUpperCase() ?? '') == 'COMPLETED') {
        completedSalesByCustomer.putIfAbsent(customerId, () => []).add(row);
      }
    }
    final paymentsBySale = <String, List<Map<String, dynamic>>>{};
    for (final row in payments) {
      paymentsBySale
          .putIfAbsent(row['saleId']?.toString() ?? '', () => [])
          .add(row);
    }

    await _database.transaction(() async {
      _requirePreviewOwner(preview);
      await _database.createBranchesTable();
      await _database.createCustomersTable();
      await _database.ensureLocalDefaultCategory();
      if (suppliers.isNotEmpty ||
          supplierInvoices.isNotEmpty ||
          supplierInvoiceItems.isNotEmpty ||
          supplierPayments.isNotEmpty) {
        await _database.ensureLocalSupplierFinanceSchema();
      }
      if (receivablePayments.isNotEmpty) {
        await _database.ensureLocalCashCollectionsSchema();
      }
      if (customerInstallments.isNotEmpty) {
        await _database.createCustomerInstallmentsTable();
      }

      for (final row in branches) {
        final id = _requiredString(row['id'], 'branch id');
        final name = _string(row['name'], 'Main branch');
        final location = _string(row['address'], '');
        final phone = _nullableString(row['phone']);
        final isActive = _bool(row['isActive']) ? 1 : 0;
        final createdAt = _date(row['createdAt'], now).toIso8601String();
        final replacesStarterBranch =
            !preview.workspaceMatches && id == 'local-main';
        await _database.customInsert(
          replacesStarterBranch
              ? 'INSERT INTO branches '
                  '(id, name, location, phone, is_active, created_at) '
                  'VALUES (?, ?, ?, ?, ?, ?) '
                  'ON CONFLICT(id) DO UPDATE SET '
                  'name = excluded.name, location = excluded.location, '
                  'phone = excluded.phone, is_active = excluded.is_active, '
                  'created_at = excluded.created_at'
              : 'INSERT OR IGNORE INTO branches '
                  '(id, name, location, phone, is_active, created_at) '
                  'VALUES (?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(id),
            Variable.withString(name),
            Variable.withString(location),
            phone == null
                ? const Variable<String>(null)
                : Variable.withString(phone),
            Variable.withInt(isActive),
            Variable.withString(createdAt),
          ],
        );
      }
      if (!preview.workspaceMatches &&
          currentBranchId != null &&
          !branches.any(
            (branch) => branch['id']?.toString() == currentBranchId,
          )) {
        await _database.customStatement(
          'DELETE FROM branches WHERE id = ?',
          [currentBranchId],
        );
      }

      final categoryCompanions = categories
          .map((row) => CategoriesCompanion.insert(
                id: _requiredString(row['id'], 'category id'),
                name: _requiredString(row['name'], 'category name'),
                description: Value(_nullableString(row['description'])),
                parentId: Value(_nullableString(row['parentId'])),
                imageUrl: const Value(null),
                sortOrder: Value(_integer(row['sortOrder'])),
                isActive: Value(_bool(row['isActive'], defaultValue: true)),
                createdAt: _date(row['createdAt'], now),
                updatedAt: _date(row['updatedAt'], now),
              ))
          .toList();
      if (categoryCompanions.isNotEmpty) {
        await _database.batch((batch) => batch.insertAll(
              _database.categories,
              categoryCompanions,
              mode: InsertMode.insertOrIgnore,
            ));
      }
      if (!preview.workspaceMatches) {
        // A fresh local workspace includes a starter category. If an archive
        // uses that reserved ID, keep the archive's category label and rules
        // rather than silently attaching restored products to the starter.
        for (final row in categories) {
          if (row['id']?.toString() != defaultCategoryId) continue;
          await _database.customStatement(
            'UPDATE categories SET name = ?, description = ?, parent_id = ?, '
            'image_url = NULL, sort_order = ?, is_active = ?, '
            'created_at = ?, updated_at = ? WHERE id = ?',
            [
              Variable.withString(
                  _requiredString(row['name'], 'category name')),
              _nullableString(row['description']) == null
                  ? const Variable<String>(null)
                  : Variable.withString(_nullableString(row['description'])!),
              _nullableString(row['parentId']) == null
                  ? const Variable<String>(null)
                  : Variable.withString(_nullableString(row['parentId'])!),
              Variable.withInt(_integer(row['sortOrder'])),
              Variable.withInt(
                  _bool(row['isActive'], defaultValue: true) ? 1 : 0),
              Variable.withString(
                  _date(row['createdAt'], now).toIso8601String()),
              Variable.withString(
                  _date(row['updatedAt'], now).toIso8601String()),
              Variable.withString(defaultCategoryId),
            ],
          );
        }
      }

      final productCompanions = products.map((row) {
        final metadata = row['metadata'];
        return ProductsCompanion.insert(
          id: _requiredString(row['id'], 'product id'),
          sku: _string(row['sku'], row['id'].toString()),
          name: _requiredString(row['name'], 'product name'),
          description: Value(_nullableString(row['description'])),
          metadata: Value(metadata is Map ? jsonEncode(metadata) : '{}'),
          categoryId:
              categoryForProduct[row['id']?.toString()] ?? defaultCategoryId,
          price: _number(row['basePrice']),
          costPrice: Value(_optionalNumber(row['costPrice'])),
          unit: Value(_string(row['unit'], 'piece')),
          imageUrl: const Value(null),
          isActive: Value(_bool(row['isActive'], defaultValue: true)),
          trackInventory:
              Value(_bool(row['trackInventory'], defaultValue: true)),
          allowFractions: Value(_bool(row['allowFractions'])),
          minStock: Value(_integer(row['minStock'])),
          createdAt: _date(row['createdAt'], now),
          updatedAt: _date(row['updatedAt'], now),
        );
      }).toList();
      if (productCompanions.isNotEmpty) {
        await _database.batch((batch) => batch.insertAll(
              _database.products,
              productCompanions,
              mode: InsertMode.insertOrIgnore,
            ));
      }

      final tierCompanions = pricingTiers
          .map((row) => ProductPricingTiersCompanion.insert(
                id: _requiredString(row['id'], 'price tier id'),
                productId: _requiredString(row['productId'], 'tier product id'),
                unit: _requiredString(row['unit'], 'tier unit'),
                quantityPerUnit: _number(row['quantityPerUnit']),
                price: _number(row['price']),
                sortOrder: Value(_integer(row['sortOrder'])),
              ))
          .toList();
      if (tierCompanions.isNotEmpty) {
        await _database.batch((batch) => batch.insertAll(
              _database.productPricingTiers,
              tierCompanions,
              mode: InsertMode.insertOrIgnore,
            ));
      }

      final branchById = {
        for (final row in branches) row['id'].toString(): row
      };
      final productById = {
        for (final row in products) row['id'].toString(): row
      };
      final stockCompanions = <LocalStockCompanion>[];
      for (final row in stock) {
        final productId = _requiredString(row['productId'], 'stock product id');
        final branchId = _requiredString(row['branchId'], 'stock branch id');
        final product = productById[productId]!;
        final quantity = _number(row['quantity']);
        if (quantity < 0) {
          throw const LocalArchiveImportException(
            'The archive contains negative on-hand stock. Correct the archive before importing it.',
          );
        }
        stockCompanions.add(LocalStockCompanion.insert(
          id: 'archive-${_requiredString(row['id'], 'stock id')}',
          productId: productId,
          branchId: branchId,
          quantity: quantity,
          minQuantity: Value(_integer(product['minStock'])),
          displayUnit: Value(_nullableString(product['unit'])),
          updatedAt: _date(row['updatedAt'], now),
        ));
        final branch = branchById[branchId];
        if (branch != null) {
          await _database.ensureLocalBranch(
            id: branchId,
            name: _string(branch['name'], 'Main branch'),
            location: _string(branch['address'], ''),
            phone: _string(branch['phone'], ''),
          );
        }
      }
      if (stockCompanions.isNotEmpty) {
        await _database.batch((batch) => batch.insertAll(
              _database.localStock,
              stockCompanions,
              mode: InsertMode.insertOrIgnore,
            ));
      }

      for (final row in customers) {
        final id = _requiredString(row['id'], 'customer id');
        final customerSales = completedSalesByCustomer[id] ?? const [];
        final totalSpent = customerSales.fold<double>(
          0,
          (sum, sale) => sum + _number(sale['totalAmount']),
        );
        final lastPurchase = customerSales
            .map((sale) => _date(sale['createdAt'], now))
            .fold<DateTime?>(
                null,
                (latest, date) =>
                    latest == null || date.isAfter(latest) ? date : latest);
        await _database.customInsert(
          'INSERT OR IGNORE INTO customers '
          '(id, tenant_id, name, phone, email, location, notes, total_purchases, '
          'total_spent, last_purchase_at, created_at, balance, credit_limit, loyalty_points) '
          'VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(id),
            Variable.withString(tenantId),
            Variable.withString(_requiredString(row['name'], 'customer name')),
            _variableString(row['phone']),
            _variableString(row['email']),
            _variableString(row['address']),
            Variable.withInt(customerSales.length),
            Variable.withReal(totalSpent),
            lastPurchase == null
                ? const Variable<String>(null)
                : Variable.withString(lastPurchase.toIso8601String()),
            Variable.withString(_date(row['createdAt'], now).toIso8601String()),
            Variable.withReal(outstandingByCustomer[id] ?? 0),
            Variable.withReal(_number(row['creditLimit'])),
            Variable.withInt(_integer(row['loyaltyPoints'])),
          ],
        );
      }

      final receivableById = {
        for (final row in receivables) row['id'].toString(): row,
      };
      for (final row in receivablePayments) {
        final receivable = receivableById[row['receivableId']?.toString()];
        final customerId = _nullableString(row['customerId']) ??
            _nullableString(receivable?['customerId']);
        if (customerId == null) continue;
        await _database.customInsert(
          'INSERT OR IGNORE INTO local_cash_collections '
          '(id, tenant_id, branch_id, customer_id, amount, collected_at, payment_method, reference) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(
              _requiredString(row['id'], 'customer collection id'),
            ),
            Variable.withString(tenantId),
            Variable.withString(
              _requiredString(row['branchId'], 'customer collection branch id'),
            ),
            Variable.withString(customerId),
            Variable.withReal(_number(row['amount'])),
            Variable.withString(
              _date(
                row['paidAt'],
                _date(row['createdAt'], now),
              ).toIso8601String(),
            ),
            Variable.withString(
              _string(row['method'], 'CASH').toUpperCase(),
            ),
            _variableString(row['reference']),
          ],
        );
      }

      for (final row in customerInstallments) {
        await _database.customInsert(
          'INSERT OR IGNORE INTO customer_installments '
          '(id, tenant_id, customer_id, amount, paid_amount, due_date, note, status, '
          'created_at, paid_at, collection_allocations, cancelled_at, cancelled_by, cancel_reason) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(
                _requiredString(row['id'], 'customer schedule id')),
            Variable.withString(tenantId),
            Variable.withString(
                _requiredString(row['customerId'], 'schedule customer id')),
            Variable.withReal(_number(row['amount'])),
            Variable.withReal(_number(row['paidAmount'])),
            Variable.withString(
                _requiredString(row['dueDate'], 'schedule due date')),
            Variable.withString(_string(row['note'], '')),
            Variable.withString(_string(row['status'], 'pending')),
            Variable.withString(_date(row['createdAt'], now).toIso8601String()),
            _variableString(row['paidAt']),
            _variableString(row['collectionAllocations']),
            _variableString(row['cancelledAt']),
            _variableString(row['cancelledBy']),
            _variableString(row['cancelReason']),
          ],
        );
      }

      for (final row in suppliers) {
        await _database.customInsert(
          'INSERT OR IGNORE INTO suppliers '
          '(id, tenant_id, name, contact_name, email, phone, address, is_active, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(_requiredString(row['id'], 'supplier id')),
            Variable.withString(tenantId),
            Variable.withString(_requiredString(row['name'], 'supplier name')),
            _variableString(row['contactName']),
            _variableString(row['email']),
            _variableString(row['phone']),
            _variableString(row['address']),
            Variable.withInt(
                _bool(row['isActive'], defaultValue: true) ? 1 : 0),
            Variable.withString(_date(row['createdAt'], now).toIso8601String()),
            Variable.withString(_date(row['updatedAt'], now).toIso8601String()),
          ],
        );
      }

      for (final row in supplierInvoices) {
        final status = _archiveInvoiceStatus(
          row['status'],
          paid: _number(row['paidAmount']),
          due: _number(row['dueAmount']),
        );
        await _database.customInsert(
          'INSERT OR IGNORE INTO supplier_invoices '
          '(id, supplier_id, invoice_number, receipt_image_path, ocr_text, summary, terms, '
          'subtotal, paid_amount, total_amount, due_amount, due_date, status, funding_source, created_at, updated_at) '
          'VALUES (?, ?, ?, NULL, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(
                _requiredString(row['id'], 'supplier invoice id')),
            Variable.withString(
                _requiredString(row['supplierId'], 'invoice supplier id')),
            _variableString(row['invoiceNumber']),
            Variable.withString('pay_later'),
            Variable.withReal(_number(row['subtotal'])),
            Variable.withReal(_number(row['paidAmount'])),
            Variable.withReal(_number(row['totalAmount'])),
            Variable.withReal(_number(row['dueAmount'])),
            _dateVariable(row['dueDate']),
            Variable.withString(status),
            Variable.withString(_archiveFundingSource(row['fundingSource'])),
            Variable.withString(_date(row['createdAt'], now).toIso8601String()),
            Variable.withString(_date(row['updatedAt'], now).toIso8601String()),
          ],
        );
      }

      for (final row in supplierInvoiceItems) {
        final sourceProductId = _nullableString(row['productId']);
        await _database.customInsert(
          'INSERT OR IGNORE INTO supplier_invoice_items '
          '(id, invoice_id, product_id, product_name, sku, quantity, unit, unit_cost, line_total, confidence, raw_text, created_at) '
          'VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, 0, NULL, ?)',
          variables: [
            Variable.withString(
                _requiredString(row['id'], 'supplier invoice item id')),
            Variable.withString(
                _requiredString(row['invoiceId'], 'invoice item invoice id')),
            sourceProductId != null && productById.containsKey(sourceProductId)
                ? Variable.withString(sourceProductId)
                : const Variable<String>(null),
            Variable.withString(_requiredString(
                row['productName'], 'supplier invoice item name')),
            Variable.withReal(_number(row['quantity'])),
            Variable.withString(_string(row['unit'], 'piece')),
            Variable.withReal(_number(row['unitCost'])),
            Variable.withReal(_number(row['lineTotal'])),
            Variable.withString(_date(row['createdAt'], now).toIso8601String()),
          ],
        );
      }

      for (final row in supplierPayments) {
        await _database.customInsert(
          'INSERT OR IGNORE INTO supplier_payments '
          '(supplier_id, amount, notes, payment_date, created_at, invoice_id, request_id, funding_source) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(_requiredString(
                row['supplierId'], 'supplier payment supplier id')),
            Variable.withReal(_number(row['amount'])),
            _variableString(row['notes']),
            Variable.withString(_date(row['paidAt'], now).toIso8601String()),
            Variable.withString(_date(row['createdAt'], now).toIso8601String()),
            _variableString(row['invoiceId']),
            Variable.withString(
                'archive:${_requiredString(row['id'], 'supplier payment id')}'),
            Variable.withString(_archiveFundingSource(row['fundingSource'])),
          ],
        );
      }

      final saleCompanions = sales.map((row) {
        final saleId = _requiredString(row['id'], 'sale id');
        final relatedPayments = paymentsBySale[saleId] ?? const [];
        final paymentMethod =
            _string(row['paymentMethod'], 'OTHER').toUpperCase();
        final saleTotal = _number(row['totalAmount']);
        final saleDiscount = _number(row['discountAmount'] ?? 0);
        final saleTax = _number(row['taxAmount'] ?? 0);
        final saleSubtotal = row['subtotal'] == null
            ? saleTotal + saleDiscount - saleTax
            : _number(row['subtotal']);
        String? reference;
        if (paymentMethod == 'SPLIT') {
          reference = _archiveSplitPaymentReference(
            relatedPayments,
            expectedTotal: saleTotal,
          );
        } else {
          reference = relatedPayments
                  .where((payment) =>
                      payment['status']?.toString().toUpperCase() ==
                      'COMPLETED')
                  .map((payment) => _nullableString(payment['transactionId']))
                  .firstWhere((value) => value != null, orElse: () => null) ??
              _nullableString(row['offlineId']);
        }
        final customerId = _nullableString(row['customerId']);
        return PendingSalesCompanion.insert(
          id: saleId,
          receiptNumber:
              _requiredString(row['receiptNumber'], 'receipt number'),
          subtotal: saleSubtotal,
          discount: Value(saleDiscount),
          tax: Value(saleTax),
          total: saleTotal,
          paymentMethod: paymentMethod,
          paymentReference: Value(reference),
          customerId: Value(customerId),
          cashierId: _string(row['userId'], 'unknown'),
          branchId: _requiredString(row['branchId'], 'sale branch id'),
          notes: Value(_nullableString(row['notes'])),
          status: Value(_string(row['status'], 'COMPLETED').toUpperCase()),
          createdAt: _date(row['createdAt'], now),
          isSynced: const Value(true),
          syncedAt: Value(_date(row['updatedAt'], now)),
        );
      }).toList();
      if (saleCompanions.isNotEmpty) {
        await _database.batch((batch) => batch.insertAll(
              _database.pendingSales,
              saleCompanions,
              mode: InsertMode.insertOrIgnore,
            ));
      }

      final saleItemCompanions = <PendingSaleItemsCompanion>[];
      final skuByProductId = {
        for (final row in products)
          row['id'].toString(): _string(row['sku'], '')
      };
      for (final row in saleItems) {
        final productId = _nullableString(row['productId']);
        final quantityPerUnit = _optionalNumber(row['quantityPerUnit']);
        saleItemCompanions.add(PendingSaleItemsCompanion.insert(
          saleId: _requiredString(row['saleId'], 'sale item sale id'),
          productId: _string(productId, ''),
          productName: _requiredString(row['productName'], 'sale item name'),
          sku: skuByProductId[productId] ?? '',
          quantity: _number(row['quantity']),
          unitPrice: _number(row['unitPrice']),
          discount: Value(_number(row['discount'] ?? 0)),
          total: _number(row['totalAmount']),
          unit: Value(_nullableString(row['unit'])),
          quantityPerUnit: Value(quantityPerUnit),
        ));
      }
      if (saleItemCompanions.isNotEmpty) {
        await _database.batch((batch) => batch.insertAll(
              _database.pendingSaleItems,
              saleItemCompanions,
              mode: InsertMode.insertOrIgnore,
            ));
      }

      await _database.customStatement('''
        CREATE TABLE IF NOT EXISTS local_import_archives (
          archive_id TEXT PRIMARY KEY NOT NULL,
          tenant_id TEXT NOT NULL,
          tenant_name TEXT NOT NULL,
          imported_at TEXT NOT NULL,
          payload_json TEXT NOT NULL
        )
      ''');
      await _database.customInsert(
        'INSERT INTO local_import_archives '
        '(archive_id, tenant_id, tenant_name, imported_at, payload_json) '
        'VALUES (?, ?, ?, ?, ?)',
        variables: [
          Variable.withString(preview.archiveId),
          Variable.withString(tenantId),
          Variable.withString(preview.tenantName),
          Variable.withString(now.toIso8601String()),
          Variable.withString(jsonEncode(preview.payload)),
        ],
      );
    });

    final branchProfile = branches.map((row) {
      final id = row['id'].toString();
      final previousBranches = _storage.getUser()?['branches'];
      Map<String, dynamic>? previousBranch;
      if (previousBranches is List) {
        for (final value in previousBranches.whereType<Map>()) {
          final candidate = Map<String, dynamic>.from(value);
          if (candidate['id']?.toString() == id) {
            previousBranch = candidate;
            break;
          }
        }
      }
      return <String, dynamic>{
        ...?previousBranch,
        'id': id,
        'name': _string(row['name'], 'Main branch'),
        'code': _string(row['code'], ''),
        'location': _string(row['address'], ''),
        'phone': _string(row['phone'], ''),
        'isActive': _bool(row['isActive'], defaultValue: true),
        'isPrimary': id == activeBranchId,
        'createdAt': _date(row['createdAt'], now).toIso8601String(),
      };
    }).toList(growable: false);
    if (preview.workspaceMatches) {
      await _auth.updateLocalWorkspaceBranches(branchProfile);
    } else {
      await _auth.adoptLocalArchiveIdentity(
        tenantId: preview.tenantId,
        tenantName: preview.tenantName,
        tenantSlug: _tenantSlug(rows['tenant'] as Map),
        activeBranchId: activeBranchId,
        branches: branchProfile,
      );
    }

    return LocalArchiveImportResult(
      alreadyImported: false,
      recordCount: preview.totalCount,
      tenantName: preview.tenantName,
    );
  }

  void _requirePreviewOwner(LocalArchiveImportPreview preview) {
    final tenantId = _requireArchiveOwnerTenantId();
    if ((_auth.userId ?? '') != preview.ownerUserId ||
        (tenantId != preview.activeWorkspaceTenantId &&
            tenantId != preview.tenantId)) {
      throw const LocalArchiveImportException(
        'The active shop changed after this archive was previewed. Select and preview the archive again.',
      );
    }
  }

  void _validateReferences({
    required List<Map<String, dynamic>> branches,
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> productCategories,
    required List<Map<String, dynamic>> pricingTiers,
    required List<Map<String, dynamic>> customers,
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> saleItems,
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> stock,
    required List<Map<String, dynamic>> receivables,
    required List<Map<String, dynamic>> receivablePayments,
    required List<Map<String, dynamic>> customerInstallments,
    required List<Map<String, dynamic>> suppliers,
    required List<Map<String, dynamic>> supplierInvoices,
    required List<Map<String, dynamic>> supplierInvoiceItems,
    required List<Map<String, dynamic>> supplierPayments,
  }) {
    final branchIds =
        branches.map((row) => _requiredString(row['id'], 'branch id')).toSet();
    final categoryIds = categories
        .map((row) => _requiredString(row['id'], 'category id'))
        .toSet();
    final productIds =
        products.map((row) => _requiredString(row['id'], 'product id')).toSet();
    final customerIds = customers
        .map((row) => _requiredString(row['id'], 'customer id'))
        .toSet();
    final saleIds =
        sales.map((row) => _requiredString(row['id'], 'sale id')).toSet();
    final supplierIds = suppliers
        .map((row) => _requiredString(row['id'], 'supplier id'))
        .toSet();
    final invoiceById = {
      for (final row in supplierInvoices)
        _requiredString(row['id'], 'supplier invoice id'): row,
    };
    final receivableById = {
      for (final row in receivables)
        _requiredString(row['id'], 'receivable id'): row,
    };
    for (final row in productCategories) {
      if (!productIds.contains(row['productId']) ||
          !categoryIds.contains(row['categoryId'])) {
        throw const LocalArchiveImportException(
            'A product category link is incomplete.');
      }
    }
    for (final row in pricingTiers) {
      if (!productIds.contains(row['productId'])) {
        throw const LocalArchiveImportException(
            'A bulk price refers to a missing product.');
      }
    }
    for (final row in sales) {
      if (!branchIds.contains(row['branchId'])) {
        throw const LocalArchiveImportException(
            'A sale refers to a missing shop branch.');
      }
      final customerId = _nullableString(row['customerId']);
      if (customerId != null && !customerIds.contains(customerId)) {
        throw const LocalArchiveImportException(
            'A sale refers to a missing customer.');
      }
    }
    for (final row in saleItems) {
      if (!saleIds.contains(row['saleId'])) {
        throw const LocalArchiveImportException(
            'A sale item refers to a missing receipt.');
      }
      if (_number(row['quantity']) <= 0) {
        throw const LocalArchiveImportException(
            'A sale item has an invalid quantity.');
      }
    }
    for (final row in payments) {
      if (!saleIds.contains(row['saleId'])) {
        throw const LocalArchiveImportException(
          'A payment refers to a missing receipt.',
        );
      }
      if (_number(row['amount']) <= 0) {
        throw const LocalArchiveImportException(
          'A payment record has an invalid amount.',
        );
      }
    }
    for (final row in stock) {
      if (!productIds.contains(row['productId']) ||
          !branchIds.contains(row['branchId'])) {
        throw const LocalArchiveImportException(
            'Stock refers to a missing product or branch.');
      }
    }
    for (final row in receivables) {
      final customerId = _nullableString(row['customerId']);
      if (customerId != null && !customerIds.contains(customerId)) {
        throw const LocalArchiveImportException(
            'A credit balance refers to a missing customer.');
      }
    }
    for (final row in receivablePayments) {
      final receivableId = _nullableString(row['receivableId']);
      final receivable =
          receivableId == null ? null : receivableById[receivableId];
      final branchId = row['branchId']?.toString() ?? '';
      final customerId = _nullableString(row['customerId']) ??
          _nullableString(receivable?['customerId']);
      if (!branchIds.contains(branchId) ||
          customerId == null ||
          !customerIds.contains(customerId) ||
          (receivableId != null &&
              (receivable == null ||
                  receivable['branchId'] != branchId ||
                  (receivable['customerId'] != null &&
                      receivable['customerId'] != customerId)))) {
        throw const LocalArchiveImportException(
          'A customer collection refers to a missing receivable or branch.',
        );
      }
      if (_number(row['amount']) <= 0) {
        throw const LocalArchiveImportException(
          'A customer collection must have a positive amount.',
        );
      }
    }
    for (final row in customerInstallments) {
      final customerId = _requiredString(
        row['customerId'],
        'scheduled payment customer id',
      );
      final amount = _number(row['amount']);
      final paidAmount = _number(row['paidAmount']);
      if (!customerIds.contains(customerId) ||
          !amount.isFinite ||
          amount <= 0 ||
          !paidAmount.isFinite ||
          paidAmount < 0 ||
          paidAmount > amount + 0.005 ||
          DateTime.tryParse(row['dueDate']?.toString() ?? '') == null) {
        throw const LocalArchiveImportException(
          'A scheduled customer payment contains an invalid customer, amount or due date.',
        );
      }
    }
    for (final row in suppliers) {
      _requiredString(row['name'], 'supplier name');
    }
    for (final row in supplierInvoices) {
      if (!supplierIds.contains(row['supplierId']) ||
          !branchIds.contains(row['branchId'])) {
        throw const LocalArchiveImportException(
          'A supplier invoice refers to a missing supplier or branch.',
        );
      }
      for (final field in [
        'subtotal',
        'paidAmount',
        'totalAmount',
        'dueAmount'
      ]) {
        if (_number(row[field]) < 0) {
          throw const LocalArchiveImportException(
            'A supplier invoice contains a negative amount.',
          );
        }
      }
    }
    for (final row in supplierInvoiceItems) {
      final invoiceId = row['invoiceId']?.toString() ?? '';
      if (!invoiceById.containsKey(invoiceId)) {
        throw const LocalArchiveImportException(
          'A supplier invoice item refers to a missing invoice.',
        );
      }
      if (_number(row['quantity']) <= 0 ||
          _number(row['unitCost']) < 0 ||
          _number(row['lineTotal']) < 0) {
        throw const LocalArchiveImportException(
          'A supplier invoice item contains an invalid quantity or cost.',
        );
      }
    }
    for (final row in supplierPayments) {
      final supplierId = row['supplierId']?.toString() ?? '';
      final invoiceId = _nullableString(row['invoiceId']);
      if (!supplierIds.contains(supplierId) ||
          (invoiceId != null &&
              (!invoiceById.containsKey(invoiceId) ||
                  invoiceById[invoiceId]?['supplierId'] != supplierId))) {
        throw const LocalArchiveImportException(
          'A supplier payment refers to a missing or mismatched supplier invoice.',
        );
      }
      if (_number(row['amount']) <= 0) {
        throw const LocalArchiveImportException(
          'A supplier payment must have a positive amount.',
        );
      }
    }
  }

  Future<bool> _localWorkspaceIsEmpty() async {
    await _database.createBranchesTable();
    await _database.createCustomersTable();
    final tables = await _database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    const infrastructureTables = {
      'settings',
      'favorite_products',
      'recent_searches',
      'android_metadata',
    };
    for (final row in tables) {
      final name = row.read<String>('name');
      if (infrastructureTables.contains(name)) continue;
      final safeName = name.replaceAll('"', '""');
      final count = await _database
          .customSelect(
            'SELECT COUNT(*) AS row_count FROM "$safeName"',
          )
          .getSingle();
      final records = count.read<int>('row_count');
      if (records == 0) continue;
      if (name == 'categories') {
        final nonDefault = await _database
            .customSelect(
              "SELECT COUNT(*) AS row_count FROM categories "
              "WHERE id <> 'local-default-category'",
            )
            .getSingle();
        if (nonDefault.read<int>('row_count') == 0) continue;
      }
      if (name == 'branches') {
        final nonStarter = await _database
            .customSelect(
              "SELECT COUNT(*) AS row_count FROM branches WHERE id = 'local-main'",
            )
            .getSingle();
        if (records == nonStarter.read<int>('row_count')) continue;
      }
      return false;
    }
    return true;
  }

  static String _selectPrimaryBranch(Map<String, dynamic> payload) {
    final branches = _maps(payload['branches']);
    final branchIds = branches.map((row) => row['id']?.toString()).toSet();
    final userBranches = _maps(payload['userBranches']);
    for (final row in userBranches) {
      final branchId = row['branchId']?.toString();
      if (_bool(row['isPrimary']) && branchIds.contains(branchId)) {
        return branchId!;
      }
    }
    if (branches.isEmpty) {
      throw const LocalArchiveImportException(
        'The archive has no shop branch to make active.',
      );
    }
    return _requiredString(branches.first['id'], 'primary branch id');
  }

  static String _tenantSlug(Map tenant) {
    final saved = tenant['slug']?.toString().trim() ?? '';
    if (saved.isNotEmpty) return saved;
    final name = tenant['name']?.toString() ?? '';
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) {
      throw const LocalArchiveImportException(
        'The archive shop name cannot be converted into a local shop ID.',
      );
    }
    return slug;
  }

  static List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  static String _requiredString(dynamic value, String label) {
    final result = value?.toString().trim() ?? '';
    if (result.isEmpty) {
      throw LocalArchiveImportException('The archive is missing $label.');
    }
    return result;
  }

  static List<int> _decodeArchiveBytes(
    String encoded,
    int? expectedLength,
    String label,
  ) {
    final bytes = base64.decode(encoded);
    if (expectedLength != null && bytes.length != expectedLength) {
      throw LocalArchiveImportException(
        'The archive $label has an invalid length.',
      );
    }
    return bytes;
  }

  static String _string(dynamic value, String fallback) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? null : result;
  }

  static Variable<String> _variableString(dynamic value) {
    final result = _nullableString(value);
    return result == null
        ? const Variable<String>(null)
        : Variable.withString(result);
  }

  static Variable<String> _dateVariable(dynamic value) {
    final raw = _nullableString(value);
    if (raw == null) return const Variable<String>(null);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw const LocalArchiveImportException(
        'The archive contains an invalid date.',
      );
    }
    return Variable.withString(parsed.toUtc().toIso8601String());
  }

  static String _archiveInvoiceStatus(
    dynamic value, {
    required double paid,
    required double due,
  }) {
    final status = value?.toString().trim().toUpperCase() ?? '';
    if (const {'OPEN', 'PARTIAL', 'PAID'}.contains(status)) {
      return status.toLowerCase();
    }
    if (due <= 0) return 'paid';
    return paid > 0 ? 'partial' : 'open';
  }

  static String _archiveFundingSource(dynamic value) {
    final source = value?.toString().trim().toUpperCase() ?? '';
    return const {'CASH_TILL', 'CREDIT_SUPPLIER', 'BANK_OR_MPESA'}
            .contains(source)
        ? source
        : 'CASH_TILL';
  }

  /// Rebuilds the local receipt's split-tender JSON from the archived payment
  /// rows. If the source rows do not describe the exact CASH + CREDIT split
  /// recorded by the sale, leave it absent so End of Day marks it unreconciled
  /// instead of inventing a payment breakdown.
  static String? _archiveSplitPaymentReference(
    List<Map<String, dynamic>> payments, {
    required double expectedTotal,
  }) {
    if (payments.length != 2 || !expectedTotal.isFinite || expectedTotal <= 0) {
      return null;
    }

    final tenders = <Map<String, dynamic>>[];
    var cashCount = 0;
    var creditCount = 0;
    var totalCents = 0;

    for (final payment in payments) {
      final method = payment['method']?.toString().trim().toUpperCase() ?? '';
      final status = payment['status']?.toString().trim().toUpperCase() ?? '';
      if (method != 'CASH' && method != 'CREDIT') return null;
      if (method == 'CASH') {
        cashCount++;
        if (status != 'COMPLETED') return null;
      } else {
        creditCount++;
        if (status != 'PENDING' && status != 'COMPLETED') return null;
      }

      final amount = payment['amount'] is num
          ? (payment['amount'] as num).toDouble()
          : double.tryParse(payment['amount']?.toString() ?? '');
      if (amount == null || !amount.isFinite || amount <= 0) return null;
      final cents = (amount * 100).round();
      if (cents <= 0) return null;
      totalCents += cents;
      final reference = _nullableString(payment['transactionId']);

      tenders.add({
        'method': method,
        'amount': cents / 100,
        if (reference != null) 'reference': reference,
      });
    }

    if (cashCount != 1 ||
        creditCount != 1 ||
        totalCents != (expectedTotal * 100).round()) {
      return null;
    }

    tenders.sort((left, right) {
      if (left['method'] == right['method']) return 0;
      return left['method'] == 'CASH' ? -1 : 1;
    });
    return jsonEncode(tenders);
  }

  static double _number(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null || !parsed.isFinite) {
      throw const LocalArchiveImportException(
          'The archive contains an invalid amount.');
    }
    return parsed;
  }

  static double? _optionalNumber(dynamic value) {
    if (value == null) return null;
    return _number(value);
  }

  static int _integer(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    final parsed = int.tryParse(value.toString());
    return parsed ?? _number(value).round();
  }

  static bool _bool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'true', '1', 'yes'}.contains(value.toString().toLowerCase());
  }

  static DateTime _date(dynamic value, DateTime fallback) {
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value?.toString() ?? '')?.toUtc() ?? fallback;
  }
}

List<Map<String, dynamic>> _archiveRecordList(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((record) => Map<String, dynamic>.from(record))
        .toList(growable: false)
    : const <Map<String, dynamic>>[];
