import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

/// Lightweight, schemaless local cache for the staff invitation list.
///
/// Stored as plain JSON strings in a dedicated Hive box so the existing
/// `List<Map<String, dynamic>>` shape used by the screen can be restored
/// without hand-written generated code. The cache is tenant-scoped via
/// [cacheKey] so a different company logging in on the same device never
/// sees another tenant's invitations.
class InvitationCacheService {
  static const String _boxName = 'invitation_cache';
  static const String _key = 'staff_invitations_v1';

  Box<String>? _box;

  /// Initializes Hive and opens the cache box. Safe to call repeatedly.
  Future<void> initialize() async {
    await Hive.initFlutter();
    _box ??= await Hive.openBox<String>(_boxName);
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

  /// Explicitly clears the cache. Call after any mutation that changes the
  /// invitation list (e.g. sending a new invitation, accepting one).
  Future<void> invalidate() async {
    _ensureOpen();
    await _box!.delete(_key);
  }

  /// Closes the box. Used during tests and logout cleanup.
  Future<void> dispose() async {
    if (_box != null && _box!.isOpen) {
      await _box!.close();
      _box = null;
    }
  }
}
