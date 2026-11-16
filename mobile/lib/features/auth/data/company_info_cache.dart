import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The last name and logo seen for each company code, so the sign-in header
/// can show the business at once instead of waiting for the network.
class CompanyInfoCache {
  CompanyInfoCache._();

  static const _key = 'company_info_cache_v1';
  static const _maxEntries = 12;

  static Future<Map<String, dynamic>?> read(String slug) async {
    try {
      final all = await _load();
      final entry = all[slug];
      return entry is Map ? Map<String, dynamic>.from(entry) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String slug, {String? name, String? logoUrl}) async {
    if (slug.isEmpty || ((name ?? '').isEmpty && (logoUrl ?? '').isEmpty)) return;
    try {
      final all = await _load();
      all.remove(slug);
      all[slug] = {'name': name, 'logoUrl': logoUrl};
      while (all.length > _maxEntries) {
        all.remove(all.keys.first);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(all));
    } catch (_) {
      // A cache that cannot be written only costs the speed-up.
    }
  }

  static Future<Map<String, dynamic>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }
}
