import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../di/injection.dart';

/// Provider for ApiClient
final apiClientProvider = Provider<ApiClient>((ref) {
  return getIt<ApiClient>();
});
