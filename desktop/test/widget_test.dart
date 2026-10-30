import 'dart:convert';
import 'dart:io';

import 'package:axon_pos_desktop/core/desktop_link_client.dart';
import 'package:axon_pos_desktop/core/desktop_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
void main() {
  test('desktop workspace is assigned to its local branch', () {
    expect(localWorkspaceBranchId, 'local-main');
  });

  group('DesktopLinkClient against a live phone-server stub', () {
    late HttpServer server;
    late Router router;
    String? startSecret;
    String startCode = '';
    String linkStatus = 'pending';

    setUp(() async {
      startSecret = null;
      startCode = '';
      linkStatus = 'pending';
      router = Router();
      router.post('/api/v1/desktop-link/start', (shelf.Request request) async {
        startCode = '123456';
        startSecret = 's3cret-value-from-qr';
        return shelf.Response.ok(
          jsonEncode({
            'linkId': 'link-1',
            'code': startCode,
            'qr': jsonEncode({
              'v': 1,
              'id': 'link-1',
              'code': startCode,
              's': startSecret,
            }),
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 3))
                .toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      });
      router.get('/api/v1/desktop-link/status', (shelf.Request request) async {
        return shelf.Response.ok(
          jsonEncode({
            'status': linkStatus,
            if (linkStatus == 'approved')
              'account': {
                'firstName': 'Ada',
                'lastName': 'Obi',
                'email': 'owner@shop.com',
                'role': 'ADMIN',
              },
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 3))
                .toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      });
      router.post('/api/v1/desktop-link/claim', (shelf.Request request) async {
        final body =
            jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        if (body['secret'] != startSecret) {
          return shelf.Response(
            401,
            body: jsonEncode({'message': 'Invalid claim secret'}),
            headers: {'content-type': 'application/json'},
          );
        }
        return shelf.Response.ok(
          jsonEncode({
            'accessToken': 'access-token',
            'refreshToken': 'refresh-token',
            'expiresIn': 28800,
            'user': {
              'id': 'owner-1',
              'firstName': 'Ada',
              'lastName': 'Obi',
              'role': 'ADMIN',
              'tenantId': 'local',
              'permissions': ['sales.view'],
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      });

      server = await shelf_io.serve(router.call, InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() => server.close(force: true));

    test('start parses code and QR secret', () async {
      final client = DesktopLinkClient(
        baseUrlOverride: 'http://127.0.0.1:${server.port}',
      );
      final start = await client.start(desktopName: 'Test PC');
      expect(start.code, '123456');
      expect(start.secret, 's3cret-value-from-qr');
    });

    test('full flow: start → approve → claim returns session', () async {
      final client = DesktopLinkClient(
        baseUrlOverride: 'http://127.0.0.1:${server.port}',
      );
      final start = await client.start(desktopName: 'Test PC');

      var status = await client.status(start.linkId);
      expect(status.status, 'pending');

      linkStatus = 'approved';
      status = await client.status(start.linkId);
      expect(status.status, 'approved');
      expect(status.accountName, 'Ada Obi');

      final session = await client.claim(
        linkId: start.linkId,
        secret: start.secret!,
      );
      expect(session.accessToken, 'access-token');
      expect(session.userName, 'Ada Obi');
      expect(session.role, 'ADMIN');
    });

    test('server errors surface as readable failures', () async {
      final client = DesktopLinkClient(
        baseUrlOverride: 'http://127.0.0.1:${server.port}',
      );
      await expectLater(
        client.claim(linkId: 'link-1', secret: 'wrong'),
        throwsA(
          isA<DesktopLinkFailure>().having(
            (e) => e.message,
            'message',
            'Invalid claim secret',
          ),
        ),
      );
    });
  });
}

