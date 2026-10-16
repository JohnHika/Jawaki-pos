import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

class _OfflineApi extends ApiClient {
  _OfflineApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> getNotifications({
    int limit = 50,
    String? before,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/notifications'),
      type: DioExceptionType.connectionError,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a failed load is not reported as "all caught up"',
      (tester) async {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
    getIt.registerSingleton<ApiClient>(_OfflineApi());
    addTearDown(() {
      if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
    });

    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              const ProviderScope(child: NotificationsScreen())),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Couldn't load notifications"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text("You're all caught up"), findsNothing);
  });
}
