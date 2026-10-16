import 'dart:convert';
import 'dart:typed_data';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/stock_request_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the request and replies the way the backend's ValidationPipe does:
/// 400 unless the body carries a valid `status`.
class _Backend implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    final body = options.data as Map;
    final ok = const ['APPROVED', 'REJECTED', 'FULFILLED']
        .contains(body['status']);
    return ResponseBody.fromString(
      jsonEncode(ok
          ? {'id': 'sr-1', 'status': body['status']}
          : {
              'message': ['Status must be APPROVED, REJECTED, or FULFILLED'],
            }),
      ok ? 200 : 400,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Backend backend;
  late StockRequestService service;

  setUp(() {
    backend = _Backend();
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = backend;
    service = StockRequestService(ApiClient(dio));
  });

  for (final status in ['APPROVED', 'REJECTED', 'FULFILLED']) {
    test('resolveRequest sends status $status the server accepts', () async {
      final res = await service.resolveRequest(
        'sr-1',
        status: status,
        resolution: 'Handled by the manager',
      );
      expect(res['status'], status);
      expect(backend.last!.method, 'PUT');
      expect(backend.last!.path, '/inventory/stock-requests/sr-1/resolve');
      expect((backend.last!.data as Map)['status'], status);
      expect((backend.last!.data as Map).containsKey('approve'), isFalse);
    });
  }
}
