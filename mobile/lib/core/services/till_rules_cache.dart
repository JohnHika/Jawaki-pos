import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'till_guard.dart';

/// Keeps the last rules on the phone so the till can apply them offline.
class TillRulesCache {
  static const _key = 'till_rules_v1';
  static const staleAfter = Duration(hours: 6);

  TillRules? _memory;

  TillRules? get current => _memory;

  bool get isStale =>
      _memory == null ||
      DateTime.now().difference(_memory!.generatedAt) > staleAfter;

  Future<TillRules?> load() async {
    if (_memory != null) return _memory;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      _memory = TillRules.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      _memory = null;
    }
    return _memory;
  }

  Future<void> save(TillRules rules) async {
    _memory = rules;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(rules.toJson()));
    } catch (_) {
      // The in-memory copy still works for this session.
    }
  }

  /// Forget the rules, e.g. on sign-out: they belong to one user's overrides.
  Future<void> clear() async {
    _memory = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
