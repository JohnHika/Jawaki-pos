/// One saved notification in the user's inbox (mirrors the backend's
/// AppNotification row).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return AppNotification(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'general').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      data: rawData is Map ? Map<String, dynamic>.from(rawData) : const {},
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString())?.toLocal() ??
              DateTime.now(),
      readAt: json['readAt'] == null
          ? null
          : DateTime.tryParse(json['readAt'].toString())?.toLocal(),
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  AppNotification markedRead() => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        data: data,
        createdAt: createdAt,
        readAt: readAt ?? DateTime.now(),
      );
}

/// Where tapping a notification should take the user. Falls back to the
/// inbox itself for types without a dedicated screen.
String routeForNotification(String type, Map<String, dynamic> data) {
  switch (type) {
    case 'partner_request':
    case 'partner_accepted':
      return '/partners';
    case 'partner_message':
      final id = data['partnershipId']?.toString();
      return id == null || id.isEmpty ? '/partners' : '/partners/$id';
    case 'stock_request_resolved':
    case 'low_stock_alert':
    case 'restock_suggestion':
      return '/inventory';
    case 'eod_reminder':
      return '/cash-flow/end-of-day';
    case 'accountability_alert':
    case 'daily_summary':
      return '/shop-alerts';
    case 'business_news':
      return '/news';
    case 'statement_claim':
    case 'statement_viewed':
      return '/statements/replies';
    case 'desktop_link_request':
    case 'desktop_link_claimed':
    case 'desktop_link_denied':
      return '/settings/desktop-approvals';
    case 'referral_reward':
      return '/referrals';
    default:
      return '/notifications';
  }
}
