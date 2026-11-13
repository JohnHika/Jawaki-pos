import 'dart:convert';

import 'package:axon_pos/core/services/httpsms_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('HttpsmsService', () {
    test('queues the recipient message using the HTTPSMS account contract',
        () async {
      Uri? requestedUri;
      Map<String, String>? requestedHeaders;
      Map<String, dynamic>? requestedBody;
      final service = HttpsmsService(
        transport: (uri, {required headers, required body}) async {
          requestedUri = uri;
          requestedHeaders = headers;
          requestedBody = jsonDecode(body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {'id': 'message-1'}
            }),
            200,
          );
        },
      );

      final result = await service.send(
        apiKey: 'account-key-test-only',
        from: '0712 345 678',
        to: '+1 (202) 555-0123',
        content: 'Account statement',
      );

      expect(requestedUri, Uri.https('api.httpsms.com', '/v1/messages/send'));
      expect(requestedHeaders?['x-api-key'], 'account-key-test-only');
      expect(requestedHeaders?['content-type'], 'application/json');
      expect(requestedBody, {
        'from': '+254712345678',
        'to': '+12025550123',
        'content': 'Account statement',
        'encrypted': false,
      });
      expect(result.statusCode, 200);
      expect(result.messageId, 'message-1');
    });

    test('rejects redirects without forwarding the account key', () async {
      var requestCount = 0;
      var followedRedirects = true;
      final client = MockClient((request) async {
        requestCount++;
        followedRedirects = request.followRedirects;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://attacker.example/collect'},
        );
      });
      addTearDown(client.close);

      await expectLater(
        http.runWithClient(
          () => HttpsmsService().send(
            apiKey: 'account-key-test-only',
            from: '+254711222333',
            to: '+254712000111',
            content: 'Account statement',
          ),
          () => client,
        ),
        throwsA(isA<HttpsmsException>()),
      );

      expect(requestCount, 1);
      expect(followedRedirects, isFalse);
    });

    test('normalizes Kenyan national and international numbers', () {
      expect(
        HttpsmsService.normalizePhoneNumber('0712 000 111'),
        '+254712000111',
      );
      expect(
        HttpsmsService.normalizePhoneNumber('254 712 000 111'),
        '+254712000111',
      );
      expect(
        HttpsmsService.normalizePhoneNumber('+44 20 7946 0958'),
        '+442079460958',
      );
    });

    test('rejects international numbers with a zero country-code prefix', () {
      expect(
        () => HttpsmsService.normalizePhoneNumber('+0123456789'),
        throwsA(isA<HttpsmsException>()),
      );
      expect(
        () => HttpsmsService.normalizePhoneNumber('00 0123456789'),
        throwsA(isA<HttpsmsException>()),
      );
    });

    test('rejects an invalid recipient before making a request', () async {
      var requests = 0;
      final service = HttpsmsService(
        transport: (_, {required headers, required body}) async {
          requests++;
          return http.Response('{}', 200);
        },
      );

      await expectLater(
        service.send(
          apiKey: 'test-key',
          from: '+254712345678',
          to: 'not a phone number',
          content: 'hello',
        ),
        throwsA(isA<HttpsmsException>()),
      );
      expect(requests, 0);
    });

    test('uses a generic message for an undocumented status code', () async {
      final service = HttpsmsService(
        transport: (_, {required headers, required body}) async =>
            http.Response('private provider response', 402),
      );

      await expectLater(
        service.send(
          apiKey: 'test-key',
          from: '+254712345678',
          to: '+254712000111',
          content: 'hello',
        ),
        throwsA(
          isA<HttpsmsException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 402'),
          ),
        ),
      );
    });

    test('treats a transport failure as an unknown queue outcome', () async {
      final service = HttpsmsService(
        transport: (_, {required headers, required body}) async {
          throw http.ClientException('connection closed');
        },
      );

      await expectLater(
        service.send(
          apiKey: 'test-key',
          from: '+254711222333',
          to: '+254712000111',
          content: 'hello',
        ),
        throwsA(
          isA<HttpsmsException>().having(
            (error) => error.message,
            'message',
            contains('Check the HTTPSMS queue before trying again'),
          ),
        ),
      );
    });

    test('warns that the outcome is unknown after a provider server error',
        () async {
      final service = HttpsmsService(
        transport: (_, {required headers, required body}) async =>
            http.Response('private provider response', 500),
      );

      await expectLater(
        service.send(
          apiKey: 'test-key',
          from: '+254711222333',
          to: '+254712000111',
          content: 'hello',
        ),
        throwsA(
          isA<HttpsmsException>().having(
            (error) => error.message,
            'message',
            contains('outcome is unknown'),
          ),
        ),
      );
    });
  });
}
