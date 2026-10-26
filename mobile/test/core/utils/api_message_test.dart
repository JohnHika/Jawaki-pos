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

  test('unwraps a gateway-wrapped customer UUID validation message', () {
    expect(
      apiErrorMessage(responseError(
        400,
        {
          'error': {
            'message': 'Validation failed: customerId must be a UUID',
          },
        },
      )),
      'The statement service needs an update before it can handle this customer record. Try again after the server is updated.',
    );
  });

  test('uses a calm fallback for non-network implementation exceptions', () {
    expect(apiErrorMessage(StateError('SQLite constraint stack')),
        'Something went wrong. Please try again.');
  });

  test('keeps concise user-facing exception messages', () {
    expect(
      apiErrorMessage(Exception('Could not load subscription')),
      'Could not load subscription',
    );
  });

  test('hides transport details from plain exception messages', () {
    expect(
      apiErrorMessage(Exception('SocketException: Failed host lookup')),
      'Something went wrong. Please try again.',
    );
  });
}
