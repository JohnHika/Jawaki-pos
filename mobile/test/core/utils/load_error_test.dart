import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/utils/load_error.dart';

DioException _err(
  int? status, {
  DioExceptionType type = DioExceptionType.unknown,
}) =>
    DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/x'), statusCode: status),
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

  test('network failures hint connection and unknown errors stay generic', () {
    expect(
      loadErrorSubtitle(_err(null, type: DioExceptionType.connectionError)),
      contains('internet'),
    );
    expect(loadErrorSubtitle(_err(null)),
        'Something went wrong. Please try again.');
    expect(loadErrorSubtitle(Exception('x')),
        'Something went wrong. Please try again.');
    expect(isPermissionDenied(null), isFalse);
  });
}
