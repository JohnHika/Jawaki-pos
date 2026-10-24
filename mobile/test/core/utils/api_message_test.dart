import 'package:axon_pos/core/utils/api_message.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException responseError(int status, Object data) => DioException(
        requestOptions: RequestOptions(path: '/checkout'),
        response: Response(
          requestOptions: RequestOptions(path: '/checkout'),
          statusCode: status,
          data: data,
        ),
      );

  test('hides an outdated API route from checkout errors', () {
    expect(
      apiErrorMessage(responseError(
        404,
        {'message': 'Cannot POST /api/v1/mpesa/parse'},
      )),
      'This feature is temporarily unavailable. Update Counterbase and try again.',
    );
  });

  test('turns server validation arrays into readable field guidance', () {
    expect(
      apiErrorMessage(responseError(
        400,
        {
          'message': ['Enter a valid amount', 'Phone number is required']
        },
      )),
      'Enter a valid amount',
    );
  });

  test('uses a calm fallback for non-network implementation exceptions', () {
    expect(apiErrorMessage(StateError('SQLite constraint stack')),
        'Something went wrong. Please try again.');
  });
}
