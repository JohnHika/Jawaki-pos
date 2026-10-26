import 'package:dio/dio.dart';

/// A customer-specific 404 may mean the local customer has not reached the
/// workspace yet. UUID validation failures indicate an outdated API contract
/// and cannot be repaired by replaying the same customer ID.
bool statementNeedsCustomerSync(Object error) {
  if (error is! DioException) return false;

  final message = _messageFromPayload(error.response?.data);
  // Only recover on a customer-specific 404. A missing API route also returns
  // 404 on older deployments, but syncing a customer cannot fix that problem.
  return error.response?.statusCode == 404 &&
      RegExp(r'customer\s+(?:not found|does not exist|was not found)',
              caseSensitive: false)
          .hasMatch(message);
}

/// A UUID validation response or a missing statement route is a deployed API
/// contract problem. Repeating the same request or syncing the customer cannot
/// repair it, so the UI should show an update notice without a retry action.
bool statementServiceNeedsUpdate(Object error) {
  if (error is! DioException) return false;

  final message = _messageFromPayload(error.response?.data);
  return RegExp(r'\bcustomerid\s+must\s+be\s+a\s+uuid\b', caseSensitive: false)
          .hasMatch(message) ||
      RegExp(
        r'^Cannot (?:GET|POST|PUT|PATCH|DELETE) /api/v\d+/statements/(?:preview|links|claims)(?:\b|/|\?)',
        caseSensitive: false,
      ).hasMatch(message);
}

String _messageFromPayload(Object? payload) {
  if (payload is String) return payload;
  if (payload is List) {
    return payload
        .map(_messageFromPayload)
        .where((value) => value.isNotEmpty)
        .join(' ');
  }
  if (payload is Map) {
    for (final key in const ['message', 'error', 'detail']) {
      final message = _messageFromPayload(payload[key]);
      if (message.isNotEmpty) return message;
    }
  }
  return '';
}
