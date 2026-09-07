import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';

/// Lightweight, schemaless local cache for the staff invitation list.
///
/// Stored as plain JSON strings in a dedicated Hive box so the existing
/// `List<Map<String, dynamic>>` shape used by the screen can be restored
/// without hand-written generated code.
///
/// The cache key is scoped to the signed-in tenant — a fixed key would let
/// tenant B's admin see tenant A's invitation PII (names, emails, phone
/// numbers) on a shared device while the fresh fetch is in flight, and the
/// data would persist in plaintext after logout. [invalidate] is also wired
/// into logout so nothing tenant-specific outlives the session.
class InvitationCacheService {
  static const String _boxName = 'invitation_cache';
  static const String _keyPrefix = 'staff_invitations_v1';

  Box<String>? _box;

  /// Initializes Hive and opens the cache box. Safe to call repeatedly.
  Future<void> initialize() async {
    await Hive.initFlutter();
    _box ??= await Hive.openBox<String>(_boxName);
  }

  /// Tenant-scoped cache key: falls back to a shared 'anonymous' bucket
  /// only when no tenant is resolvable (pre-login), in which case nothing
  /// meaningful should be cached anyway.
  String get _key {
    String tenantId = 'anonymous';
    try {
      final id = getIt<AuthService>().tenantId;
      if (id != null && id.isNotEmpty) tenantId = id;
    } catch (_) {
      // DI not ready (e.g. early tests) — anonymous bucket.
    }
    return '${_keyPrefix}_$tenantId';
  }

  void _ensureOpen() {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
        'InvitationCacheService not initialized. Call initialize() first.',
      );
    }
  }

  /// Returns the currently cached invitation list, or null if nothing has
  /// been cached yet (or the cache was invalidated).
  List<Map<String, dynamic>>? getInvitations() {
    _ensureOpen();
    final raw = _box!.get(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Persist the invitation list returned from the backend.
  Future<void> saveInvitations(List<Map<String, dynamic>> invitations) async {
    _ensureOpen();
    await _box!.put(_key, jsonEncode(invitations));
  }

  /// Explicitly clears the current tenant's cached list. Call after any
  /// mutation that changes the invitation list (e.g. sending a new
  /// invitation, accepting one).
  Future<void> invalidate() async {
    _ensureOpen();
    await _box!.delete(_key);
  }

  /// Clears every tenant's cached invitations. Called on logout so no
  /// staff PII survives the session on a shared device.
  Future<void> invalidateAll() async {
    _ensureOpen();
    await _box!.clear();
  }

  /// Closes the box. Used during tests and logout cleanup.
  Future<void> dispose() async {
    if (_box != null && _box!.isOpen) {
      await _box!.close();
      _box = null;
    }
  }
}