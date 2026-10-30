import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/app_database.dart';
import 'auth_service.dart';
import 'local_archive_import_service.dart';
import 'storage_service.dart';

/// Produces the cross-platform .cbarchive format consumed by both mobile and
/// desktop. This deliberately carries the common operational records; the
/// full-fidelity .cbmobile backup remains available for phone-to-phone moves.
class LocalArchiveExportService {
  LocalArchiveExportService({
    required AppDatabase database,
    required StorageService storage,
    required AuthService auth,
  })  : _database = database,
        _storage = storage,
        _auth = auth;

  static const _maxPlaintextBytes = 45 * 1024 * 1024;
  static const _maxArchiveBytes = 64 * 1024 * 1024;
  static const _iterations = 310000;
  static const _aadPrefix = 'counterbase-local-archive:v2';

  final AppDatabase _database;
  final StorageService _storage;
  final AuthService _auth;

  Future<File> createArchive({required String passphrase}) async {
    _requireOwner();
    if (passphrase.length < 12 ||
        passphrase.length > 1024 ||
        passphrase.contains('\u0000')) {
      throw const FormatException(
        'Use a backup password between 12 and 1024 characters.',
      );
    }

    final payload = await _buildPayload();
    _requireOwner();
    final plaintext = utf8.encode(jsonEncode(payload));
    if (plaintext.length > _maxPlaintextBytes) {
      throw const FormatException(
        'This shop is too large for a cross-platform transfer file. Use the full encrypted device backup instead.',
      );
    }

    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));
    final saltText = base64Encode(salt);
    final nonceText = base64Encode(nonce);
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final aad = utf8.encode(
      '$_aadPrefix:$createdAt:$saltText:$nonceText:$_iterations',
    );
    final key = await Pbkdf2.hmacSha256(
      iterations: _iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
    final encrypted = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: aad,
    );
    final envelope = <String, dynamic>{
      'format': 'counterbase-local-archive',
      'version': 2,
      'encryption': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _iterations,
      'createdAt': createdAt,
      'salt': saltText,
      'nonce': nonceText,
      'tag': base64Encode(encrypted.mac.bytes),
      'ciphertext': base64Encode(encrypted.cipherText),
    };
    final bytes = utf8.encode(jsonEncode(envelope));
    if (bytes.length > _maxArchiveBytes) {
      throw const FormatException(
        'This transfer file exceeds the 64 MB share limit. Use the full encrypted device backup instead.',
      );
    }
    final preview = await LocalArchiveImportService(
      database: _database,
      storage: _storage,
      auth: _auth,
    ).previewBytes(Uint8List.fromList(bytes), passphrase: passphrase);
    final expectedCounts = <String, int>{
      for (final entry in payload.entries)
        if (entry.key != 'tenant') entry.key: (entry.value as List).length,
    };
    final countsMatch = expectedCounts.entries.every(
      (entry) => preview.counts[entry.key] == entry.value,
    );
    if (preview.tenantId != _storage.getTenantId() || !countsMatch) {
      throw const FormatException(
        'The cross-platform transfer did not pass its content verification.',
      );
    }

    final directory = await getApplicationSupportDirectory();
    final transfers = Directory(
      '${directory.path}${Platform.pathSeparator}Counterbase${Platform.pathSeparator}transfers',
    );
    await transfers.create(recursive: true);
    final safeTime = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '');
    final file = File(
      '${transfers.path}${Platform.pathSeparator}Counterbase-$safeTime.cbarchive',
    );
    try {
      _requireOwner();
      await file.writeAsBytes(bytes, flush: true);
      if (await file.length() < 1024) {
        throw const FormatException('The shop transfer file is incomplete.');
      }
      return file;
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Keep the primary export failure.
      }
      debugPrint('[LocalArchiveExport] Transfer file creation failed.');
      rethrow;
    }
  }

  Future<void> shareArchive(File file) async {
    _requireOwner();
    if (!await file.exists()) {
      throw const FileSystemException(
        'The transfer file is no longer available.',
      );
    }
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Counterbase encrypted shop transfer',
      text:
          'This file carries products, customer balances and collections, payment schedules, completed sales and stock. Keep its password separate from the file.',
    );
  }

  Future<Map<String, dynamic>> _buildPayload() async {
    final user = _storage.getUser();
    final localWorkspace = _storage.getLocalWorkspace();
    final tenant = _asMap(user?['tenant']) ?? _asMap(localWorkspace?['tenant']);
    final tenantId = _storage.getTenantId()?.trim() ?? '';
    final tenantName = tenant?['name']?.toString().trim() ?? '';
    final slug = tenant?['slug']?.toString().trim() ??
        _storage.getTenantSlug()?.trim() ??
        '';
    if (tenantId.isEmpty || tenantName.isEmpty) {
      throw const FormatException(
        'The local shop profile is incomplete. Reopen the shop and try again.',
      );
    }

    await _database.createBranchesTable();
    await _database.createCustomersTable();

    final branchRows = await _database
        .customSelect(
          'SELECT id, name, location, phone, is_active, created_at FROM branches ORDER BY id',
        )
        .get();
    final branches = branchRows.map((row) {
      final id = row.read<String>('id');
      return <String, dynamic>{
        'id': id,
        'name': row.read<String>('name'),
        'code': id == _storage.getBranchId() ? 'MAIN' : '',
        'address': row.read<String>('location'),
        'phone': row.readNullable<String>('phone') ?? '',
        'isActive': row.read<int>('is_active') != 0,
        'isPrimary': id == _storage.getBranchId(),
        'createdAt': _date(row.data['created_at']),
      };
    }).toList(growable: false);
    if (branches.isEmpty) {
      throw const FormatException('This shop has no branch to transfer.');
    }
    final branchIds = branches.map((branch) => branch['id'] as String).toSet();

    final categoryRows = await _database
        .customSelect(
          'SELECT id, name, description, parent_id, sort_order, is_active, created_at, updated_at FROM categories ORDER BY sort_order, name',
        )
        .get();
    final categories = categoryRows
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'name': row.read<String>('name'),
              'description': row.readNullable<String>('description'),
              'parentId': row.readNullable<String>('parent_id'),
              'sortOrder': row.read<int>('sort_order'),
              'isActive': row.read<int>('is_active') != 0,
              'createdAt': _date(row.data['created_at']),
              'updatedAt': _date(row.data['updated_at']),
            })
        .toList(growable: false);
    final categoryIds = categories.map((row) => row['id'] as String).toSet();

    final productRows = await _database
        .customSelect(
          'SELECT id, sku, name, description, metadata, category_id, price, cost_price, unit, is_active, track_inventory, allow_fractions, min_stock, created_at, updated_at FROM products ORDER BY name',
        )
        .get();
    final products = productRows
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'sku': row.read<String>('sku'),
              'name': row.read<String>('name'),
              'description': row.readNullable<String>('description'),
              'metadata': _decodeMap(row.read<String>('metadata')),
              'basePrice': row.read<double>('price'),
              'costPrice': row.readNullable<double>('cost_price'),
              'minStock': row.read<int>('min_stock'),
              'unit': row.read<String>('unit'),
              'trackInventory': row.read<int>('track_inventory') != 0,
              'allowFractions': row.read<int>('allow_fractions') != 0,
              'isActive': row.read<int>('is_active') != 0,
              'createdAt': _date(row.data['created_at']),
              'updatedAt': _date(row.data['updated_at']),
            })
        .toList(growable: false);
    final productIds = products.map((row) => row['id'] as String).toSet();
    final productCategories = productRows
        .map((row) => {
              'productId': row.read<String>('id'),
              'categoryId': row.read<String>('category_id'),
            })
        .where((row) => categoryIds.contains(row['categoryId']))
        .toList(growable: false);

    final customerRows = await _database.customSelect(
      'SELECT id, name, email, phone, location, created_at, balance, credit_limit, loyalty_points FROM customers WHERE tenant_id = ? ORDER BY name',
      variables: [Variable.withString(tenantId)],
    ).get();
    final customers = customerRows
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'name': row.read<String>('name'),
              'email': row.readNullable<String>('email') ?? '',
              'phone': row.readNullable<String>('phone') ?? '',
              'address': row.readNullable<String>('location') ?? '',
              'balance': row.read<double>('balance'),
              'creditLimit': row.read<double>('credit_limit'),
              'loyaltyPoints': row.read<int>('loyalty_points'),
              'isActive': true,
              'createdAt': _date(row.data['created_at']),
            })
        .toList(growable: false);
    final customerIds = customers.map((row) => row['id'] as String).toSet();

    await _database.ensureLocalCashCollectionsSchema();
    final collectionRows = await _database.customSelect(
      'SELECT id, branch_id, customer_id, amount, collected_at, payment_method, reference '
      'FROM local_cash_collections WHERE tenant_id = ? ORDER BY collected_at, id',
      variables: [Variable.withString(tenantId)],
    ).get();
    final customerCollections = collectionRows
        .where((row) =>
            branchIds.contains(row.read<String>('branch_id')) &&
            customerIds.contains(row.read<String>('customer_id')))
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'customerId': row.read<String>('customer_id'),
              'branchId': row.read<String>('branch_id'),
              'amount': row.read<double>('amount'),
              'paidAt': row.read<String>('collected_at'),
              'createdAt': row.read<String>('collected_at'),
              'method': row.read<String>('payment_method'),
              'reference': row.readNullable<String>('reference'),
            })
        .toList(growable: false);

    await _database.createCustomerInstallmentsTable();
    final installmentRows = await _database.customSelect(
      'SELECT id, customer_id, amount, paid_amount, due_date, note, status, '
      'created_at, paid_at, collection_allocations, cancelled_at, cancelled_by, cancel_reason '
      'FROM customer_installments WHERE tenant_id = ? ORDER BY due_date, created_at, id',
      variables: [Variable.withString(tenantId)],
    ).get();
    final customerInstallments = installmentRows
        .where((row) => customerIds.contains(row.read<String>('customer_id')))
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'customerId': row.read<String>('customer_id'),
              'amount': row.read<double>('amount'),
              'paidAmount': row.read<double>('paid_amount'),
              'dueDate': row.read<String>('due_date'),
              'note': row.readNullable<String>('note') ?? '',
              'status': row.read<String>('status'),
              'createdAt': row.read<String>('created_at'),
              'paidAt': row.readNullable<String>('paid_at'),
              'collectionAllocations':
                  row.readNullable<String>('collection_allocations'),
              'cancelledAt': row.readNullable<String>('cancelled_at'),
              'cancelledBy': row.readNullable<String>('cancelled_by'),
              'cancelReason': row.readNullable<String>('cancel_reason'),
            })
        .toList(growable: false);

    final stockRows = await _database
        .customSelect(
          'SELECT id, product_id, branch_id, quantity FROM local_stock ORDER BY branch_id, product_id',
        )
        .get();
    final stock = stockRows
        .where((row) =>
            productIds.contains(row.read<String>('product_id')) &&
            branchIds.contains(row.read<String>('branch_id')))
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'productId': row.read<String>('product_id'),
              'branchId': row.read<String>('branch_id'),
              'quantity': row.read<double>('quantity'),
            })
        .toList(growable: false);

    final salesRows = await _database
        .customSelect(
          'SELECT id, receipt_number, subtotal, discount, tax, total, payment_method, payment_reference, customer_id, branch_id, status, created_at, void_reason FROM pending_sales ORDER BY created_at',
        )
        .get();
    final sales = salesRows
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'receiptNumber': row.read<String>('receipt_number'),
              'createdAt': _date(row.data['created_at']),
              'paymentMethod': row.read<String>('payment_method'),
              'subtotal': row.read<double>('subtotal'),
              'totalAmount': row.read<double>('total'),
              'discountAmount': row.read<double>('discount'),
              'taxAmount': row.read<double>('tax'),
              'customerId':
                  customerIds.contains(row.readNullable<String>('customer_id'))
                      ? row.readNullable<String>('customer_id')
                      : null,
              'branchId': row.read<String>('branch_id'),
              'status':
                  row.readNullable<String>('void_reason')?.isNotEmpty == true
                      ? 'VOIDED'
                      : row.read<String>('status').toUpperCase(),
            })
        .where((sale) =>
            branchIds.contains(sale['branchId']) &&
            sale['status'] == 'COMPLETED')
        .toList(growable: false);
    final saleIds = sales.map((row) => row['id'] as String).toSet();
    final itemRows = await _database
        .customSelect(
          'SELECT id, sale_id, product_id, product_name, quantity, unit_price, discount, total, unit FROM pending_sale_items ORDER BY id',
        )
        .get();
    final saleItems = itemRows
        .where((row) => saleIds.contains(row.read<String>('sale_id')))
        .map((row) => <String, dynamic>{
              'id': row.read<int>('id').toString(),
              'saleId': row.read<String>('sale_id'),
              'productId': productIds.contains(row.read<String>('product_id'))
                  ? row.read<String>('product_id')
                  : null,
              'productName': row.read<String>('product_name'),
              'quantity': row.read<double>('quantity'),
              'unitPrice': row.read<double>('unit_price'),
              'discount': row.read<double>('discount'),
              'totalAmount': row.read<double>('total'),
              'unit': row.readNullable<String>('unit'),
            })
        .toList(growable: false);
    final splitPayments = <Map<String, dynamic>>[
      for (final row in salesRows)
        if (saleIds.contains(row.read<String>('id')))
          ..._splitPaymentRows(
            saleId: row.read<String>('id'),
            paymentMethod: row.read<String>('payment_method'),
            reference: row.readNullable<String>('payment_reference'),
            total: row.read<double>('total'),
          ),
    ];

    final activeBranchId = _storage.getBranchId();
    if (!branches.any((branch) => branch['isPrimary'] == true) &&
        activeBranchId != null) {
      for (final branch in branches) {
        branch['isPrimary'] = branch['id'] == activeBranchId;
      }
    }

    return <String, dynamic>{
      'tenant': {'id': tenantId, 'name': tenantName, 'slug': slug},
      'branches': branches,
      'users': const <dynamic>[],
      'categories': categories,
      'products': products,
      'productCategories': productCategories,
      'pricingTiers': const <dynamic>[],
      'customers': customers,
      'suppliers': const <dynamic>[],
      'supplierInvoices': const <dynamic>[],
      'supplierInvoiceItems': const <dynamic>[],
      'supplierPayments': const <dynamic>[],
      'sales': sales,
      'saleItems': saleItems,
      'stock': stock,
      'stockBatches': const <dynamic>[],
      'stockMovements': const <dynamic>[],
      'payments': splitPayments,
      'retailReceivables': const <dynamic>[],
      'retailReceivablePayments': customerCollections,
      'customerInstallments': customerInstallments,
      'stockCounts': const <dynamic>[],
      'stockCountLines': const <dynamic>[],
    };
  }

  Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  Map<String, dynamic> _decodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  List<Map<String, dynamic>> _splitPaymentRows({
    required String saleId,
    required String paymentMethod,
    required String? reference,
    required double total,
  }) {
    if (paymentMethod.toUpperCase() != 'SPLIT' ||
        reference == null ||
        !total.isFinite ||
        total <= 0) {
      return const [];
    }
    try {
      final decoded = jsonDecode(reference);
      if (decoded is! List || decoded.length != 2) return const [];
      final rows = <Map<String, dynamic>>[];
      var cashCount = 0;
      var creditCount = 0;
      var totalCents = 0;
      for (final value in decoded) {
        if (value is! Map) return const [];
        final method = value['method']?.toString().toUpperCase() ?? '';
        final amountValue = value['amount'];
        final amount = amountValue is num
            ? amountValue.toDouble()
            : double.tryParse(amountValue?.toString() ?? '');
        if ((method != 'CASH' && method != 'CREDIT') ||
            amount == null ||
            !amount.isFinite ||
            amount <= 0) {
          return const [];
        }
        if (method == 'CASH') {
          cashCount++;
        } else {
          creditCount++;
        }
        final cents = (amount * 100).round();
        if (cents <= 0) return const [];
        totalCents += cents;
        final tenderReference = value['reference']?.toString().trim();
        rows.add({
          'id': 'transfer-$saleId-$method',
          'saleId': saleId,
          'method': method,
          'amount': cents / 100,
          'status': method == 'CASH' ? 'COMPLETED' : 'PENDING',
          if (tenderReference != null && tenderReference.isNotEmpty)
            'transactionId': tenderReference,
        });
      }
      if (cashCount != 1 ||
          creditCount != 1 ||
          totalCents != (total * 100).round()) {
        return const [];
      }
      return rows;
    } on FormatException {
      return const [];
    }
  }

  String _date(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).round(),
        isUtc: true,
      ).toIso8601String();
    }
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return (parsed ?? DateTime.now().toUtc()).toUtc().toIso8601String();
  }

  void _requireOwner() {
    if (!_auth.isLocalWorkspace ||
        !_auth.isAuthenticated ||
        !_auth.isLocalWorkspaceOwner) {
      throw StateError(
        'Unlock the local shop owner account to export a transfer file.',
      );
    }
  }
}
