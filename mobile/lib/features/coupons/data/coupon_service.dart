import 'package:flutter/foundation.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/company_caches.dart';
import '../../../core/services/coupon_cache.dart';
import '../../../core/services/coupon_rules.dart';

/// The shop's coupons as the till sees them. Works offline from the cache.
class CouponService {
  CouponService._() {
    CompanyCaches.register(_cache.clear);
  }

  static final CouponService instance = CouponService._();

  final CouponCache _cache = CouponCache();
  bool _refreshing = false;

  /// Pulls the latest coupons when the cached ones are old. Never throws: the
  /// till carries on with whatever it already has.
  Future<void> refreshIfStale({bool force = false}) async {
    await _cache.load();
    if (!force && !_cache.isStale) return;
    if (_refreshing) return;
    _refreshing = true;
    try {
      final json = await getIt<ApiClient>().getTillCoupons();
      final list = json['coupons'];
      if (list is List) {
        await _cache.save([
          for (final item in list)
            if (item is Map) Coupon.fromJson(item.cast<String, dynamic>()),
        ]);
      }
    } catch (e) {
      debugPrint('[Coupons] refresh failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<Coupon?> find(String code) async {
    await _cache.load();
    return _cache.find(code);
  }

  bool get hasAny => _cache.coupons.isNotEmpty;
}
