import 'package:dio/dio.dart';

/// Older APIs reject offline customer IDs as UUIDs. Newer APIs accept them,
/// then report that the customer is missing until the queued customer event
/// reaches the workspace. Both errors should lead to the same in-app recovery.
bool statementNeedsCustomerSync(Object error) {
  if (error is! DioException) return false;

  final payload = error.response?.data;
  final raw = payload is Map ? payload['message'] : payload;
  final message = raw is List ? raw.join(' ') : raw?.toString() ?? '';

  if (RegExp(r'customerId\s+must\s+be\s+a\s+UUID', caseSensitive: false)
      .hasMatch(message)) {
    return true;
  }

  // Only recover on a customer-specific 404. A missing API route also returns
  // 404 on older deployments, but syncing a customer cannot fix that problem.
  return error.response?.statusCode == 404 &&
      RegExp(r'customer\s+(?:not found|does not exist|was not found)',
              caseSensitive: false)
          .hasMatch(message);
}
