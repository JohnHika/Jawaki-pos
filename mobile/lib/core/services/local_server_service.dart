import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../database/app_database.dart';
import '../di/injection.dart';
import '../network/api_client.dart';
import 'connectivity_service.dart';
import 'server/middleware.dart';
import 'server/routes/auth_routes.dart';
import 'server/routes/catalog_routes.dart';
import 'server/routes/sales_routes.dart';
import 'server/routes/inventory_routes.dart';
import 'server/routes/sync_routes.dart';
import 'server/routes/report_routes.dart';
import 'server/routes/image_routes.dart';
import 'server/routes/payment_routes.dart';
import 'storage_service.dart';

/// Phone Server Mode — runs an HTTP server inside the Flutter app.
///
/// Other phones on the network (or via Tailscale) connect to this server
/// instead of requiring a separate NestJS/PostgreSQL backend.
///
/// Usage:
/// ```dart
/// final server = LocalServerService();
/// await server.start(port: 3000);
/// // ...
/// await server.stop();
/// ```
class LocalServerService {
  HttpServer? _server;
  StreamSubscription<ConnectionStatus>? _autoStartSubscription;
  bool _isRunning = false;
  int _port = 3000;
  List<Map<String, dynamic>> _connectedClients = [];

  bool get isRunning => _isRunning;
  int get port => _port;
  List<Map<String, dynamic>> get connectedClients =>
      List.unmodifiable(_connectedClients);

  void enableAutoStart({
    required ConnectivityService connectivity,
    required StorageService storage,
  }) {
    _autoStartSubscription?.cancel();
    _autoStartSubscription = connectivity.statusStream.listen((status) {
      _startIfPreferredNetworkIsAvailable(connectivity, storage);
    });
    _startIfPreferredNetworkIsAvailable(connectivity, storage);
  }

  Future<void> _startIfPreferredNetworkIsAvailable(
    ConnectivityService connectivity,
    StorageService storage,
  ) async {
    if (_isRunning || !storage.isServerModeEnabled()) return;
    if (connectivity.isOnline && connectivity.isWifi) {
      await start(port: storage.getServerPort());
    }
  }

  /// Get the local IP addresses of this device.
  static Future<List<String>> getLocalIpAddresses() async {
    try {
      final interfaces = await NetworkInterface.list();
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
      return ips;
    } catch (e) {
      debugPrint('[LocalServer] Failed to get IP: $e');
      return [];
    }
  }

  /// Start the HTTP server on the given [port].
  Future<bool> start({int port = 3000}) async {
    if (_isRunning) {
      debugPrint('[LocalServer] Already running on port $_port');
      return true;
    }

    _port = port;

    try {
      // Build the router with all routes
      final appRouter = Router();

      // Get the database from DI
      final db = getIt<AppDatabase>();

      // Register all route handlers directly into the main router.
      // IMPORTANT: Do NOT use mount() with the same prefix — it replaces
      // previously mounted routes. Each class must add to the same router.
      final db_local = db;
      await _seedDefaultAdmin(db_local);

      AuthRoutes(db_local).addRoutes(appRouter);
      CatalogRoutes(db_local).addRoutes(appRouter);
      SalesRoutes(db_local).addRoutes(appRouter);
      InventoryRoutes(db_local).addRoutes(appRouter);
      SyncRoutes(db_local).addRoutes(appRouter);
      ReportRoutes(db_local).addRoutes(appRouter);
      ImageRoutes().addRoutes(appRouter);
      PaymentRoutes().addRoutes(appRouter);

      // Build middleware pipeline
      final handler = shelf.Pipeline()
          .addMiddleware(errorHandler())
          .addMiddleware(corsMiddleware())
          .addMiddleware(jsonBodyParser())
          .addMiddleware(authMiddleware())
          .addHandler(appRouter);

      // Start the server on all interfaces
      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        port,
      );

      // Auto-redirect the API client to localhost so the app
      // talks to itself instead of the old remote backend.
      try {
        final apiClient = getIt<ApiClient>();
        apiClient.setBaseUrl('http://127.0.0.1:$port/api/v1');
        debugPrint('[LocalServer] ✅ API client redirected to local server');
      } catch (e) {
        debugPrint('[LocalServer] ⚠️  Could not redirect API client: $e');
      }

      _isRunning = true;

      final ips = await getLocalIpAddresses();
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('  🖥️  PHONE SERVER MODE ACTIVE');
      debugPrint('  Port: $port');
      for (final ip in ips) {
        debugPrint('  URL: http://$ip:$port');
      }
      debugPrint('  Clients can connect via Settings → Backend Server');
      debugPrint('═══════════════════════════════════════════════════');

      return true;
    } catch (e, stack) {
      debugPrint('[LocalServer] Failed to start: $e');
      debugPrint('[LocalServer] Stack: $stack');
      _isRunning = false;
      return false;
    }
  }

  /// Stop the HTTP server.
  Future<void> stop() async {
    if (!_isRunning || _server == null) return;

    try {
      await _server!.close(force: true);
      _isRunning = false;
      _connectedClients.clear();
      debugPrint('[LocalServer] Server stopped');
    } catch (e) {
      debugPrint('[LocalServer] Error stopping: $e');
    }
  }

  /// Restart the server on a new port.
  Future<bool> restart({int? port}) async {
    await stop();
    return start(port: port ?? _port);
  }

  /// Register a connected client (called from middleware).
  void registerClient(String ip, String? deviceId) {
    _connectedClients.removeWhere((c) => c['ip'] == ip);
    _connectedClients.add({
      'ip': ip,
      'deviceId': deviceId ?? '',
      'connectedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Seed a default admin user if the server_users table is empty.
  Future<void> _seedDefaultAdmin(AppDatabase db) async {
    try {
      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS server_users ('
        '  id TEXT PRIMARY KEY NOT NULL, '
        '  email TEXT NOT NULL UNIQUE, '
        '  password_hash TEXT NOT NULL, '
        '  pin_hash TEXT, '
        '  first_name TEXT NOT NULL DEFAULT \'\', '
        '  last_name TEXT NOT NULL DEFAULT \'\', '
        '  role TEXT NOT NULL DEFAULT \'CASHIER\', '
        '  tenant_id TEXT NOT NULL DEFAULT \'local\', '
        '  branch_id TEXT, '
        '  is_active INTEGER NOT NULL DEFAULT 1, '
        '  last_login_at TEXT, '
        '  created_at TEXT NOT NULL, '
        '  updated_at TEXT NOT NULL'
        ')',
      );

      // No default admin seeded - user must create their own via setup screen
      debugPrint('[LocalServer] ℹ️  No default users - setup required on first login');
    } catch (e) {
      debugPrint('[LocalServer] ⚠️  Could not seed admin user: $e');
    }
  }
}
