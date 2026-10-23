import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'coupon_rules.dart';

/// Keeps the shop's redeemable coupons on the phone so the till can apply a
/// code with no signal. Usage limits and per-customer limits are re-checked by
/// the server when the sale syncs.
class CouponCache {
  static const _key = 'till_coupons_v1';
  static const staleAfter = Duration(minutes: 30);

  List<Coupon>? _memory;
  DateTime? _fetchedAt;

  List<Coupon> get coupons => _memory ?? const [];

  bool get isStale =>
      _memory == null ||
      _fetchedAt == null ||
      DateTime.now().difference(_fetchedAt!) > staleAfter;

  /// The coupon for a typed code, ignoring case and spaces.
  Coupon? find(String code) {
    final wanted = normaliseCouponCode(code);
    if (wanted.isEmpty) return null;
    for (final coupon in coupons) {
      if (coupon.code == wanted) return coupon;
    }
    return null;
  }

  Future<void> load() async {
    if (_memory != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
      _fetchedAt = DateTime.tryParse('${json['fetchedAt']}')?.toLocal();
      _memory = [
        for (final item in (json['coupons'] as List?) ?? const [])
          if (item is Map) Coupon.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      _memory = null;
    }
  }

  Future<void> save(List<Coupon> coupons) async {
    _memory = coupons;
    _fetchedAt = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'fetchedAt': _fetchedAt!.toUtc().toIso8601String(),
          'coupons': [for (final c in coupons) c.toJson()],
        }),
      );
    } catch (_) {
      // The in-memory copy still works for this session.
    }
  }

  Future<void> clear() async {
    _memory = null;
    _fetchedAt = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
