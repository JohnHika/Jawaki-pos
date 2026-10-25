import 'dart:async';

import 'package:dio/dio.dart';

/// Turns an API failure into a sentence a shop owner can act on.
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    final message = _messageFromPayload(data);
    if (message.isNotEmpty) {
      final validationMessage = _friendlyValidationMessage(message);
      if (validationMessage != null) return validationMessage;
      // Old API deployments returned Express/Nest's raw route miss to the
      // app, exposing paths like "Cannot POST /api/v1/mpesa/parse".
      if (RegExp(r'^Cannot (?:GET|POST|PUT|PATCH|DELETE) /api/v\d+/')
          .hasMatch(message)) {
        return 'This feature is temporarily unavailable. Update Counterbase and try again.';
      }
      return message;
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session expired. Sign in again.';
    if (status == 403) return "You don't have permission to do that.";
    if (status == 404) return 'That was not found.';
    if (status == 429) return 'Too many requests. Wait a moment and try again.';
    if (status != null && status >= 500) {
      return 'Server error. Please try again in a moment.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return "Couldn't reach the server. Check your internet and try again.";
    }
  }
  if (error is TimeoutException) {
    return "Couldn't finish in time. Check your connection and try again.";
  }
  if (error is Exception) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (_isSafeExceptionMessage(message)) return message;
  }
  return 'Something went wrong. Please try again.';
}

bool _isSafeExceptionMessage(String message) {
  if (message.isEmpty || message.length > 180 || message.contains('\n')) {
    return false;
  }
  return !RegExp(
    r'(?:DioException|SocketException|HttpException|FormatException|StateError|TypeError|RangeError|TimeoutException|stack trace|traceback|package:|file:///|https?://|/api/v\d+/|sqlite|postgres|prisma|constraint|errno|failed host lookup|connection refused|connection reset|handshake|certificate|status code|response body|null check operator|not a subtype|unhandled exception|error:)',
    caseSensitive: false,
  ).hasMatch(message);
}

String? _friendlyValidationMessage(String message) {
  if (RegExp(r'\bcustomerid\s+must\s+be\s+a\s+uuid\b', caseSensitive: false)
      .hasMatch(message)) {
    return 'This customer record needs to sync before a statement can be sent. Reconnect and try again.';
  }
  return null;
}

/// API gateways may wrap a validation error in one or more `error` objects.
/// Unwrap those common envelopes so the app can still show a useful message.
String _messageFromPayload(Object? payload) {
  if (payload is String) return payload.trim();
  if (payload is List) {
    for (final item in payload) {
      final message = _messageFromPayload(item);
      if (message.isNotEmpty) return message;
    }
    return '';
  }
  if (payload is Map) {
    for (final key in const ['message', 'error', 'detail']) {
      final message = _messageFromPayload(payload[key]);
      if (message.isNotEmpty) return message;
    }
  }
  return '';
}

/// "just now", "5 min ago", "3 h ago", "Yesterday", "12 Oct".
String timeAgo(DateTime when, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(when);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${when.day} ${months[when.month - 1]}';
}

/// "KES 12,500" — whole shillings, thousands separated.
String kesWhole(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '${negative ? '-' : ''}KES $out';
}

double asDouble(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fallback;

int asInt(Object? v, [int fallback = 0]) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback;

DateTime? asDate(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
