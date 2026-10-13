import 'package:dio/dio.dart';

/// Plain-language explanation for a failed screen load.
///
/// Screens used to answer every failure with "Check your connection", which is
/// wrong and unhelpful when the server actually said the user may not see this.
String loadErrorSubtitle(Object? error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 403) {
      return 'You don’t have permission to view this. Ask an admin to grant access.';
    }
    if (status != null && status >= 500) {
      return 'Something went wrong on our side. Please try again in a moment.';
    }
  }
  return 'Check your connection and try again.';
}

/// True when retrying cannot help because the server refused the request.
bool isPermissionDenied(Object? error) =>
    error is DioException && error.response?.statusCode == 403;
