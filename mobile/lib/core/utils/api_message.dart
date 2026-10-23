import 'package:dio/dio.dart';

/// Turns an API failure into a sentence a shop owner can act on.
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        // Old API deployments returned Express/Nest's raw route miss to the
        // app, exposing paths like "Cannot POST /api/v1/mpesa/parse".
        if (RegExp(r'^Cannot (?:GET|POST|PUT|PATCH|DELETE) /api/v\d+/')
            .hasMatch(message.trim())) {
          return 'This feature is temporarily unavailable. Update Counterbase and try again.';
        }
        return message;
      }
      if (message is List && message.isNotEmpty)
        return message.first.toString();
      final inner = data['error'];
      if (inner is Map && inner['message'] is String) {
        return inner['message'] as String;
      }
    }
    final status = error.response?.statusCode;
    if (status == 403) return "You don't have permission to do that.";
    if (status == 404) return 'That was not found.';
    if (status != null && status >= 500) {
      return 'Server error. Please try again in a moment.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return "Couldn't reach the server. Check your internet and try again.";
    }
  }
  return 'Something went wrong. Please try again.';
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
