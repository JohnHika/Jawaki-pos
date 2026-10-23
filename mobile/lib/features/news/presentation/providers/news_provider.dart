import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/news_models.dart';

final newsDigestProvider = FutureProvider.autoDispose<NewsDigest>((ref) async {
  return NewsDigest.fromJson(await getIt<ApiClient>().getBusinessNewsDigest());
});

final exchangeRatesProvider = FutureProvider.autoDispose<RateBoard>((ref) async {
  return RateBoard.fromJson(await getIt<ApiClient>().getExchangeRates());
});

/// Headlines for one topic (null = everything).
final newsListProvider = FutureProvider.autoDispose
    .family<List<NewsItem>, String?>((ref, category) async {
  final json = await getIt<ApiClient>()
      .getBusinessNews(category: category, limit: 30);
  return ((json['items'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => NewsItem.fromJson(e.cast<String, dynamic>()))
      .toList();
});

final officialLinksProvider =
    FutureProvider.autoDispose<List<OfficialLink>>((ref) async {
  final json = await getIt<ApiClient>().getBusinessNewsSources();
  return ((json['official'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => OfficialLink.fromJson(e.cast<String, dynamic>()))
      .toList();
});
