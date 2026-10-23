import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/coupon_models.dart';

final couponsProvider =
    FutureProvider.autoDispose<List<ShopCoupon>>((ref) async {
  final rows = await getIt<ApiClient>().getCoupons();
  return rows.map(ShopCoupon.fromJson).toList();
});

final couponReportProvider =
    FutureProvider.autoDispose<CouponReport>((ref) async {
  final json = await getIt<ApiClient>().getCouponReport(days: 30);
  return CouponReport.fromJson(json);
});
