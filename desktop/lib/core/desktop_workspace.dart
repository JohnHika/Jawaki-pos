import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

const localWorkspaceBranchId = 'local-main';

class LocalWorkspaceFailure implements Exception {
  const LocalWorkspaceFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class DesktopPortableBackupPreview {
  const DesktopPortableBackupPreview({
    required this.path,
    required this.businessName,
    required this.ownerName,
    required this.byteLength,
    required this.products,
    required this.customers,
    required this.sales,
  });

  final String path;
  final String businessName;
  final String ownerName;
  final int byteLength;
  final int products;
  final int customers;
  final int sales;
}

class _PinAttemptState {
  const _PinAttemptState({this.failures = 0, this.lockedUntil});

  final int failures;
  final DateTime? lockedUntil;
}

/// Local owner profile and access gate. Business data stays in the local DB;
/// the PIN is stored by the operating system credential store.
class DesktopSession extends ChangeNotifier {
  DesktopSession()
    : _storage = const FlutterSecureStorage(),
      workspace = DesktopWorkspaceStore();

  static const _workspaceReadyKey = 'counterbase_desktop_workspace_ready';
  static const _pinKey = 'counterbase_desktop_owner_pin';
  static const _pinVerifierKey = 'counterbase_desktop_owner_pin_verifier_v1';
  static const _pinAttemptsKey = 'counterbase_desktop_pin_attempts_v1';
  static const _deviceIdKey = 'counterbase_desktop_device_id';
  static const _axonGatewayKey = 'counterbase_axon_gateway_api_key';
  static const _databaseKey = 'counterbase_desktop_database_key';

  final DesktopWorkspaceStore workspace;
  final FlutterSecureStorage _storage;
  bool _initializing = true;
  bool _authenticated = false;
  bool _hasWorkspace = false;
  String? _deviceId;
  String? _ownerName;
  String? _businessName;
  String? _initializationError;

  bool get initializing => _initializing;
  bool get authenticated => _authenticated;
  bool get hasWorkspace => _hasWorkspace;
  String? get initializationError => _initializationError;
  String get displayName => _ownerName ?? 'Owner';
  String get businessName => _businessName ?? 'Counterbase';
  String get deviceId => _deviceId ?? '';
  String get branchId => localWorkspaceBranchId;
  Map<String, dynamic> get user => const {'role': 'Workspace owner'};

  Future<bool> hasAxonGatewayKey() async =>
      (await _storage.read(key: _axonGatewayKey))?.trim().isNotEmpty == true;

  Future<String?> getAxonGatewayKey() async {
    final value = await _storage.read(key: _axonGatewayKey);
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<void> saveAxonGatewayKey(String value) async {
    final key = value.trim();
    if (key.isEmpty) {
      throw const LocalWorkspaceFailure('Enter the Axon Gateway key first.');
    }
    await _storage.write(key: _axonGatewayKey, value: key);
  }

  Future<void> removeAxonGatewayKey() async {
    await _storage.delete(key: _axonGatewayKey);
  }

  Future<void> initialize() async {
    try {
      final databaseKey = await _loadOrCreateDatabaseKey();
      await workspace.initialize(databaseKey: databaseKey);
      _deviceId = await _storage.read(key: _deviceIdKey);
      _deviceId ??= const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: _deviceId);

      _businessName = await workspace.getSetting('business_name');
      _ownerName = await workspace.getSetting('owner_name');
      final ready = await _storage.read(key: _workspaceReadyKey) == '1';
      final hasPinCredential = await _hasPinCredential();
      _hasWorkspace = ready && hasPinCredential;
      if (ready && (_businessName == null || _ownerName == null)) {
        _initializationError =
            'The saved workspace profile is missing. Do not create a new workspace over the existing data; restore its database or contact support.';
        _hasWorkspace = false;
      } else if (ready && !hasPinCredential) {
        _initializationError =
            'The saved owner PIN credential is missing. Your encrypted shop data was left untouched. Restore a backup or contact support; do not set up a new workspace on this computer.';
        _hasWorkspace = false;
      }
    } on LocalWorkspaceFailure catch (error) {
      _initializationError = error.message;
      _hasWorkspace = false;
    } catch (error) {
      debugPrint('[DesktopWorkspace] Safe open failed: $error');
      _initializationError =
          'Counterbase could not safely open this computer’s local workspace. Your saved records were left untouched. Check that the operating system credential store is available, then try again.';
      _hasWorkspace = false;
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<String> _loadOrCreateDatabaseKey() async {
    var key = await _storage.read(key: _databaseKey);
    if (key != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const LocalWorkspaceFailure(
        'The secure database key is invalid. Do not reset this workspace; contact support.',
      );
    }
    if (key == null) {
      key = List<int>.generate(
        32,
        (_) => math.Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      await _storage.write(key: _databaseKey, value: key);
    }
    return key;
  }

  Future<void> createWorkspace({
    required String businessName,
    required String ownerName,
    required String pin,
  }) async {
    final business = businessName.trim();
    final owner = ownerName.trim();
    if (business.length < 2 || owner.length < 2) {
      throw const LocalWorkspaceFailure(
        'Enter your business name and your name.',
      );
    }
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw const LocalWorkspaceFailure('Choose a six-digit owner PIN.');
    }

    await workspace.saveWorkspaceProfile(
      businessName: business,
      ownerName: owner,
    );
    await _writePinVerifier(pin);
    // Set the ready marker last so a partial setup can safely be retried.
    await _storage.write(key: _workspaceReadyKey, value: '1');
    _businessName = business;
    _ownerName = owner;
    _hasWorkspace = true;
    _authenticated = true;
    notifyListeners();
  }

  Future<void> login(String pin) async {
    final attemptState = await _readPinAttempts();
    final lockedUntil = attemptState.lockedUntil;
    final now = DateTime.now().toUtc();
    if (lockedUntil != null && lockedUntil.isAfter(now)) {
      final seconds = lockedUntil.difference(now).inSeconds + 1;
      throw LocalWorkspaceFailure(
        'Too many incorrect PIN attempts. Try again in $seconds seconds.',
      );
    }

    final matches = await _verifyPin(pin);
    if (!matches) {
      final failedAttempts = attemptState.failures + 1;
      final lockoutSeconds = math
          .min(900, 30 * (1 << (failedAttempts - 5).clamp(0, 5)))
          .toInt();
      final lockout = failedAttempts < 5
          ? null
          : now.add(Duration(seconds: lockoutSeconds));
      await _writePinAttempts(failedAttempts, lockout);
      if (lockout != null) {
        throw LocalWorkspaceFailure(
          'Too many incorrect PIN attempts. Try again in $lockoutSeconds seconds.',
        );
      }
      throw const LocalWorkspaceFailure('That PIN is not correct. Try again.');
    }

    // Upgrade older desktop installs on the first successful login. The old
    // verifier stored the six-digit PIN directly in the OS credential store.
    if (await _storage.read(key: _pinVerifierKey) == null) {
      await _writePinVerifier(pin);
      await _storage.delete(key: _pinKey);
    }
    await _clearPinAttempts();
    _authenticated = true;
    notifyListeners();
  }

  Future<bool> _hasPinCredential() async {
    final verifier = await _storage.read(key: _pinVerifierKey);
    if (verifier != null && verifier.isNotEmpty) return true;
    final legacyPin = await _storage.read(key: _pinKey);
    return legacyPin != null && RegExp(r'^\d{6}$').hasMatch(legacyPin);
  }

  Future<void> _writePinVerifier(String pin) async {
    final random = math.Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final derived = await Pbkdf2.hmacSha256(
      iterations: 310000,
      bits: 256,
    ).deriveKeyFromPassword(password: pin, nonce: salt);
    final hash = await derived.extractBytes();
    final verifier = <String, dynamic>{
      'version': 1,
      'iterations': 310000,
      'salt': base64Url.encode(salt),
      'hash': hash.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
    };
    await _storage.write(key: _pinVerifierKey, value: jsonEncode(verifier));
  }

  Future<bool> _verifyPin(String pin) async {
    final savedVerifier = await _storage.read(key: _pinVerifierKey);
    if (savedVerifier == null) {
      final legacyPin = await _storage.read(key: _pinKey);
      return legacyPin != null && _constantTimeEquals(pin, legacyPin);
    }

    try {
      final decoded = jsonDecode(savedVerifier);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          decoded['iterations'] != 310000) {
        throw const LocalWorkspaceFailure(
          'The saved PIN verifier is invalid. Do not reset this workspace; contact support.',
        );
      }
      final salt = base64Url.decode(decoded['salt']?.toString() ?? '');
      final expected = decoded['hash']?.toString() ?? '';
      if (salt.length != 16 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
        throw const LocalWorkspaceFailure(
          'The saved PIN verifier is incomplete. Do not reset this workspace; contact support.',
        );
      }
      final derived = await Pbkdf2.hmacSha256(
        iterations: 310000,
        bits: 256,
      ).deriveKeyFromPassword(password: pin, nonce: salt);
      final actual = (await derived.extractBytes())
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      return _constantTimeEquals(actual, expected);
    } on LocalWorkspaceFailure {
      rethrow;
    } catch (_) {
      throw const LocalWorkspaceFailure(
        'The saved PIN verifier could not be read. Do not reset this workspace; contact support.',
      );
    }
  }

  bool _constantTimeEquals(String first, String second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var i = 0; i < first.length; i++) {
      difference |= first.codeUnitAt(i) ^ second.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<_PinAttemptState> _readPinAttempts() async {
    final raw = await _storage.read(key: _pinAttemptsKey);
    if (raw == null) return const _PinAttemptState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const _PinAttemptState();
      final failures = decoded['failures'];
      final lockedUntilMs = decoded['lockedUntilMs'];
      return _PinAttemptState(
        failures: failures is int ? failures.clamp(0, 1000000).toInt() : 0,
        lockedUntil: lockedUntilMs is int && lockedUntilMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(lockedUntilMs, isUtc: true)
            : null,
      );
    } catch (_) {
      // A damaged throttle record must not lock the owner out of their data.
      await _storage.delete(key: _pinAttemptsKey);
      return const _PinAttemptState();
    }
  }

  Future<void> _writePinAttempts(int failures, DateTime? lockedUntil) async {
    await _storage.write(
      key: _pinAttemptsKey,
      value: jsonEncode({
        'failures': failures,
        'lockedUntilMs': lockedUntil?.millisecondsSinceEpoch,
      }),
    );
  }

  Future<void> _clearPinAttempts() => _storage.delete(key: _pinAttemptsKey);

  Future<void> signOut() async {
    _authenticated = false;
    notifyListeners();
  }

  Future<void> refreshWorkspaceProfile() async {
    _businessName = await workspace.getSetting('business_name');
    _ownerName = await workspace.getSetting('owner_name');
    notifyListeners();
  }
}

/// SQLite-backed workspace. The interface is deliberately local-only: it has
/// no HTTP client, API base URL, remote login, or cloud-sync methods.
class DesktopWorkspaceStore {
  Database? _database;
  String? _databasePath;
  String? _databaseEncryptionKey;

  String? get databasePath => _databasePath;

  Future<void> initialize({required String databaseKey}) async {
    if (_database != null) return;
    sqfliteFfiInit();
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'Counterbase'));
    await directory.create(recursive: true);
    _databasePath = p.join(directory.path, 'counterbase.sqlite');
    _databaseEncryptionKey = databaseKey;
    final existingPlaintextDatabase = await _hasPlaintextSqliteHeader(
      File(_databasePath!),
    );
    _database = await databaseFactoryFfi.openDatabase(
      _databasePath!,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (database) async {
          if (existingPlaintextDatabase) {
            // Preserve committed rows in any prior WAL before converting the
            // older plaintext desktop database to SQLCipher in place.
            await database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
            await database.execute('PRAGMA journal_mode = DELETE');
            await database.execute('PRAGMA rekey = "x\'$databaseKey\'"');
          } else {
            // The key must be the first database operation that can read the
            // schema. Keep it in OS secure storage, never in the app package.
            await database.execute('PRAGMA key = "x\'$databaseKey\'"');
          }
          final cipherVersion = await database.rawQuery(
            'PRAGMA cipher_version',
          );
          if (cipherVersion.isEmpty ||
              cipherVersion.first.values.every(
                (value) => value == null || value.toString().trim().isEmpty,
              )) {
            throw const LocalWorkspaceFailure(
              'Database encryption is unavailable. The local shop data was not opened.',
            );
          }
          await database.rawQuery('SELECT count(*) FROM sqlite_master');
          await database.execute('PRAGMA foreign_keys = ON');
          await database.execute('PRAGMA journal_mode = WAL');
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE categories (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL UNIQUE
            )
          ''');
          await database.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              category_id TEXT,
              price REAL NOT NULL CHECK (price >= 0),
              stock REAL NOT NULL DEFAULT 0 CHECK (stock >= 0),
              sku TEXT NOT NULL DEFAULT '',
              min_stock REAL NOT NULL DEFAULT 0 CHECK (min_stock >= 0),
              unit TEXT NOT NULL DEFAULT 'piece',
              image_url TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              FOREIGN KEY (category_id) REFERENCES categories(id)
                ON DELETE SET NULL
            )
          ''');
          await database.execute(
            "CREATE UNIQUE INDEX products_sku_unique ON products(sku) WHERE sku <> ''",
          );
          await database.execute('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT NOT NULL DEFAULT '',
              phone TEXT NOT NULL DEFAULT '',
              address TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE sales (
              id TEXT PRIMARY KEY,
              receipt_number TEXT NOT NULL UNIQUE,
              created_at TEXT NOT NULL,
              payment_method TEXT NOT NULL,
              total REAL NOT NULL CHECK (total >= 0),
              discount REAL NOT NULL DEFAULT 0,
              customer_id TEXT,
              FOREIGN KEY (customer_id) REFERENCES customers(id)
                ON DELETE SET NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE sale_items (
              id TEXT PRIMARY KEY,
              sale_id TEXT NOT NULL,
              product_id TEXT,
              product_name TEXT NOT NULL,
              quantity REAL NOT NULL CHECK (quantity > 0),
              unit_price REAL NOT NULL CHECK (unit_price >= 0),
              line_total REAL NOT NULL CHECK (line_total >= 0),
              FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
              FOREIGN KEY (product_id) REFERENCES products(id)
                ON DELETE SET NULL
            )
          ''');
          await database.execute(
            'CREATE INDEX sales_created_at_idx ON sales(created_at)',
          );
          await database.execute(
            'CREATE INDEX sale_items_sale_id_idx ON sale_items(sale_id)',
          );
          await database.execute('''
            CREATE TABLE local_import_archives (
              archive_id TEXT PRIMARY KEY,
              tenant_id TEXT NOT NULL,
              tenant_name TEXT NOT NULL,
              imported_at TEXT NOT NULL,
              record_count INTEGER NOT NULL,
              payload_json TEXT
            )
          ''');
          await database.insert('categories', {
            'id': const Uuid().v4(),
            'name': 'General',
          });
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await database.execute('''
              CREATE TABLE IF NOT EXISTS local_import_archives (
                archive_id TEXT PRIMARY KEY,
                tenant_id TEXT NOT NULL,
                tenant_name TEXT NOT NULL,
                imported_at TEXT NOT NULL,
                record_count INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 3) {
            await database.execute(
              'ALTER TABLE local_import_archives ADD COLUMN payload_json TEXT',
            );
          }
        },
      ),
    );
  }

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

  Future<bool> _hasPlaintextSqliteHeader(File file) async {
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

  Database get _db {
    final database = _database;
    if (database == null) {
      throw const LocalWorkspaceFailure('The local workspace is not ready.');
    }
    return database;
  }

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<List<Map<String, dynamic>>> getImportedArchiveHistory() async {
    final rows = await _db.query(
      'local_import_archives',
      columns: [
        'archive_id',
        'tenant_name',
        'imported_at',
        'record_count',
        'payload_json',
      ],
      orderBy: 'imported_at DESC',
    );
    return rows
        .map((row) {
          final payloadText = row['payload_json']?.toString();
          final counts = <String, int>{};
          if (payloadText != null && payloadText.isNotEmpty) {
            try {
              final payload = jsonDecode(payloadText);
              if (payload is Map) {
                for (final entry in payload.entries) {
                  if (entry.key == 'tenant' || entry.value is! List) continue;
                  counts[entry.key.toString()] = (entry.value as List).length;
                }
              }
            } catch (_) {
              // Preserve the archive record even if older imported JSON is damaged.
            }
          }
          return <String, dynamic>{
            'archiveId': row['archive_id'],
            'tenantName': row['tenant_name'],
            'importedAt': row['imported_at'],
            'recordCount': row['record_count'],
            'hasPreservedPayload': counts.isNotEmpty,
            'sectionCounts': counts,
          };
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> getImportedArchivePayload(
    String archiveId,
  ) async {
    final rows = await _db.query(
      'local_import_archives',
      columns: ['payload_json'],
      where: 'archive_id = ?',
      whereArgs: [archiveId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payloadText = rows.first['payload_json']?.toString();
    if (payloadText == null || payloadText.isEmpty) return null;
    final decoded = jsonDecode(payloadText);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> saveWorkspaceProfile({
    required String businessName,
    required String ownerName,
  }) async {
    await _db.transaction((txn) async {
      await txn.insert('settings', {
        'key': 'business_name',
        'value': businessName,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('settings', {
        'key': 'owner_name',
        'value': ownerName,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, dynamic>>> getCategories() async => (await _db.query(
    'categories',
    orderBy: 'name COLLATE NOCASE',
  )).map(Map<String, dynamic>.from).toList();

  Future<List<Map<String, dynamic>>> getProducts({
    String? branchId,
    String? categoryId,
    String? search,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, c.name AS category_name
      FROM products p LEFT JOIN categories c ON c.id = p.category_id
      WHERE p.is_active = 1
        AND (? IS NULL OR p.category_id = ?)
        AND (? IS NULL OR p.name LIKE ? OR p.sku LIKE ?)
      ORDER BY p.name COLLATE NOCASE
    ''',
      [
        categoryId,
        categoryId,
        search?.trim().isEmpty ?? true ? null : search!.trim(),
        '%${search?.trim() ?? ''}%',
        '%${search?.trim() ?? ''}%',
      ],
    );
    return rows.map(_productJson).toList();
  }

  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> payload,
  ) async {
    final name = _requiredText(payload['name'], 'Enter a product name.');
    final price = _number(payload['basePrice'] ?? payload['price']);
    final stock = _number(payload['initialStock']);
    final minimum = _number(payload['minStock']);
    if (price < 0 || stock < 0 || minimum < 0) {
      throw const LocalWorkspaceFailure(
        'Price and stock values cannot be negative.',
      );
    }
    final categoryId = _categoryId(payload);
    final id = const Uuid().v4();
    try {
      await _db.insert('products', {
        'id': id,
        'name': name,
        'category_id': categoryId,
        'price': price,
        'stock': stock,
        'sku': payload['sku']?.toString().trim() ?? '',
        'min_stock': minimum,
        'unit': payload['unit']?.toString().trim().isNotEmpty == true
            ? payload['unit'].toString().trim()
            : 'piece',
        'image_url': payload['image']?.toString(),
        'created_at': DateTime.now().toIso8601String(),
      });
    } on DatabaseException catch (error) {
      throw LocalWorkspaceFailure(_databaseMessage(error));
    }
    return (await _productById(id))!;
  }

  Future<Map<String, dynamic>> updateProduct(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final existing = await _productById(id);
    if (existing == null) {
      throw const LocalWorkspaceFailure('Product not found.');
    }
    final updates = <String, Object?>{};
    if (payload.containsKey('name')) {
      updates['name'] = _requiredText(payload['name'], 'Enter a product name.');
    }
    if (payload.containsKey('basePrice') || payload.containsKey('price')) {
      final price = _number(payload['basePrice'] ?? payload['price']);
      if (price < 0) {
        throw const LocalWorkspaceFailure('Price cannot be negative.');
      }
      updates['price'] = price;
    }
    if (payload.containsKey('minStock')) {
      final minimum = _number(payload['minStock']);
      if (minimum < 0) {
        throw const LocalWorkspaceFailure('Stock level cannot be negative.');
      }
      updates['min_stock'] = minimum;
    }
    if (payload.containsKey('sku')) {
      updates['sku'] = payload['sku']?.toString().trim() ?? '';
    }
    if (payload.containsKey('unit')) {
      updates['unit'] = payload['unit']?.toString().trim();
    }
    if (payload.containsKey('image')) {
      updates['image_url'] = payload['image']?.toString();
    }
    if (payload.containsKey('categoryIds')) {
      updates['category_id'] = _categoryId(payload);
    }
    if (updates.isEmpty) return existing;
    try {
      await _db.update('products', updates, where: 'id = ?', whereArgs: [id]);
    } on DatabaseException catch (error) {
      throw LocalWorkspaceFailure(_databaseMessage(error));
    }
    return (await _productById(id))!;
  }

  Future<void> deleteProduct(String id) async {
    await _db.update(
      'products',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getCustomers() async => (await _db.query(
    'customers',
    orderBy: 'name COLLATE NOCASE',
  )).map(Map<String, dynamic>.from).toList();

  Future<Map<String, dynamic>> createCustomer(
    Map<String, dynamic> payload,
  ) async {
    final id = const Uuid().v4();
    await _db.insert('customers', {
      'id': id,
      'name': _requiredText(payload['name'], 'Enter a customer name.'),
      'email': payload['email']?.toString().trim() ?? '',
      'phone': payload['phone']?.toString().trim() ?? '',
      'address': payload['address']?.toString().trim() ?? '',
      'created_at': DateTime.now().toIso8601String(),
    });
    return (await _customerById(id))!;
  }

  Future<Map<String, dynamic>> updateCustomer(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final updates = <String, Object?>{};
    if (payload.containsKey('name')) {
      updates['name'] = _requiredText(
        payload['name'],
        'Enter a customer name.',
      );
    }
    for (final key in ['email', 'phone', 'address']) {
      if (payload.containsKey(key)) {
        updates[key] = payload[key]?.toString().trim() ?? '';
      }
    }
    if (updates.isNotEmpty) {
      await _db.update('customers', updates, where: 'id = ?', whereArgs: [id]);
    }
    final customer = await _customerById(id);
    if (customer == null) {
      throw const LocalWorkspaceFailure('Customer not found.');
    }
    return customer;
  }

  Future<void> deleteCustomer(String id) async {
    await _db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<({bool alreadyImported, int recordCount})> importLegacyArchive({
    required Map<String, dynamic> payload,
    required String archiveId,
  }) async {
    final tenant = Map<String, dynamic>.from(payload['tenant'] as Map);
    final tenantId = _requiredArchiveText(tenant['id'], 'shop id');
    final tenantName = _requiredArchiveText(tenant['name'], 'shop name');
    final branches = _archiveMaps(payload['branches']);
    if (branches.isEmpty) {
      throw const LocalWorkspaceFailure(
        'The archive does not contain a shop branch.',
      );
    }
    final products = _archiveMaps(payload['products']);
    final categories = _archiveMaps(payload['categories']);
    final productCategories = _archiveMaps(payload['productCategories']);
    final customers = _archiveMaps(payload['customers']);
    final sales = _archiveMaps(payload['sales']);
    final saleItems = _archiveMaps(payload['saleItems']);
    final stock = _archiveMaps(payload['stock']);
    final saleIds = sales.map((row) => row['id']?.toString()).toSet();
    final productIds = products.map((row) => row['id']?.toString()).toSet();
    final customerIds = customers.map((row) => row['id']?.toString()).toSet();
    for (final sale in sales) {
      if (!_archiveBranchExists(branches, sale['branchId'])) {
        throw const LocalWorkspaceFailure(
          'A sale refers to a branch missing from this archive.',
        );
      }
    }
    for (final item in saleItems) {
      if (!saleIds.contains(item['saleId']?.toString())) {
        throw const LocalWorkspaceFailure(
          'A sale item refers to a missing receipt.',
        );
      }
    }
    for (final row in stock) {
      if (!productIds.contains(row['productId']?.toString()) ||
          !_archiveBranchExists(branches, row['branchId'])) {
        throw const LocalWorkspaceFailure(
          'Stock refers to a missing product or shop branch.',
        );
      }
    }

    var alreadyImported = false;
    var importedRecordCount = 0;
    await _db.transaction((txn) async {
      final existingArchive = await txn.query(
        'local_import_archives',
        columns: ['archive_id'],
        where: 'archive_id = ?',
        whereArgs: [archiveId],
        limit: 1,
      );
      if (existingArchive.isNotEmpty) {
        await txn.update(
          'local_import_archives',
          {'payload_json': jsonEncode(payload)},
          where:
              'archive_id = ? AND (payload_json IS NULL OR length(payload_json) = 0)',
          whereArgs: [archiveId],
        );
        alreadyImported = true;
        return;
      }

      final businessRows = await txn.rawQuery('''
        SELECT
          (SELECT COUNT(*) FROM products) +
          (SELECT COUNT(*) FROM customers) +
          (SELECT COUNT(*) FROM sales) +
          (SELECT COUNT(*) FROM sale_items) AS row_count
      ''');
      final hasBusinessData = (businessRows.single['row_count'] as int) > 0;
      final savedTenantRows = await txn.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['archive_tenant_id'],
        limit: 1,
      );
      final savedTenantId = savedTenantRows.isEmpty
          ? null
          : savedTenantRows.first['value']?.toString();
      if (savedTenantId != tenantId && hasBusinessData) {
        throw const LocalWorkspaceFailure(
          'This computer already contains another shop’s records. Restore this archive on a new, empty Counterbase workspace.',
        );
      }
      if (savedTenantId == null && hasBusinessData) {
        throw const LocalWorkspaceFailure(
          'This workspace already has records and is not linked to this archive. Create a new local workspace before restoring it.',
        );
      }

      await txn.insert('settings', {
        'key': 'archive_tenant_id',
        'value': tenantId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (savedTenantId != tenantId) {
        await txn.insert('settings', {
          'key': 'business_name',
          'value': tenantName,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final categoryIdByArchiveId = <String, String>{};
      for (final row in categories) {
        final id = _requiredArchiveText(row['id'], 'category id');
        final name = _requiredArchiveText(row['name'], 'category name');
        final byId = await txn.query(
          'categories',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (byId.isNotEmpty) {
          categoryIdByArchiveId[id] = id;
          continue;
        }
        final byName = await txn.query(
          'categories',
          columns: ['id'],
          where: 'name = ?',
          whereArgs: [name],
          limit: 1,
        );
        if (byName.isNotEmpty) {
          categoryIdByArchiveId[id] = byName.first['id'].toString();
          continue;
        }
        await txn.insert('categories', {
          'id': id,
          'name': name,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        categoryIdByArchiveId[id] = id;
      }
      final generalRows = await txn.query(
        'categories',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: ['General'],
        limit: 1,
      );
      final defaultCategoryId = generalRows.isNotEmpty
          ? generalRows.first['id'].toString()
          : const Uuid().v4();
      if (generalRows.isEmpty) {
        await txn.insert('categories', {
          'id': defaultCategoryId,
          'name': 'General',
        });
      }

      final categoryForProduct = <String, String>{};
      for (final row in productCategories) {
        final productId = row['productId']?.toString() ?? '';
        final categoryId = row['categoryId']?.toString() ?? '';
        if (productId.isNotEmpty &&
            categoryIdByArchiveId.containsKey(categoryId)) {
          categoryForProduct.putIfAbsent(
            productId,
            () => categoryIdByArchiveId[categoryId]!,
          );
        }
      }

      final stockByProduct = <String, double>{};
      for (final row in stock) {
        final productId = row['productId']?.toString() ?? '';
        final quantity = _archiveNumber(row['quantity']);
        if (quantity < 0) {
          throw const LocalWorkspaceFailure(
            'The archive contains negative on-hand stock. Correct it before importing.',
          );
        }
        stockByProduct.update(
          productId,
          (current) => current + quantity,
          ifAbsent: () => quantity,
        );
      }
      for (final row in products) {
        final id = _requiredArchiveText(row['id'], 'product id');
        final existing = await txn.query(
          'products',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        var sku = _archiveText(row['sku']);
        if (sku.isEmpty) sku = id;
        final baseSku = sku;
        final suffixLength = id.length < 6 ? id.length : 6;
        var skuSuffix = 1;
        while ((await txn.query(
          'products',
          columns: ['id'],
          where: 'sku = ? AND id <> ?',
          whereArgs: [sku, id],
          limit: 1,
        )).isNotEmpty) {
          sku = '$baseSku-${id.substring(0, suffixLength)}-$skuSuffix';
          skuSuffix += 1;
        }
        final price = _archiveNumber(row['basePrice']);
        if (price < 0) {
          throw const LocalWorkspaceFailure(
            'The archive contains a negative product price. Correct it before importing.',
          );
        }
        await txn.insert('products', {
          'id': id,
          'name': _requiredArchiveText(row['name'], 'product name'),
          'category_id': categoryForProduct[id] ?? defaultCategoryId,
          'price': price,
          'stock': stockByProduct[id] ?? 0,
          'sku': sku,
          'min_stock': _archiveNumber(row['minStock']),
          'unit': _archiveText(row['unit']).isEmpty
              ? 'piece'
              : _archiveText(row['unit']),
          'image_url': null,
          'is_active': _archiveBool(row['isActive'], true) ? 1 : 0,
          'created_at': _archiveDate(row['createdAt']),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      for (final row in customers) {
        final id = _requiredArchiveText(row['id'], 'customer id');
        await txn.insert('customers', {
          'id': id,
          'name': _requiredArchiveText(row['name'], 'customer name'),
          'email': _archiveText(row['email']),
          'phone': _archiveText(row['phone']),
          'address': _archiveText(row['address']),
          'created_at': _archiveDate(row['createdAt']),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      final importedSaleIds = <String>{};
      final receiptNumbers = <String>{};
      for (final row in sales) {
        if ((_archiveText(row['status']).toUpperCase()) != 'COMPLETED') {
          continue;
        }
        final id = _requiredArchiveText(row['id'], 'sale id');
        final existing = await txn.query(
          'sales',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        final branchCode = _archiveBranchCode(branches, row['branchId']);
        final sourceReceiptNumber = _archiveText(row['receiptNumber']);
        final receiptBase = sourceReceiptNumber.isEmpty
            ? 'ARCH-${id.substring(0, 8)}'
            : sourceReceiptNumber;
        var receiptNumber = receiptBase;
        var suffix = 1;
        while (receiptNumbers.contains(receiptNumber) ||
            (await txn.query(
              'sales',
              columns: ['id'],
              where: 'receipt_number = ?',
              whereArgs: [receiptNumber],
              limit: 1,
            )).isNotEmpty) {
          final branchSuffix = branchCode.isEmpty
              ? id.substring(0, 6)
              : branchCode;
          receiptNumber = '$receiptBase-$branchSuffix-$suffix';
          suffix += 1;
        }
        receiptNumbers.add(receiptNumber);
        final customerId = row['customerId']?.toString();
        final customerExists =
            customerId != null && customerIds.contains(customerId);
        await txn.insert('sales', {
          'id': id,
          'receipt_number': receiptNumber,
          'created_at': _archiveDate(row['createdAt']),
          'payment_method': _archiveText(row['paymentMethod']).isEmpty
              ? 'OTHER'
              : _archiveText(row['paymentMethod']).toUpperCase(),
          'total': _archiveNumber(row['totalAmount']),
          'discount': _archiveNumber(row['discountAmount']),
          'customer_id': customerExists ? customerId : null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        importedSaleIds.add(id);
      }

      for (final row in saleItems) {
        final saleId = row['saleId']?.toString() ?? '';
        if (!importedSaleIds.contains(saleId)) continue;
        final id = _requiredArchiveText(row['id'], 'sale item id');
        final sourceProductId = row['productId']?.toString();
        final existingProduct = sourceProductId == null
            ? const <Map<String, Object?>>[]
            : await txn.query(
                'products',
                columns: ['id'],
                where: 'id = ?',
                whereArgs: [sourceProductId],
                limit: 1,
              );
        final productExists = existingProduct.isNotEmpty;
        final quantity = _archiveNumber(row['quantity']);
        final unitPrice = _archiveNumber(row['unitPrice']);
        final lineTotal = _archiveNumber(row['totalAmount']);
        if (quantity <= 0 || unitPrice < 0 || lineTotal < 0) {
          throw const LocalWorkspaceFailure(
            'The archive contains an invalid sale item. Correct it before importing.',
          );
        }
        await txn.insert('sale_items', {
          'id': id,
          'sale_id': saleId,
          'product_id': productExists ? sourceProductId : null,
          'product_name': _requiredArchiveText(
            row['productName'],
            'sale item name',
          ),
          'quantity': quantity,
          'unit_price': unitPrice,
          'line_total': lineTotal,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      importedRecordCount =
          products.length +
          categories.length +
          customers.length +
          importedSaleIds.length +
          saleItems.length;
      await txn.insert('local_import_archives', {
        'archive_id': archiveId,
        'tenant_id': tenantId,
        'tenant_name': tenantName,
        'imported_at': DateTime.now().toUtc().toIso8601String(),
        'record_count': importedRecordCount,
        'payload_json': jsonEncode(payload),
      });
    });
    return (alreadyImported: alreadyImported, recordCount: importedRecordCount);
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> payload) async {
    final rawItems = payload['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw const LocalWorkspaceFailure(
        'Add at least one product before completing a sale.',
      );
    }
    final saleId = const Uuid().v4();
    final now = DateTime.now();
    final receiptNumber =
        'CB-${now.year}${_two(now.month)}${_two(now.day)}-${const Uuid().v4().substring(0, 6).toUpperCase()}';
    final items = <Map<String, dynamic>>[];
    var total = 0.0;

    await _db.transaction((txn) async {
      for (final raw in rawItems) {
        if (raw is! Map) {
          throw const LocalWorkspaceFailure('Sale item is invalid.');
        }
        final item = Map<String, dynamic>.from(raw);
        final productId = item['productId']?.toString();
        if (productId == null || productId.isEmpty) {
          throw const LocalWorkspaceFailure(
            'A sale item is missing its product.',
          );
        }
        final rows = await txn.query(
          'products',
          where: 'id = ? AND is_active = 1',
          whereArgs: [productId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const LocalWorkspaceFailure(
            'A product is no longer available.',
          );
        }
        final product = rows.first;
        final quantity = _number(item['quantity']);
        final stock = _number(product['stock']);
        if (!quantity.isFinite || quantity <= 0) {
          throw const LocalWorkspaceFailure(
            'Sale quantities must be above zero.',
          );
        }
        if (!stock.isFinite || stock < 0) {
          throw const LocalWorkspaceFailure(
            'This product has an invalid stock count. Review its inventory before selling.',
          );
        }
        if (stock < quantity) {
          throw LocalWorkspaceFailure(
            'Not enough ${product['name']} in stock. Available: ${_formatQuantity(stock)}.',
          );
        }
        // Use the stored price as the checkout authority so a stale cart cannot
        // charge an old price after the product was edited elsewhere.
        final unitPrice = _number(product['price']);
        if (!unitPrice.isFinite || unitPrice < 0) {
          throw const LocalWorkspaceFailure(
            'This product has an invalid sale price. Review it before selling.',
          );
        }
        final lineTotal = quantity * unitPrice;
        if (!lineTotal.isFinite || !(total + lineTotal).isFinite) {
          throw const LocalWorkspaceFailure(
            'The sale total is outside the supported amount range.',
          );
        }
        total += lineTotal;
        final saleItemId = const Uuid().v4();
        items.add({
          'id': saleItemId,
          'productId': productId,
          'productName': product['name'],
          'quantity': quantity,
          'unitPrice': unitPrice,
          'lineTotal': lineTotal,
        });
        await txn.update(
          'products',
          {'stock': stock - quantity},
          where: 'id = ?',
          whereArgs: [productId],
        );
      }
      final customerId = payload['customerId']?.toString();
      await txn.insert('sales', {
        'id': saleId,
        'receipt_number': receiptNumber,
        'created_at': now.toIso8601String(),
        'payment_method': 'CASH',
        'total': total,
        'discount': _number(payload['discount']),
        'customer_id': customerId?.isEmpty == true ? null : customerId,
      });
      for (final item in items) {
        await txn.insert('sale_items', {
          'id': item['id'],
          'sale_id': saleId,
          'product_id': item['productId'],
          'product_name': item['productName'],
          'quantity': item['quantity'],
          'unit_price': item['unitPrice'],
          'line_total': item['lineTotal'],
        });
      }
    });
    return {
      'id': saleId,
      'receiptNumber': receiptNumber,
      'createdAt': now.toIso8601String(),
      'paymentMethod': 'CASH',
      'total': total,
      'items': items,
    };
  }

  Future<List<Map<String, dynamic>>> getSales({String? branchId}) async {
    final sales = await _db.query(
      'sales',
      orderBy: 'created_at DESC',
      limit: 500,
    );
    final result = <Map<String, dynamic>>[];
    for (final sale in sales) {
      final items = await _db.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [sale['id']],
        orderBy: 'rowid',
      );
      result.add({
        ...sale,
        'receiptNumber': sale['receipt_number'],
        'createdAt': sale['created_at'],
        'paymentMethod': sale['payment_method'],
        'items': items
            .map(
              (item) => {
                'productName': item['product_name'],
                'quantity': item['quantity'],
                'unitPrice': item['unit_price'],
                'lineTotal': item['line_total'],
              },
            )
            .toList(),
      });
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getStock(String branchId) async =>
      _db.rawQuery('''
        SELECT id AS productId, name AS productName, stock AS quantity,
               min_stock AS lowStockThreshold, unit
        FROM products WHERE is_active = 1 ORDER BY name COLLATE NOCASE
      ''');

  Future<Map<String, dynamic>> adjustStock(Map<String, dynamic> payload) async {
    final productId = payload['productId']?.toString();
    if (productId == null || productId.isEmpty) {
      throw const LocalWorkspaceFailure('Choose a product to adjust.');
    }
    final amount = _number(payload['quantity'] ?? payload['adjustment']);
    if (amount <= 0) {
      throw const LocalWorkspaceFailure('Enter a quantity above zero.');
    }
    final direction = payload['direction']?.toString().toUpperCase();
    final delta = direction == 'REMOVE' || direction == 'DECREASE'
        ? -amount
        : amount;
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) throw const LocalWorkspaceFailure('Product not found.');
      final current = _number(rows.first['stock']);
      final updated = current + delta;
      if (updated < 0) {
        throw LocalWorkspaceFailure(
          'Only ${_formatQuantity(current)} units are available.',
        );
      }
      await txn.update(
        'products',
        {'stock': updated},
        where: 'id = ?',
        whereArgs: [productId],
      );
      return {'productId': productId, 'quantity': updated, 'delta': delta};
    });
  }

  Future<List<Map<String, dynamic>>> getLowStock(String branchId) async =>
      _db.rawQuery('''
        SELECT id AS productId, name AS productName, stock AS quantity,
               min_stock AS lowStockThreshold, unit
        FROM products WHERE is_active = 1 AND stock <= min_stock
        ORDER BY stock ASC, name COLLATE NOCASE
      ''');

  Future<Map<String, dynamic>> getDashboard({String? branchId}) async {
    final start = _startOfDay(DateTime.now());
    final end = start.add(const Duration(days: 1));
    final saleRows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS total_sales, COALESCE(SUM(total), 0) AS revenue,
             COALESCE(SUM(discount), 0) AS discounts,
             COUNT(DISTINCT customer_id) AS unique_customers
      FROM sales WHERE created_at >= ? AND created_at < ?
    ''',
      [_timestamp(start), _timestamp(end)],
    );
    final itemRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(si.quantity), 0) AS items_sold
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      WHERE s.created_at >= ? AND s.created_at < ?
    ''',
      [_timestamp(start), _timestamp(end)],
    );
    final productRows = await _db.rawQuery('''
      SELECT COUNT(*) AS total_products,
             COALESCE(SUM(price * stock), 0) AS stock_value,
             SUM(CASE WHEN stock <= min_stock THEN 1 ELSE 0 END) AS low_stock
      FROM products WHERE is_active = 1
    ''');
    final sales = saleRows.first;
    final inventory = productRows.first;
    final revenue = _number(sales['revenue']);
    final count = _number(sales['total_sales']);
    return {
      'sales': {
        'netRevenue': revenue,
        'totalRevenue': revenue,
        'totalSales': count,
        'itemsSold': _number(itemRows.first['items_sold']),
        'uniqueCustomers': _number(sales['unique_customers']),
        'averageTicket': count == 0 ? 0 : revenue / count,
        'totalDiscount': _number(sales['discounts']),
      },
      'inventory': {
        'totalProducts': _number(inventory['total_products']),
        'totalStockValue': _number(inventory['stock_value']),
        'lowStockItems': _number(inventory['low_stock']),
      },
    };
  }

  Future<List<Map<String, dynamic>>> getSalesTrend({String? branchId}) async {
    final today = _startOfDay(DateTime.now());
    final firstDay = today.subtract(const Duration(days: 6));
    final rows = await _db.rawQuery(
      '''
      SELECT substr(created_at, 1, 10) AS day,
             COALESCE(SUM(total), 0) AS revenue
      FROM sales WHERE created_at >= ? AND created_at < ?
      GROUP BY day
    ''',
      [_timestamp(firstDay), _timestamp(today.add(const Duration(days: 1)))],
    );
    final byDay = {
      for (final row in rows) row['day'].toString(): _number(row['revenue']),
    };
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return [
      for (var offset = 0; offset < 7; offset++)
        () {
          final date = firstDay.add(Duration(days: offset));
          final dateKey = '${date.year}-${_two(date.month)}-${_two(date.day)}';
          return {
            'date': dateKey,
            'label': labels[date.weekday - 1],
            'revenue': byDay[dateKey] ?? 0,
          };
        }(),
    ];
  }

  Future<List<Map<String, dynamic>>> getTopProducts({String? branchId}) async {
    final start = _startOfDay(DateTime.now());
    final end = start.add(const Duration(days: 1));
    return _db.rawQuery(
      '''
      SELECT si.product_name AS name, SUM(si.quantity) AS quantity,
             SUM(si.line_total) AS revenue
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      WHERE s.created_at >= ? AND s.created_at < ?
      GROUP BY si.product_name
      ORDER BY revenue DESC LIMIT 10
    ''',
      [_timestamp(start), _timestamp(end)],
    );
  }

  Future<List<Map<String, dynamic>>> getTopProductsForPeriod({
    required DateTime from,
    required DateTime to,
    int limit = 10,
  }) async {
    final safeLimit = limit.clamp(1, 20).toInt();
    return _db.rawQuery(
      '''
      SELECT si.product_name AS name, SUM(si.quantity) AS quantity,
             SUM(si.line_total) AS revenue
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      WHERE s.created_at >= ? AND s.created_at < ?
      GROUP BY si.product_name
      ORDER BY quantity DESC, revenue DESC
      LIMIT ?
    ''',
      [_timestamp(from), _timestamp(to), safeLimit],
    );
  }

  Future<List<Map<String, dynamic>>> getPaymentMethods() async => [
    {'id': 'CASH', 'name': 'Cash', 'available': true},
    {'id': 'CREDIT', 'name': 'Customer credit', 'available': true},
  ];

  Future<String> createPortableBackup({required String passphrase}) async {
    _validateBackupPassphrase(passphrase);
    if (_databasePath == null) {
      throw const LocalWorkspaceFailure('The local workspace is not ready.');
    }
    final downloads = await getDownloadsDirectory();
    if (downloads == null) {
      throw const LocalWorkspaceFailure(
        'This computer does not expose a Downloads folder.',
      );
    }
    final now = DateTime.now();
    final name =
        'Counterbase-transfer-${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}${_three(now.millisecond)}-${const Uuid().v4().substring(0, 8)}.cbportable';
    final backupPath = p.join(downloads.path, name);
    final escapedPath = backupPath.replaceAll("'", "''");
    Database? backup;
    try {
      await _db.execute("VACUUM INTO '$escapedPath'");
      final deviceKey = _databaseEncryptionKey;
      if (deviceKey == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(deviceKey)) {
        throw const LocalWorkspaceFailure(
          'The secure database key is unavailable. Restart Counterbase and try again.',
        );
      }
      backup = await databaseFactoryFfi.openDatabase(
        backupPath,
        options: OpenDatabaseOptions(
          onConfigure: (database) async {
            await database.execute('PRAGMA key = "x\'$deviceKey\'"');
            await _requireSqlCipher(database);
            await database.rawQuery('SELECT count(*) FROM sqlite_master');
          },
        ),
      );
      await _requireHealthyDatabase(backup);
      await backup.execute('PRAGMA rekey = ${_sqliteString(passphrase)}');
      await backup.close();
      backup = null;

      final verification = await _openEncryptedDatabase(
        backupPath,
        passphrase,
        readOnly: true,
      );
      try {
        await _requireHealthyDatabase(verification);
        await _readBackupPreview(verification, backupPath);
      } finally {
        await verification.close();
      }
    } catch (error) {
      await backup?.close();
      final partialBackup = File(backupPath);
      if (await partialBackup.exists()) await partialBackup.delete();
      if (error is LocalWorkspaceFailure) rethrow;
      debugPrint('[DesktopWorkspace] Portable backup failed: $error');
      throw const LocalWorkspaceFailure(
        'The encrypted transfer backup could not be created or verified. Try again.',
      );
    }
    return backupPath;
  }

  /// Creates the shared encrypted JSON transfer accepted by mobile and
  /// desktop. The desktop schema is intentionally smaller than mobile, so the
  /// export contains the common operational records supported on both sides.
  Future<String> createCrossPlatformArchive({
    required String passphrase,
  }) async {
    _validateBackupPassphrase(passphrase);
    await _requireHealthyDatabase(_db);
    final downloads = await getDownloadsDirectory();
    if (downloads == null) {
      throw const LocalWorkspaceFailure(
        'This computer does not expose a Downloads folder.',
      );
    }
    final settingsRows = await _db.query('settings', columns: ['key', 'value']);
    final settings = {
      for (final row in settingsRows)
        row['key'].toString(): row['value']?.toString() ?? '',
    };
    final businessName = settings['business_name']?.trim() ?? '';
    if (businessName.length < 2) {
      throw const LocalWorkspaceFailure(
        'The local shop profile is incomplete. Reopen the workspace and try again.',
      );
    }
    var tenantId = settings['archive_tenant_id']?.trim() ?? '';
    if (tenantId.isEmpty) {
      tenantId = const Uuid().v4();
      await _db.insert('settings', {
        'key': 'archive_tenant_id',
        'value': tenantId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    final createdAt = DateTime.now().toUtc().toIso8601String();
    final categories = await _db.query('categories', orderBy: 'name');
    final products = await _db.query('products', orderBy: 'name');
    final customers = await _db.query('customers', orderBy: 'name');
    final sales = await _db.query('sales', orderBy: 'created_at');
    final saleItems = await _db.query('sale_items', orderBy: 'rowid');
    final categoryIds = categories.map((row) => row['id']?.toString()).toSet();
    final productIds = products.map((row) => row['id']?.toString()).toSet();
    final customerIds = customers.map((row) => row['id']?.toString()).toSet();
    final lineTotalsBySale = <String, double>{};
    for (final item in saleItems) {
      final saleId = item['sale_id']?.toString() ?? '';
      lineTotalsBySale.update(
        saleId,
        (total) => total + _number(item['line_total']),
        ifAbsent: () => _number(item['line_total']),
      );
    }

    final archiveProducts = products
        .map(
          (row) => <String, dynamic>{
            'id': row['id'],
            'sku': row['sku'],
            'name': row['name'],
            'basePrice': row['price'],
            'minStock': row['min_stock'],
            'unit': row['unit'],
            'isActive': row['is_active'] == 1,
            'trackInventory': true,
            'allowFractions': true,
            'createdAt': row['created_at'],
            'updatedAt': row['created_at'],
          },
        )
        .toList(growable: false);
    final archiveStock = products
        .where((row) => (row['stock'] as num?)?.toDouble().isFinite ?? false)
        .map(
          (row) => <String, dynamic>{
            'id': 'desktop-stock-${row['id']}',
            'productId': row['id'],
            'branchId': localWorkspaceBranchId,
            'quantity': (row['stock'] as num).toDouble(),
          },
        )
        .toList(growable: false);
    final archiveSales = sales
        .map((row) {
          final id = row['id']?.toString() ?? '';
          final total = _number(row['total']);
          final discount = _number(row['discount']);
          final subtotal = lineTotalsBySale[id] ?? total + discount;
          return <String, dynamic>{
            'id': row['id'],
            'receiptNumber': row['receipt_number'],
            'createdAt': row['created_at'],
            'paymentMethod': row['payment_method'],
            'subtotal': subtotal,
            'totalAmount': total,
            'discountAmount': discount,
            'taxAmount': total - subtotal + discount,
            'customerId': customerIds.contains(row['customer_id']?.toString())
                ? row['customer_id']
                : null,
            'branchId': localWorkspaceBranchId,
            'status': 'COMPLETED',
          };
        })
        .toList(growable: false);
    final archiveSaleIds = archiveSales
        .map((row) => row['id']?.toString())
        .toSet();
    final archiveSaleItems = saleItems
        .where((row) => archiveSaleIds.contains(row['sale_id']?.toString()))
        .map((row) {
          final quantity = _number(row['quantity']);
          final unitPrice = _number(row['unit_price']);
          final lineTotal = _number(row['line_total']);
          final gross = quantity * unitPrice;
          final discount = gross.isFinite && gross > lineTotal
              ? gross - lineTotal
              : 0.0;
          return <String, dynamic>{
            'id': row['id'],
            'saleId': row['sale_id'],
            'productId': productIds.contains(row['product_id']?.toString())
                ? row['product_id']
                : null,
            'productName': row['product_name'],
            'quantity': quantity,
            'unitPrice': unitPrice,
            'discount': discount,
            'totalAmount': lineTotal,
          };
        })
        .toList(growable: false);
    final payload = <String, dynamic>{
      'tenant': {
        'id': tenantId,
        'name': businessName,
        'slug': _archiveSlug(businessName),
      },
      'branches': [
        {
          'id': localWorkspaceBranchId,
          'name': 'Main branch',
          'code': 'MAIN',
          'address': '',
          'phone': '',
          'isActive': true,
          'isPrimary': true,
          'createdAt': createdAt,
        },
      ],
      'users': const <dynamic>[],
      'categories': categories
          .map(
            (row) => {
              'id': row['id'],
              'name': row['name'],
              'description': '',
              'sortOrder': 0,
              'isActive': true,
              'createdAt': createdAt,
              'updatedAt': createdAt,
            },
          )
          .toList(growable: false),
      'products': archiveProducts,
      'productCategories': products
          .where((row) => categoryIds.contains(row['category_id']?.toString()))
          .map(
            (row) => {'productId': row['id'], 'categoryId': row['category_id']},
          )
          .toList(growable: false),
      'pricingTiers': const <dynamic>[],
      'customers': customers
          .map(
            (row) => {
              'id': row['id'],
              'name': row['name'],
              'email': row['email'] ?? '',
              'phone': row['phone'] ?? '',
              'address': row['address'] ?? '',
              'isActive': true,
              'createdAt': row['created_at'],
            },
          )
          .toList(growable: false),
      'suppliers': const <dynamic>[],
      'supplierInvoices': const <dynamic>[],
      'supplierInvoiceItems': const <dynamic>[],
      'supplierPayments': const <dynamic>[],
      'sales': archiveSales,
      'saleItems': archiveSaleItems,
      'stock': archiveStock,
      'stockBatches': const <dynamic>[],
      'stockMovements': const <dynamic>[],
      'payments': const <dynamic>[],
      'retailReceivables': const <dynamic>[],
      'retailReceivablePayments': const <dynamic>[],
      'stockCounts': const <dynamic>[],
      'stockCountLines': const <dynamic>[],
    };
    final plaintextText = jsonEncode(payload);
    final plaintext = utf8.encode(plaintextText);
    if (plaintext.length > 45 * 1024 * 1024) {
      throw const LocalWorkspaceFailure(
        'This shop is too large for a cross-platform transfer file. Use the full encrypted device backup instead.',
      );
    }

    final random = math.Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));
    final saltText = base64Encode(salt);
    final nonceText = base64Encode(nonce);
    final archiveCreatedAt = DateTime.now().toUtc().toIso8601String();
    final aad = utf8.encode(
      'counterbase-local-archive:v2:$archiveCreatedAt:$saltText:$nonceText:310000',
    );
    final key = await Pbkdf2.hmacSha256(
      iterations: 310000,
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
      'iterations': 310000,
      'createdAt': archiveCreatedAt,
      'salt': saltText,
      'nonce': nonceText,
      'tag': base64Encode(encrypted.mac.bytes),
      'ciphertext': base64Encode(encrypted.cipherText),
    };
    final envelopeText = jsonEncode(envelope);
    final verified = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(envelope['ciphertext'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        mac: Mac(base64Decode(envelope['tag'] as String)),
      ),
      secretKey: key,
      aad: aad,
    );
    if (utf8.decode(verified) != plaintextText) {
      throw const LocalWorkspaceFailure(
        'The cross-platform transfer did not pass its content verification.',
      );
    }
    final envelopeBytes = utf8.encode(envelopeText);
    if (envelopeBytes.length > 64 * 1024 * 1024) {
      throw const LocalWorkspaceFailure(
        'This transfer file exceeds the 64 MB share limit. Use the full encrypted device backup instead.',
      );
    }
    final now = DateTime.now();
    final filename =
        'Counterbase-transfer-${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}-${const Uuid().v4().substring(0, 8)}.cbarchive';
    final archivePath = p.join(downloads.path, filename);
    final archiveFile = File(archivePath);
    try {
      await archiveFile.writeAsBytes(envelopeBytes, flush: true);
      if (await archiveFile.length() < 1024) {
        throw const LocalWorkspaceFailure(
          'The cross-platform transfer file is incomplete.',
        );
      }
    } catch (error) {
      try {
        if (await archiveFile.exists()) await archiveFile.delete();
      } catch (_) {
        // Preserve the export error if cleanup is unavailable.
      }
      if (error is LocalWorkspaceFailure) rethrow;
      throw const LocalWorkspaceFailure(
        'The cross-platform transfer could not be saved. Check free disk space and try again.',
      );
    }
    return archivePath;
  }

  Future<DesktopPortableBackupPreview> inspectPortableBackup({
    required String path,
    required String passphrase,
  }) async {
    _validateBackupPassphrase(passphrase);
    final file = File(path);
    if (!await file.exists()) {
      throw const LocalWorkspaceFailure(
        'That backup file is no longer available. Select it again.',
      );
    }
    final byteLength = await file.length();
    if (byteLength < 1024 || byteLength > 1024 * 1024 * 1024) {
      throw const LocalWorkspaceFailure(
        'That backup is empty or exceeds the 1 GB restore limit.',
      );
    }
    Database? database;
    try {
      database = await _openEncryptedDatabase(path, passphrase, readOnly: true);
      await _requireHealthyDatabase(database);
      return await _readBackupPreview(database, path, byteLength: byteLength);
    } on LocalWorkspaceFailure {
      rethrow;
    } catch (error) {
      debugPrint('[DesktopWorkspace] Backup inspection failed: $error');
      throw const LocalWorkspaceFailure(
        'Counterbase could not unlock this backup. Check the password and file.',
      );
    } finally {
      await database?.close();
    }
  }

  Future<void> restorePortableBackup({
    required String path,
    required String passphrase,
  }) async {
    _validateBackupPassphrase(passphrase);
    final livePath = _databasePath;
    final deviceKey = _databaseEncryptionKey;
    if (livePath == null ||
        deviceKey == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(deviceKey)) {
      throw const LocalWorkspaceFailure('The local workspace is not ready.');
    }
    final source = File(path);
    if (!await source.exists()) {
      throw const LocalWorkspaceFailure(
        'That backup file is no longer available. Select it again.',
      );
    }
    await inspectPortableBackup(path: path, passphrase: passphrase);
    final directory = p.dirname(livePath);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final stagingPath = p.join(directory, 'restore-$stamp.sqlite');
    final previousPath = p.join(directory, 'before-restore-$stamp.sqlite');
    Database? imported;
    var oldWorkspaceMoved = false;
    var newWorkspaceInstalled = false;
    try {
      await source.copy(stagingPath);
      imported = await _openEncryptedDatabase(stagingPath, passphrase);
      await _requireHealthyDatabase(imported);
      await _readBackupPreview(imported, path);
      await imported.execute('PRAGMA rekey = "x\'$deviceKey\'"');
      await _requireHealthyDatabase(imported);
      await imported.close();
      imported = null;

      await _db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await close();
      await _deleteSqliteSidecars(livePath);
      await File(livePath).rename(previousPath);
      oldWorkspaceMoved = true;
      await File(stagingPath).rename(livePath);
      newWorkspaceInstalled = true;
      await initialize(databaseKey: deviceKey);
      final businessName = await getSetting('business_name');
      final ownerName = await getSetting('owner_name');
      if (businessName == null || ownerName == null) {
        throw const LocalWorkspaceFailure(
          'The restored shop profile is incomplete. The previous workspace will be recovered.',
        );
      }
      // Keep the encrypted pre-restore database as a local rollback copy. It
      // remains protected by this computer's existing credential-store key.
    } catch (error) {
      await imported?.close();
      if (newWorkspaceInstalled) {
        await close();
        final failedWorkspace = File(livePath);
        if (await failedWorkspace.exists()) await failedWorkspace.delete();
        await _deleteSqliteSidecars(livePath);
      }
      if (oldWorkspaceMoved) {
        final previous = File(previousPath);
        if (await previous.exists()) await previous.rename(livePath);
        await initialize(databaseKey: deviceKey);
      } else if (_database == null) {
        await initialize(databaseKey: deviceKey);
      }
      final staging = File(stagingPath);
      if (await staging.exists()) await staging.delete();
      if (error is LocalWorkspaceFailure) rethrow;
      debugPrint('[DesktopWorkspace] Portable restore failed: $error');
      throw const LocalWorkspaceFailure(
        'The backup could not be restored. The previous workspace was recovered.',
      );
    }
  }

  Future<DesktopPortableBackupPreview> _readBackupPreview(
    Database database,
    String path, {
    int? byteLength,
  }) async {
    final expectedTables = {
      'settings',
      'categories',
      'products',
      'customers',
      'sales',
      'sale_items',
    };
    final tableRows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tables = tableRows.map((row) => row['name']?.toString()).toSet();
    if (!expectedTables.every(tables.contains)) {
      throw const LocalWorkspaceFailure(
        'That file is not a complete Counterbase workspace backup.',
      );
    }
    final settings = await database.query(
      'settings',
      columns: ['key', 'value'],
    );
    final values = {
      for (final row in settings)
        row['key'].toString(): row['value']?.toString() ?? '',
    };
    final businessName = values['business_name']?.trim() ?? '';
    final ownerName = values['owner_name']?.trim() ?? '';
    if (businessName.length < 2 || ownerName.length < 2) {
      throw const LocalWorkspaceFailure(
        'That backup does not contain a complete shop profile.',
      );
    }
    Future<int> count(String table) async {
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS count FROM $table',
      );
      return (rows.single['count'] as num).toInt();
    }

    return DesktopPortableBackupPreview(
      path: path,
      businessName: businessName,
      ownerName: ownerName,
      byteLength: byteLength ?? await File(path).length(),
      products: await count('products'),
      customers: await count('customers'),
      sales: await count('sales'),
    );
  }

  Future<Database> _openEncryptedDatabase(
    String path,
    String key, {
    bool readOnly = false,
  }) => databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      readOnly: readOnly,
      onConfigure: (database) async {
        await database.execute('PRAGMA key = ${_sqliteString(key)}');
        await _requireSqlCipher(database);
        await database.rawQuery('SELECT count(*) FROM sqlite_master');
      },
    ),
  );

  Future<void> _requireSqlCipher(Database database) async {
    final cipherVersion = await database.rawQuery('PRAGMA cipher_version');
    if (cipherVersion.isEmpty ||
        cipherVersion.first.values.every(
          (value) => value == null || value.toString().trim().isEmpty,
        )) {
      throw const LocalWorkspaceFailure(
        'Encrypted backup support is unavailable in this Counterbase build.',
      );
    }
  }

  Future<void> _requireHealthyDatabase(Database database) async {
    final check = await database.rawQuery('PRAGMA quick_check');
    if (check.length != 1 || check.single.values.first != 'ok') {
      throw const LocalWorkspaceFailure(
        'This backup did not pass its database integrity check.',
      );
    }
  }

  Future<void> _deleteSqliteSidecars(String path) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File('$path$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
  }

  void _validateBackupPassphrase(String passphrase) {
    if (passphrase.length < 12 ||
        passphrase.length > 1024 ||
        passphrase.contains('\u0000')) {
      throw const LocalWorkspaceFailure(
        'Use a backup password between 12 and 1024 characters.',
      );
    }
  }

  String _sqliteString(String value) => "'${value.replaceAll("'", "''")}'";

  String _three(int value) => value.toString().padLeft(3, '0');

  Future<Map<String, dynamic>?> _productById(String id) async {
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, c.name AS category_name
      FROM products p LEFT JOIN categories c ON c.id = p.category_id
      WHERE p.id = ? LIMIT 1
    ''',
      [id],
    );
    return rows.isEmpty ? null : _productJson(rows.first);
  }

  Future<Map<String, dynamic>?> _customerById(String id) async {
    final rows = await _db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  String? _categoryId(Map<String, dynamic> payload) {
    final ids = payload['categoryIds'];
    if (ids is List && ids.isNotEmpty && ids.first != null) {
      return ids.first.toString();
    }
    final single = payload['categoryId']?.toString();
    return single?.isEmpty == true ? null : single;
  }

  Map<String, dynamic> _productJson(Map<String, Object?> row) => {
    'id': row['id'],
    'name': row['name'],
    'categories': row['category_id'] == null
        ? const []
        : [
            {
              'id': row['category_id'],
              'name': row['category_name'] ?? 'General',
            },
          ],
    'currentPrice': row['price'],
    'price': row['price'],
    'currentStock': row['stock'],
    'sku': (row['sku']?.toString().isEmpty ?? true) ? '—' : row['sku'],
    'minStock': row['min_stock'],
    'unit': row['unit'],
    'imageUrl': row['image_url'],
    'isActive': row['is_active'] == 1,
  };

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

String _databaseMessage(DatabaseException error) {
  final message = error.toString().toLowerCase();
  if (message.contains('products.sku') ||
      message.contains('unique constraint')) {
    return 'That SKU is already used by another product.';
  }
  return 'The change could not be saved to this device. Please review the details and try again.';
}

String _requiredText(dynamic value, String message) {
  final text = value?.toString().trim() ?? '';
  if (text.length < 2) throw LocalWorkspaceFailure(message);
  return text;
}

double _number(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

String _two(int value) => value.toString().padLeft(2, '0');

String _archiveSlug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'my-shop' : slug;
}

DateTime _startOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

String _timestamp(DateTime date) => date.toIso8601String();

String _formatQuantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

Map<String, dynamic> jsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> jsonMaps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

List<Map<String, dynamic>> _archiveMaps(dynamic value) {
  if (value is! List) return const [];
  return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}

String _archiveText(dynamic value) => value?.toString().trim() ?? '';

String _requiredArchiveText(dynamic value, String label) {
  final text = _archiveText(value);
  if (text.isEmpty) {
    throw LocalWorkspaceFailure('The archive is missing $label.');
  }
  return text;
}

double _archiveNumber(dynamic value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (parsed == null || !parsed.isFinite) {
    throw const LocalWorkspaceFailure(
      'The archive contains an invalid price, quantity, or amount.',
    );
  }
  return parsed;
}

bool _archiveBool(dynamic value, bool fallback) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {'true', '1', 'yes'}.contains(value.toString().toLowerCase());
}

String _archiveDate(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    throw const LocalWorkspaceFailure(
      'The archive contains an invalid business date.',
    );
  }
  return parsed.toIso8601String();
}

bool _archiveBranchExists(
  List<Map<String, dynamic>> branches,
  dynamic branchId,
) => branches.any((branch) => branch['id']?.toString() == branchId?.toString());

String _archiveBranchCode(
  List<Map<String, dynamic>> branches,
  dynamic branchId,
) {
  for (final branch in branches) {
    if (branch['id']?.toString() == branchId?.toString()) {
      return _archiveText(branch['code']);
    }
  }
  return '';
}
