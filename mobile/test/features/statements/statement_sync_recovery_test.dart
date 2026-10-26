import 'package:axon_pos/features/statements/domain/statement_sync_recovery.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException responseError(int status, Object data) => DioException(
        requestOptions: RequestOptions(path: '/statements/preview'),
        response: Response(
          requestOptions: RequestOptions(path: '/statements/preview'),
          statusCode: status,
          data: data,
        ),
      );

  group('statementNeedsCustomerSync', () {
    test('does not sync-retry legacy IDs rejected by older API validation', () {
      expect(
        statementNeedsCustomerSync(responseError(
          400,
          {
            'message': ['customerId must be a UUID']
          },
        )),
        isFalse,
      );
    });

    test('does not sync-retry a nested UUID validation message', () {
      expect(
        statementNeedsCustomerSync(responseError(
          400,
          {
            'error': {
              'message': 'Validation failed: customerId must be a UUID',
            },
          },
        )),
        isFalse,
      );
    });

    test('recovers a customer missing from the workspace', () {
      expect(
        statementNeedsCustomerSync(
          responseError(404, {'message': 'Customer not found'}),
        ),
        isTrue,
      );
    });

    test('does not try customer sync for a missing API route', () {
      expect(
        statementNeedsCustomerSync(
          responseError(
              404, {'message': 'Cannot GET /api/v1/statements/preview'}),
        ),
        isFalse,
      );
    });

    test('does not turn unrelated failures into customer syncs', () {
      expect(
        statementNeedsCustomerSync(
          responseError(403, {'message': 'Forbidden resource'}),
        ),
        isFalse,
      );
    });
  });
}
