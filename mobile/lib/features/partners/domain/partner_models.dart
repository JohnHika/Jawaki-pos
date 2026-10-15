/// A business the signed-in shop trades with (or is connecting with) —
/// "Trade Partners". Mirrors one row of GET /partners.
class TradePartner {
  const TradePartner({
    required this.id,
    required this.status,
    required this.direction,
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.createdAt,
    this.logo,
    this.message,
    this.lastMessageBody,
    this.lastMessageAt,
    this.lastMessageFromMe = false,
    this.unreadCount = 0,
  });

  factory TradePartner.fromJson(Map<String, dynamic> json) {
    final partner = (json['partner'] as Map?)?.cast<String, dynamic>() ?? {};
    final last = (json['lastMessage'] as Map?)?.cast<String, dynamic>();
    return TradePartner(
      id: (json['id'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString().toUpperCase(),
      direction: (json['direction'] ?? 'outgoing').toString(),
      tenantId: (partner['tenantId'] ?? '').toString(),
      name: (partner['name'] ?? 'Business').toString(),
      slug: (partner['slug'] ?? '').toString(),
      logo: partner['logo']?.toString(),
      message: json['message']?.toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString())?.toLocal() ??
              DateTime.now(),
      lastMessageBody: last?['body']?.toString(),
      lastMessageAt: last == null
          ? null
          : DateTime.tryParse((last['createdAt'] ?? '').toString())?.toLocal(),
      lastMessageFromMe: last?['fromMe'] == true,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String status;
  final String direction;
  final String tenantId;
  final String name;
  final String slug;
  final String? logo;
  final String? message;
  final DateTime createdAt;
  final String? lastMessageBody;
  final DateTime? lastMessageAt;
  final bool lastMessageFromMe;
  final int unreadCount;

  bool get isAccepted => status == 'ACCEPTED';
  bool get isPending => status == 'PENDING';
  bool get isIncomingRequest => isPending && direction == 'incoming';
  bool get isOutgoingRequest => isPending && direction == 'outgoing';

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

/// One chat message between two partner businesses.
class PartnerMessage {
  const PartnerMessage({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.fromMe,
    required this.senderName,
  });

  factory PartnerMessage.fromJson(Map<String, dynamic> json) => PartnerMessage(
        id: (json['id'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((json['createdAt'] ?? '').toString())?.toLocal() ??
                DateTime.now(),
        fromMe: json['fromMe'] == true,
        senderName: (json['senderName'] ?? '').toString(),
      );

  final String id;
  final String body;
  final DateTime createdAt;
  final bool fromMe;
  final String senderName;
}
