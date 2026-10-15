import 'package:axon_pos/features/notifications/domain/app_notification.dart';
import 'package:axon_pos/features/partners/domain/partner_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TradePartner.fromJson', () {
    test('reads an incoming pending request', () {
      final p = TradePartner.fromJson({
        'id': 'p1',
        'status': 'PENDING',
        'direction': 'incoming',
        'partner': {
          'tenantId': 't2',
          'name': 'Levisa Ventures',
          'slug': 'levisa-ventures',
          'logo': null,
        },
        'message': 'Hi',
        'createdAt': '2026-10-15T13:03:59.092Z',
        'lastMessage': null,
        'unreadCount': 0,
      });
      expect(p.isIncomingRequest, isTrue);
      expect(p.isAccepted, isFalse);
      expect(p.initial, 'L');
      expect(p.slug, 'levisa-ventures');
    });

    test('reads an accepted partner with last message and unread count', () {
      final p = TradePartner.fromJson({
        'id': 'p1',
        'status': 'ACCEPTED',
        'direction': 'outgoing',
        'partner': {'tenantId': 't2', 'name': 'Jawaki', 'slug': 'jawaki'},
        'createdAt': '2026-10-15T13:03:59.092Z',
        'lastMessage': {
          'body': 'Deliver Friday?',
          'createdAt': '2026-10-15T13:10:00.000Z',
          'fromMe': false,
        },
        'unreadCount': 3,
      });
      expect(p.isAccepted, isTrue);
      expect(p.lastMessageBody, 'Deliver Friday?');
      expect(p.lastMessageFromMe, isFalse);
      expect(p.unreadCount, 3);
    });
  });

  group('routeForNotification', () {
    test('partner notifications open the partner screens', () {
      expect(routeForNotification('partner_request', {}), '/partners');
      expect(routeForNotification('partner_accepted', {}), '/partners');
      expect(
        routeForNotification('partner_message', {'partnershipId': 'abc'}),
        '/partners/abc',
      );
      expect(routeForNotification('partner_message', {}), '/partners');
    });

    test('stock alerts open inventory; unknown types open the inbox', () {
      expect(routeForNotification('low_stock_alert', {}), '/inventory');
      expect(routeForNotification('stock_request_resolved', {}), '/inventory');
      expect(routeForNotification('eod_reminder', {}), '/cash-flow/end-of-day');
      expect(routeForNotification('something_new', {}), '/notifications');
    });
  });

  test('AppNotification parses read state and data', () {
    final n = AppNotification.fromJson({
      'id': 'n1',
      'type': 'partner_message',
      'title': 'Levisa',
      'body': 'Hello',
      'data': {'partnershipId': 'p1'},
      'readAt': null,
      'createdAt': '2026-10-15T13:00:00.000Z',
    });
    expect(n.isUnread, isTrue);
    expect(n.data['partnershipId'], 'p1');
    expect(n.markedRead().isUnread, isFalse);
  });
}
