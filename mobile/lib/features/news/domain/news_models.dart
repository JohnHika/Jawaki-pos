import '../../../core/utils/api_message.dart';

const newsCategories = <String, String>{
  'CUSTOMS_TAX': 'Customs & tax',
  'TRADE_IMPORT': 'Imports & trade',
  'MONEY_FX': 'Money & rates',
  'COUNTY_LICENSING': 'County & markets',
  'LOGISTICS': 'Fuel & transport',
  'MARKET': 'Prices & business',
};

class NewsItem {
  const NewsItem({
    required this.id,
    required this.source,
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.category,
    required this.impact,
    this.summary,
    this.imageUrl,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) => NewsItem(
        id: '${json['id'] ?? ''}',
        source: '${json['source'] ?? ''}',
        title: '${json['title'] ?? ''}',
        url: '${json['url'] ?? ''}',
        summary: json['summary']?.toString(),
        imageUrl: json['imageUrl']?.toString(),
        publishedAt: asDate(json['publishedAt']) ?? DateTime.now(),
        category: '${json['category'] ?? 'GENERAL'}',
        impact: '${json['impact'] ?? 'LOW'}',
      );

  final String id;
  final String source;
  final String title;
  final String url;
  final String? summary;
  final String? imageUrl;
  final DateTime publishedAt;
  final String category;
  final String impact;

  bool get isUrgent => impact == 'HIGH';
  String get categoryLabel => newsCategories[category] ?? 'News';
}

class NewsDigest {
  const NewsDigest({this.urgent = const []});

  factory NewsDigest.fromJson(Map<String, dynamic> json) => NewsDigest(
        urgent: ((json['urgent'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => NewsItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  final List<NewsItem> urgent;
}

class RateBoard {
  const RateBoard({
    required this.rates,
    required this.disclaimer,
    this.updatedAt,
    this.stale = false,
  });

  factory RateBoard.fromJson(Map<String, dynamic> json) => RateBoard(
        rates: ((json['rates'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', asDouble(v))),
        disclaimer: '${json['disclaimer'] ?? ''}',
        updatedAt: asDate(json['updatedAt']),
        stale: json['stale'] == true,
      );

  /// KES for 1 unit of the currency.
  final Map<String, double> rates;
  final String disclaimer;
  final DateTime? updatedAt;
  final bool stale;
}

class OfficialLink {
  const OfficialLink(
      {required this.name, required this.url, required this.about});

  factory OfficialLink.fromJson(Map<String, dynamic> json) => OfficialLink(
        name: '${json['name'] ?? ''}',
        url: '${json['url'] ?? ''}',
        about: '${json['about'] ?? ''}',
      );

  final String name;
  final String url;
  final String about;
}
