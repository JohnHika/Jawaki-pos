import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/utils/load_error.dart';

DioException _err(int? status) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: status == null
          ? null
          : Response(requestOptions: RequestOptions(path: '/x'), statusCode: status),
    );

void main() {
  test('403 explains the missing permission and offers no retry', () {
    expect(loadErrorSubtitle(_err(403)), contains('permission'));
    expect(isPermissionDenied(_err(403)), isTrue);
  });

  test('server errors are not blamed on the connection', () {
    expect(loadErrorSubtitle(_err(500)), contains('our side'));
    expect(isPermissionDenied(_err(500)), isFalse);
  });

  test('no response or other errors fall back to the connection hint', () {
    expect(loadErrorSubtitle(_err(null)), contains('connection'));
    expect(loadErrorSubtitle(Exception('x')), contains('connection'));
    expect(isPermissionDenied(null), isFalse);
  });
}
