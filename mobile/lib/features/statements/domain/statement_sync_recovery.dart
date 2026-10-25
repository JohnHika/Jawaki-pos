import 'package:dio/dio.dart';

/// Older APIs reject offline customer IDs as UUIDs. Newer APIs accept them,
/// then report that the customer is missing until the queued customer event
/// reaches the workspace. Both errors should lead to the same in-app recovery.
bool statementNeedsCustomerSync(Object error) {
  if (error is! DioException) return false;

  final message = _messageFromPayload(error.response?.data);

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
