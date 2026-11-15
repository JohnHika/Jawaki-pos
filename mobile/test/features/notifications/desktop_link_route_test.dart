import 'package:axon_pos/features/notifications/domain/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a computer sign-in prompt opens the approval screen on that request', () {
    const qr = '{"v":2,"app":"counterbase","id":"abc","code":"123456"}';
    final route = routeForNotification(
      'desktop_link_request',
      {'linkId': 'abc', 'payload': qr},
    );
    final uri = Uri.parse(route);
    expect(uri.path, '/settings/desktop-approvals');
    expect(uri.queryParameters['payload'], qr);
  });

  test('without a request attached it still opens the approvals screen', () {
    expect(
      routeForNotification('desktop_link_request', {}),
      '/settings/desktop-approvals',
    );
  });
}
